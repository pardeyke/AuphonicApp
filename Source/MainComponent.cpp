#include "MainComponent.h"
#include "SettingsComponent.h"
#include "DesktopNotification.h"

MainComponent::MainComponent (const juce::File& initialFile)
{
    addAndMakeVisible (settingsButton);
    addAndMakeVisible (fileListComponent);
    addChildComponent (audioPlayerComponent);
    addAndMakeVisible (previewDurationComponent);
    addAndMakeVisible (creditsComponent);
    addAndMakeVisible (presetListComponent);
    addAndMakeVisible (savePresetButton);
    addAndMakeVisible (optionsViewport);
    addAndMakeVisible (statusComponent);
    addAndMakeVisible (processButton);
    addAndMakeVisible (cancelButton);

    optionsViewport.setViewedComponent (&manualOptionsComponent, false);
    optionsViewport.setScrollBarsShown (true, false);

    settingsButton.onClick    = [this] { onSettingsClicked(); };
    processButton.onClick     = [this] { onProcessClicked(); };
    cancelButton.onClick      = [this] { onCancelClicked(); };
    savePresetButton.onClick  = [this] { onSavePresetClicked(); };

    cancelButton.setEnabled (false);

    fileListComponent.onFilesChanged = [this]
    {
        auto files = fileListComponent.getFiles();

        audioPlayerComponent.clearProcessedFile();

        if (files.size() == 1)
        {
            audioPlayerComponent.setVisible (true);
            audioPlayerComponent.loadFile (files[0]);
            creditsComponent.setFile (files[0]);
            previewDurationComponent.setFileDuration (creditsComponent.getFileDurationSeconds());
            creditsComponent.setPreviewDurationSeconds (previewDurationComponent.getPreviewDurationSeconds());
            manualOptionsComponent.setFileChannelCount (creditsComponent.getFileChannels());
        }
        else
        {
            audioPlayerComponent.setVisible (false);
            creditsComponent.setFiles (files);
            creditsComponent.setPreviewDurationSeconds (previewDurationComponent.getPreviewDurationSeconds());
            if (! files.isEmpty())
            {
                // Use first file for channel count info
                creditsComponent.setFile (files[0]);
                manualOptionsComponent.setFileChannelCount (creditsComponent.getFileChannels());
                creditsComponent.setFiles (files); // re-set to show batch info
            }
        }

        resized();
        manualOptionsComponent.setSize (optionsViewport.getMaximumVisibleWidth(),
                                        manualOptionsComponent.getRequiredHeight());
        updateButtonStates();
    };

    previewDurationComponent.onChange = [this]
    {
        creditsComponent.setPreviewDurationSeconds (previewDurationComponent.getPreviewDurationSeconds());
    };
    presetListComponent.onSelectionChanged = [this]
    {
        auto uuid = presetListComponent.getSelectedPresetUuid();
        if (uuid.isNotEmpty())
        {
            apiClient->fetchPresetDetails (uuid, [this] (bool success, const juce::var& algorithms)
            {
                if (success)
                    manualOptionsComponent.applyApiSettings (algorithms);
                saveCurrentConfig();
                updateButtonStates();
            });
        }
        else
        {
            saveCurrentConfig();
            updateButtonStates();
        }
    };

    manualOptionsComponent.onChange = [this]
    {
        if (presetListComponent.hasSelection() || presetListComponent.getBasePresetUuid().isNotEmpty())
            presetListComponent.setModified (true);
        saveCurrentConfig();
        updateButtonStates();
    };

    // Init API client
    apiClient = std::make_unique<AuphonicApiClient> (settingsManager.getApiToken());
    batchWorkflow = std::make_unique<BatchWorkflow> (*apiClient);
    batchWorkflow->setListener (this);

    if (initialFile.existsAsFile())
    {
        juce::Array<juce::File> files;
        files.add (initialFile);
        fileListComponent.addFiles (files);
    }

    // Restore manual settings before presets load (presets restore happens in refreshPresets callback)
    restoreLastConfig();

    connectAndFetchUser();
    audioPlayerComponent.setOutputDevice (settingsManager.getAudioOutputDevice());

    updateButtonStates();
    setSize (520, 862);
}

MainComponent::~MainComponent()
{
    batchWorkflow->setListener (nullptr);
}

bool MainComponent::keyPressed (const juce::KeyPress& key)
{
    if (key == juce::KeyPress::spaceKey && audioPlayerComponent.hasFileLoaded())
    {
        audioPlayerComponent.togglePlayPause();
        return true;
    }

    return false;
}

void MainComponent::paint (juce::Graphics& g)
{
    g.fillAll (getLookAndFeel().findColour (juce::ResizableWindow::backgroundColourId));
}

