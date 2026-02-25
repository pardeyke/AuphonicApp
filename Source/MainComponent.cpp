#include "MainComponent.h"
#include "SettingsComponent.h"

MainComponent::MainComponent (const juce::File& initialFile)
{
    addAndMakeVisible (settingsButton);
    addAndMakeVisible (fileDropComponent);
    addAndMakeVisible (audioPlayerComponent);
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

    fileDropComponent.onFileSelected = [this] (const juce::File& f)
    {
        audioPlayerComponent.clearProcessedFile();
        audioPlayerComponent.loadFile (f);
        creditsComponent.setFile (f);
        previewDurationComponent.setFileDuration (creditsComponent.getFileDurationSeconds());
        creditsComponent.setPreviewDurationSeconds (previewDurationComponent.getPreviewDurationSeconds());
        manualOptionsComponent.setFileChannelCount (creditsComponent.getFileChannels());
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
    workflow = std::make_unique<ProcessingWorkflow> (*apiClient);
    workflow->setListener (this);

    if (initialFile.existsAsFile())
    {
        fileDropComponent.setFile (initialFile);
        audioPlayerComponent.loadFile (initialFile);
        creditsComponent.setFile (initialFile);
        manualOptionsComponent.setFileChannelCount (creditsComponent.getFileChannels());
    }

    // Restore manual settings before presets load (presets restore happens in refreshPresets callback)
    restoreLastConfig();

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

    audioPlayerComponent.setOutputDevice (settingsManager.getAudioOutputDevice());

    updateButtonStates();
    setSize (520, 822);
}

MainComponent::~MainComponent()
{
    workflow->setListener (nullptr);
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

    // File drop area
    fileDropComponent.setBounds (area.removeFromTop (60));

    area.removeFromTop (8);

    // Audio player
    audioPlayerComponent.setBounds (area.removeFromTop (100));

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
    fileDropComponent.setFile (file);
}

void MainComponent::onSettingsClicked()
{
    SettingsComponent::showDialog (settingsManager, this, [this]
    {
        apiClient->setToken (settingsManager.getApiToken());
        audioPlayerComponent.setOutputDevice (settingsManager.getAudioOutputDevice());

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
    });
}

void MainComponent::onProcessClicked()
{
    auto file = fileDropComponent.getFile();
    if (! file.existsAsFile())
    {
        juce::AlertWindow::showMessageBoxAsync (juce::MessageBoxIconType::WarningIcon,
            "No File", "Please select an audio file first.");
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
    workflow->start (file, presetUuid, manualSettings,
                     manualOptionsComponent.shouldAvoidOverwrite(),
                     manualOptionsComponent.shouldWriteSettingsXml(),
                     manualOptionsComponent.getSelectedChannel(),
                     previewDurationComponent.getPreviewDurationSeconds());
}

void MainComponent::onCancelClicked()
{
    workflow->cancel();
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
    bool isIdle = workflow->getState() == ProcessingWorkflow::State::Idle
               || workflow->getState() == ProcessingWorkflow::State::Done
               || workflow->getState() == ProcessingWorkflow::State::Error;

    processButton.setEnabled (isIdle && fileDropComponent.getFile().existsAsFile());
    cancelButton.setEnabled (! isIdle);

    bool canSavePreset = isIdle
        && manualOptionsComponent.hasAnyEnabled()
        && settingsManager.hasApiToken()
        && (presetListComponent.isModified() || ! presetListComponent.hasSelection());
    savePresetButton.setEnabled (canSavePreset);
}

void MainComponent::workflowStateChanged (ProcessingWorkflow::State)
{
    updateButtonStates();
}

void MainComponent::workflowProgressChanged (double progress, const juce::String& statusText)
{
    statusComponent.setStatus (statusText);
    statusComponent.setProgress (progress);
}

void MainComponent::workflowCompleted()
{
    statusComponent.setStatus ("Complete! File saved.");
    statusComponent.setProgress (1.0);
    refreshCredits();

    auto outputFile = workflow->getLastOutputFile();
    audioPlayerComponent.loadProcessedFile (outputFile);

    auto* aw = new juce::AlertWindow ("Success",
        "Processing complete. Output saved to:\n" + outputFile.getFullPathName(),
        juce::MessageBoxIconType::InfoIcon);
    aw->addButton ("OK", 0);
    aw->addButton ("Show in Finder", 1);
    aw->enterModalState (true, juce::ModalCallbackFunction::create ([outputFile] (int result)
    {
        if (result == 1)
            outputFile.revealToUser();
    }), true);
}

void MainComponent::workflowFailed (const juce::String& errorMessage)
{
    statusComponent.setStatus ("Error: " + errorMessage);
    statusComponent.setProgress (-1.0);

    juce::AlertWindow::showMessageBoxAsync (juce::MessageBoxIconType::WarningIcon,
        "Error", errorMessage);
}
