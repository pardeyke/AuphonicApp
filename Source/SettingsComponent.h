#pragma once

#include <juce_gui_basics/juce_gui_basics.h>
#include "SettingsManager.h"

class SettingsComponent : public juce::Component
{
public:
    SettingsComponent (SettingsManager& settings, std::function<void()> onSaved);

    void resized() override;

    static void showDialog (SettingsManager& settings, juce::Component* parent,
                            std::function<void()> onSaved = {});

private:
    SettingsManager& settingsManager;
    std::function<void()> onTokenSaved;

    juce::Label tokenLabel { {}, "API Token:" };
    juce::TextEditor tokenEditor;
    juce::TextButton saveButton { "Save" };
    juce::Label helpLabel { {}, "Find your token at auphonic.com/accounts/api-app" };

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR (SettingsComponent)
};
