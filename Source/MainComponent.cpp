#include "MainComponent.h"
#include "SettingsComponent.h"

MainComponent::MainComponent (const juce::File& initialFile)
{
    addAndMakeVisible (settingsButton);
    addAndMakeVisible (titleLabel);
    addAndMakeVisible (fileDropComponent);
    addAndMakeVisible (creditsComponent);
    addAndMakeVisible (presetListComponent);
    addAndMakeVisible (optionsViewport);
    addAndMakeVisible (statusComponent);
    addAndMakeVisible (processButton);
    addAndMakeVisible (cancelButton);

    optionsViewport.setViewedComponent (&manualOptionsComponent, false);
    optionsViewport.setScrollBarsShown (true, false);

    titleLabel.setFont (juce::FontOptions (18.0f, juce::Font::bold));
    titleLabel.setJustificationType (juce::Justification::centredRight);

    settingsButton.onClick = [this] { onSettingsClicked(); };
    processButton.onClick  = [this] { onProcessClicked(); };
    cancelButton.onClick   = [this] { onCancelClicked(); };

    cancelButton.setEnabled (false);

    fileDropComponent.onFileSelected = [this] (const juce::File& f)
    {
        creditsComponent.setFile (f);
        updateButtonStates();
    };
    presetListComponent.onSelectionChanged = [this] { updateButtonStates(); };

    // Init API client
    apiClient = std::make_unique<AuphonicApiClient> (settingsManager.getApiToken());
    workflow = std::make_unique<ProcessingWorkflow> (*apiClient);
    workflow->setListener (this);

    if (initialFile.existsAsFile())
    {
        fileDropComponent.setFile (initialFile);
        creditsComponent.setFile (initialFile);
    }

    if (settingsManager.hasApiToken())
    {
        refreshPresets();
        refreshCredits();
    }

    updateButtonStates();
    setSize (520, 680);
}

MainComponent::~MainComponent()
{
    workflow->setListener (nullptr);
}

void MainComponent::paint (juce::Graphics& g)
{
    g.fillAll (getLookAndFeel().findColour (juce::ResizableWindow::backgroundColourId));
}

void MainComponent::resized()
{
    auto area = getLocalBounds().reduced (12);

    // Top bar
    auto topBar = area.removeFromTop (28);
    settingsButton.setBounds (topBar.removeFromLeft (80));
    titleLabel.setBounds (topBar);

    area.removeFromTop (10);

    // File drop area
    fileDropComponent.setBounds (area.removeFromTop (60));

    area.removeFromTop (6);
    creditsComponent.setBounds (area.removeFromTop (20));
    area.removeFromTop (6);

    // Preset
    presetListComponent.setBounds (area.removeFromTop (26));

    area.removeFromTop (8);

    // Bottom: status + buttons (fixed)
    auto bottomArea = area.removeFromBottom (32);
    auto buttonWidth = 120;
    auto totalButtonWidth = buttonWidth * 2 + 16;
    auto startX = (bottomArea.getWidth() - totalButtonWidth) / 2;
    processButton.setBounds (bottomArea.getX() + startX, bottomArea.getY(), buttonWidth, 32);
    cancelButton.setBounds (bottomArea.getX() + startX + buttonWidth + 16, bottomArea.getY(), buttonWidth, 32);

    area.removeFromBottom (10);
    statusComponent.setBounds (area.removeFromBottom (50));
    area.removeFromBottom (8);

    // Manual options in viewport (fills remaining space)
    optionsViewport.setBounds (area);

    // Size the manual options component to viewport width, tall enough for content
    // Use a generous height — the viewport will clip & scroll as needed
    int vpWidth = optionsViewport.getMaximumVisibleWidth();
    manualOptionsComponent.setSize (vpWidth, 600);
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
        refreshPresets();
        refreshCredits();
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

    auto presetUuid = presetListComponent.getSelectedPresetUuid();
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

    workflow->start (file, presetUuid, manualSettings);
}

void MainComponent::onCancelClicked()
{
    workflow->cancel();
    statusComponent.reset();
    updateButtonStates();
}

void MainComponent::refreshCredits()
{
    apiClient->fetchUserInfo ([this] (bool success, const UserCredits& credits)
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
            presetListComponent.setPresets (presets);
    });
}

void MainComponent::updateButtonStates()
{
    bool isIdle = workflow->getState() == ProcessingWorkflow::State::Idle
               || workflow->getState() == ProcessingWorkflow::State::Done
               || workflow->getState() == ProcessingWorkflow::State::Error;

    processButton.setEnabled (isIdle && fileDropComponent.getFile().existsAsFile());
    cancelButton.setEnabled (! isIdle);
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

    juce::AlertWindow::showMessageBoxAsync (juce::MessageBoxIconType::InfoIcon,
        "Success", "Processing complete. Output saved to:\n" + fileDropComponent.getFile().getFullPathName());
}

void MainComponent::workflowFailed (const juce::String& errorMessage)
{
    statusComponent.setStatus ("Error: " + errorMessage);
    statusComponent.setProgress (-1.0);

    juce::AlertWindow::showMessageBoxAsync (juce::MessageBoxIconType::WarningIcon,
        "Error", errorMessage);
}