void MainComponent::resized()
{
    auto area = getLocalBounds().reduced (12);

    // Credits at top
    creditsComponent.setBounds (area.removeFromTop (20));
    area.removeFromTop (6);

    // File list area (dynamic height based on file count)
    fileListComponent.setBounds (area.removeFromTop (fileListComponent.getDesiredHeight()));

    // Audio player (only takes space when visible)
    if (audioPlayerComponent.isVisible())
    {
        area.removeFromTop (8);
        audioPlayerComponent.setBounds (area.removeFromTop (100));
    }

    area.removeFromTop (8);

    // Preview duration
    previewDurationComponent.setBounds (area.removeFromTop (26));

    area.removeFromTop (8);

    // Preset row
    auto presetRow = area.removeFromTop (26);
    savePresetButton.setBounds (presetRow.removeFromRight (90));
    presetRow.removeFromRight (6);
    presetListComponent.setBounds (presetRow);

    area.removeFromTop (8);

    // Status at very bottom (no padding below)
    statusComponent.setBounds (area.removeFromBottom (50));

    // Buttons above status
    area.removeFromBottom (8);
    auto buttonArea = area.removeFromBottom (32);
    settingsButton.setBounds (buttonArea.removeFromRight (32));
    buttonArea.removeFromRight (8);
    auto buttonWidth = 120;
    auto totalButtonWidth = buttonWidth * 2 + 16;
    auto startX = (buttonArea.getWidth() - totalButtonWidth) / 2;
    processButton.setBounds (buttonArea.getX() + startX, buttonArea.getY(), buttonWidth, 32);
    cancelButton.setBounds (buttonArea.getX() + startX + buttonWidth + 16, buttonArea.getY(), buttonWidth, 32);

    area.removeFromBottom (8);

    // Manual options in viewport (fills remaining space)
    optionsViewport.setBounds (area);

    int vpWidth = optionsViewport.getMaximumVisibleWidth();
    manualOptionsComponent.setSize (vpWidth, manualOptionsComponent.getRequiredHeight());
}

void MainComponent::setFile (const juce::File& file)
{
    juce::Array<juce::File> files;
    files.add (file);
    fileListComponent.addFiles (files);
}

void MainComponent::onSettingsClicked()
{
    SettingsComponent::showDialog (settingsManager, this, [this]
    {
        apiClient->setToken (settingsManager.getApiToken());
        audioPlayerComponent.setOutputDevice (settingsManager.getAudioOutputDevice());
        connectAndFetchUser();
    });
}

void MainComponent::onProcessClicked()
{
    auto files = fileListComponent.getFiles();
    if (files.isEmpty())
    {
        juce::AlertWindow::showMessageBoxAsync (juce::MessageBoxIconType::WarningIcon,
            "No Files", "Please select audio files first.");
        return;
    }

    if (! settingsManager.hasApiToken())
    {
        juce::AlertWindow::showMessageBoxAsync (juce::MessageBoxIconType::WarningIcon,
            "No Token", "Please enter your API token in Settings first.");
        return;
    }

    // Use preset UUID only if unmodified; otherwise send manual settings
    auto presetUuid = presetListComponent.getSelectedPresetUuid(); // empty if modified or no preset
    juce::var manualSettings;

    if (presetUuid.isEmpty())
    {
        if (! manualOptionsComponent.hasAnyEnabled())
        {
            juce::AlertWindow::showMessageBoxAsync (juce::MessageBoxIconType::WarningIcon,
                "No Options", "Please select a preset or enable at least one processing option.");
            return;
        }
        manualSettings = manualOptionsComponent.getSettings();
    }

    audioPlayerComponent.stop();
    saveCurrentConfig();

    fileListComponent.setEnabled (false);
    statusComponent.reset();

    batchWorkflow->start (files, presetUuid, manualSettings,
                          manualOptionsComponent.shouldAvoidOverwrite(),
                          manualOptionsComponent.getOutputSuffix(),
                          manualOptionsComponent.shouldWriteSettingsXml(),
                          manualOptionsComponent.getSelectedChannel(),
                          previewDurationComponent.getPreviewDurationSeconds());

    updateButtonStates();
}

void MainComponent::onCancelClicked()
{
    batchWorkflow->cancel();
    fileListComponent.setEnabled (true);
    statusComponent.reset();
    updateButtonStates();
}

void MainComponent::refreshCredits()
{
    apiClient->fetchUserInfo ([this] (bool success, int /*httpStatus*/, const UserCredits& credits)
    {
        if (success)
            creditsComponent.setCredits (credits);
    });
}

void MainComponent::connectAndFetchUser()
{
    if (settingsManager.hasApiToken())
    {
        statusComponent.setStatus ("Connecting...");
        apiClient->fetchUserInfo ([this] (bool success, int httpStatus, const UserCredits& credits)
        {
            if (success)
            {
                creditsComponent.setCredits (credits);
                statusComponent.setStatus ("Ready.");
                refreshPresets();
            }
            else if (httpStatus == 401 || httpStatus == 403)
            {
                statusComponent.setStatus ("Invalid API token. Please check Settings.");
            }
            else
            {
                statusComponent.setStatus ("Connection failed. Check your internet.");
            }
        });
    }
    else
    {
        statusComponent.setStatus ("No API token. Please configure in Settings.");
    }
}

