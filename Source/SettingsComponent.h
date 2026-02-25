#pragma once

#include <juce_gui_basics/juce_gui_basics.h>
#include <juce_audio_devices/juce_audio_devices.h>
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
    juce::Label helpLabel { {}, "Find your token at auphonic.com/accounts/api-app" };

    juce::Label outputDeviceLabel { {}, "Output Device:" };
    juce::ComboBox outputDeviceCombo;

    juce::TextButton saveButton { "Save" };

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR (SettingsComponent)
};
