#include "SettingsComponent.h"

SettingsComponent::SettingsComponent (SettingsManager& settings, std::function<void()> onSaved)
    : settingsManager (settings), onTokenSaved (std::move (onSaved))
{
    addAndMakeVisible (tokenLabel);
    addAndMakeVisible (tokenEditor);
    addAndMakeVisible (helpLink);
    addAndMakeVisible (outputDeviceLabel);
    addAndMakeVisible (outputDeviceCombo);
    addAndMakeVisible (saveButton);

    tokenEditor.setPasswordCharacter ('*');
    tokenEditor.setText (settingsManager.getApiToken(), juce::dontSendNotification);

    helpLink.setFont (juce::FontOptions (12.0f), false);
    helpLink.setColour (juce::HyperlinkButton::textColourId, juce::Colours::grey);
    helpLink.setJustificationType (juce::Justification::centredLeft);

    // Populate output device combo
    {
        juce::AudioDeviceManager tempDeviceManager;
        tempDeviceManager.initialiseWithDefaultDevices (0, 2);

        int itemId = 1;
        outputDeviceCombo.addItem ("(Default)", itemId++);

        auto savedDevice = settingsManager.getAudioOutputDevice();
        int selectedId = 1;

        for (auto* deviceType : tempDeviceManager.getAvailableDeviceTypes())
        {
            deviceType->scanForDevices();
            auto deviceNames = deviceType->getDeviceNames (false);

            for (auto& name : deviceNames)
            {
                outputDeviceCombo.addItem (name, itemId);
                if (name == savedDevice)
                    selectedId = itemId;
                itemId++;
            }
        }

        outputDeviceCombo.setSelectedId (selectedId, juce::dontSendNotification);
    }

    saveButton.onClick = [this]
    {
        settingsManager.setApiToken (tokenEditor.getText().trim());

        auto selectedText = outputDeviceCombo.getText();
        if (outputDeviceCombo.getSelectedId() == 1) // "(Default)"
            settingsManager.setAudioOutputDevice ("");
        else
            settingsManager.setAudioOutputDevice (selectedText);

        if (onTokenSaved)
            onTokenSaved();
        if (auto* dw = findParentComponentOfClass<juce::DialogWindow>())
            dw->exitModalState (0);
    };

    setSize (400, 200);
}

void SettingsComponent::resized()
{
    auto area = getLocalBounds().reduced (16);

    auto labelRow = area.removeFromTop (24);
    tokenLabel.setBounds (labelRow.removeFromLeft (80));

    area.removeFromTop (4);
    tokenEditor.setBounds (area.removeFromTop (28));

    area.removeFromTop (4);
    helpLink.setBounds (area.removeFromTop (20));

    area.removeFromTop (12);
    auto deviceRow = area.removeFromTop (24);
    outputDeviceLabel.setBounds (deviceRow.removeFromLeft (110));
    outputDeviceCombo.setBounds (deviceRow);

    area.removeFromTop (12);
    saveButton.setBounds (area.removeFromTop (28).withSizeKeepingCentre (100, 28));
}

void SettingsComponent::showDialog (SettingsManager& settings, juce::Component* parent,
                                    std::function<void()> onSaved)
{
    auto* comp = new SettingsComponent (settings, std::move (onSaved));

    juce::DialogWindow::LaunchOptions opts;
    opts.content.setOwned (comp);
    opts.dialogTitle = "Settings";
    opts.dialogBackgroundColour = parent->getLookAndFeel()
        .findColour (juce::ResizableWindow::backgroundColourId);
    opts.escapeKeyTriggersCloseButton = true;
    opts.useNativeTitleBar = true;
    opts.resizable = false;

    opts.launchAsync();
}
