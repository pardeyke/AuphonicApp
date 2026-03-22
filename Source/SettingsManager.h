#pragma once

#include <juce_gui_extra/juce_gui_extra.h>

class SettingsManager
{
public:
    SettingsManager();

    juce::String getApiToken() const;
    void setApiToken (const juce::String& token);
    bool hasApiToken() const;

    juce::String getLastPresetUuid() const;
    void setLastPresetUuid (const juce::String& uuid);

    juce::String getLastManualSettings() const;
    void setLastManualSettings (const juce::String& jsonString);

    juce::String getAudioOutputDevice() const;
    void setAudioOutputDevice (const juce::String& deviceName);

    bool getPerChannelMode() const;
    void setPerChannelMode (bool enabled);

private:
    juce::String getValue (const juce::String& key, const juce::String& defaultValue = {}) const;
    void setValue (const juce::String& key, const juce::String& value);

    std::unique_ptr<juce::ApplicationProperties> appProperties;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR (SettingsManager)
};
