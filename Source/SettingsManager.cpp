#include "SettingsManager.h"

SettingsManager::SettingsManager()
{
    juce::PropertiesFile::Options options;
    options.applicationName = "AuphonicApp";
    options.folderName = "AuphonicApp";
    options.filenameSuffix = ".settings";
    options.osxLibrarySubFolder = "Application Support";

    appProperties = std::make_unique<juce::ApplicationProperties>();
    appProperties->setStorageParameters (options);
}

juce::String SettingsManager::getValue (const juce::String& key, const juce::String& defaultValue) const
{
    if (auto* props = appProperties->getUserSettings())
        return props->getValue (key, defaultValue);
    return defaultValue;
}

void SettingsManager::setValue (const juce::String& key, const juce::String& value)
{
    if (auto* props = appProperties->getUserSettings())
    {
        props->setValue (key, value);
        props->saveIfNeeded();
    }
}

juce::String SettingsManager::getApiToken() const              { return getValue ("apiToken"); }
void SettingsManager::setApiToken (const juce::String& token)  { setValue ("apiToken", token); }
bool SettingsManager::hasApiToken() const                      { return getApiToken().isNotEmpty(); }

juce::String SettingsManager::getLastPresetUuid() const              { return getValue ("lastPresetUuid"); }
void SettingsManager::setLastPresetUuid (const juce::String& uuid)   { setValue ("lastPresetUuid", uuid); }

juce::String SettingsManager::getLastManualSettings() const                    { return getValue ("lastManualSettings"); }
void SettingsManager::setLastManualSettings (const juce::String& jsonString)   { setValue ("lastManualSettings", jsonString); }

juce::String SettingsManager::getAudioOutputDevice() const                     { return getValue ("audioOutputDevice"); }
void SettingsManager::setAudioOutputDevice (const juce::String& deviceName)    { setValue ("audioOutputDevice", deviceName); }

bool SettingsManager::getPerChannelMode() const            { return getValue ("perChannelMode", "0") == "1"; }
void SettingsManager::setPerChannelMode (bool enabled)     { setValue ("perChannelMode", enabled ? "1" : "0"); }