void MainComponent::refreshPresets()
{
    apiClient->fetchPresets ([this] (bool success, const juce::Array<AuphonicPreset>& presets)
    {
        if (success)
        {
            presetListComponent.setPresets (presets);

            auto lastUuid = settingsManager.getLastPresetUuid();
            presetListComponent.setSelectedUuid (lastUuid);
            updateButtonStates();
        }
    });
}

void MainComponent::onSavePresetClicked()
{
    auto defaultName = presetListComponent.getBasePresetName();

    auto* aw = new juce::AlertWindow ("Save Preset", "Enter a name for this preset:", juce::MessageBoxIconType::QuestionIcon);
    aw->addTextEditor ("name", defaultName, "Preset name:");
    aw->addButton ("Save", 1, juce::KeyPress (juce::KeyPress::returnKey));
    aw->addButton ("Cancel", 0, juce::KeyPress (juce::KeyPress::escapeKey));

    aw->enterModalState (true, juce::ModalCallbackFunction::create ([this, aw] (int result)
    {
        auto name = aw->getTextEditorContents ("name").trim();
        delete aw;

        if (result == 0 || name.isEmpty())
            return;

        auto settings = manualOptionsComponent.getSettings();

        apiClient->savePreset (name, settings, [this] (bool success, const juce::String& /*uuid*/, const juce::String& error)
        {
            if (success)
            {
                refreshPresets();
                statusComponent.setStatus ("Preset saved.");
            }
            else
            {
                juce::AlertWindow::showMessageBoxAsync (juce::MessageBoxIconType::WarningIcon,
                    "Save Failed", error);
            }
        });
    }));
}

void MainComponent::saveCurrentConfig()
{
    // Save the base preset UUID (even if modified, so we can restore it)
    auto uuid = presetListComponent.getBasePresetUuid();
    if (uuid.isEmpty())
        uuid = presetListComponent.getSelectedPresetUuid();
    settingsManager.setLastPresetUuid (uuid);

    auto widgetState = manualOptionsComponent.getWidgetState();
    settingsManager.setLastManualSettings (juce::JSON::toString (widgetState));
}

void MainComponent::restoreLastConfig()
{
    auto manualJson = settingsManager.getLastManualSettings();
    if (manualJson.isNotEmpty())
    {
        auto parsed = juce::JSON::parse (manualJson);
        manualOptionsComponent.applyWidgetState (parsed);
    }
}

void MainComponent::updateButtonStates()
{
    bool isIdle = ! batchWorkflow->isRunning();

    processButton.setEnabled (isIdle && fileListComponent.hasFiles());
    cancelButton.setEnabled (! isIdle);

    bool canSavePreset = isIdle
        && manualOptionsComponent.hasAnyEnabled()
        && settingsManager.hasApiToken()
        && (presetListComponent.isModified() || ! presetListComponent.hasSelection());
    savePresetButton.setEnabled (canSavePreset);
}

// BatchWorkflow::Listener

void MainComponent::batchFileStatusChanged (int index, const juce::String& status)
{
    fileListComponent.setFileStatus (index, status);
}

void MainComponent::batchProgressChanged (int completed, int total, const juce::String& overallStatus)
{
    statusComponent.setStatus (overallStatus);

    if (total > 0)
        statusComponent.setProgress ((double) completed / (double) total);
}

void MainComponent::batchCompleted (const juce::Array<BatchWorkflow::FileResult>& results)
{
    fileListComponent.setEnabled (true);
    statusComponent.setProgress (-1.0);

    int successCount = 0;
    int errorCount = 0;
    for (auto& r : results)
    {
        if (r.success)
            ++successCount;
        else
            ++errorCount;
    }

    if (results.size() == 1)
    {
        // Single file — behave like before
        auto r = results[0];
        if (r.success)
        {
            statusComponent.setStatus ("Complete! Saved to: " + r.outputFile.getFileName());
            statusComponent.setOutputFile (r.outputFile);
            audioPlayerComponent.loadProcessedFile (r.outputFile);
        }
        else
        {
            statusComponent.setStatus ("Error: " + r.errorMessage);
            juce::AlertWindow::showMessageBoxAsync (juce::MessageBoxIconType::WarningIcon,
                "Error", r.errorMessage);
        }
    }
    else
    {
        // Batch — show summary
        juce::String summary = juce::String (successCount) + "/" + juce::String (results.size()) + " files completed";
        if (errorCount > 0)
            summary += " (" + juce::String (errorCount) + " failed)";

        statusComponent.setStatus (summary);

        // Show in Finder for the output directory of first successful file
        for (auto& r : results)
        {
            if (r.success && r.outputFile.existsAsFile())
            {
                statusComponent.setOutputDirectory (r.outputFile.getParentDirectory());
                break;
            }
        }
    }

    refreshCredits();

    juce::String notifBody;
    if (results.size() == 1 && results[0].success)
        notifBody = "Saved to: " + results[0].outputFile.getFileName();
    else
        notifBody = juce::String (successCount) + "/" + juce::String (results.size()) + " files processed successfully";

    DesktopNotification::show ("Processing Complete", notifBody);

    updateButtonStates();
}
