#include "SettingsComponent.h"

SettingsComponent::SettingsComponent (SettingsManager& settings, std::function<void()> onSaved)
    : settingsManager (settings), onTokenSaved (std::move (onSaved))
{
    addAndMakeVisible (tokenLabel);
    addAndMakeVisible (tokenEditor);
    addAndMakeVisible (saveButton);
    addAndMakeVisible (helpLabel);

    tokenEditor.setPasswordCharacter ('*');
    tokenEditor.setText (settingsManager.getApiToken(), juce::dontSendNotification);

    helpLabel.setFont (juce::FontOptions (12.0f));
    helpLabel.setColour (juce::Label::textColourId, juce::Colours::grey);

    saveButton.onClick = [this]
    {
        settingsManager.setApiToken (tokenEditor.getText().trim());
        if (onTokenSaved)
            onTokenSaved();
        if (auto* dw = findParentComponentOfClass<juce::DialogWindow>())
            dw->exitModalState (0);
    };

    setSize (400, 140);
}

void SettingsComponent::resized()
{
    auto area = getLocalBounds().reduced (16);

    auto labelRow = area.removeFromTop (24);
    tokenLabel.setBounds (labelRow.removeFromLeft (80));

    area.removeFromTop (4);
    tokenEditor.setBounds (area.removeFromTop (28));

    area.removeFromTop (4);
    helpLabel.setBounds (area.removeFromTop (20));

    area.removeFromTop (8);
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
