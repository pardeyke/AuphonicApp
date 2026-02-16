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

juce::String SettingsManager::getApiToken() const
{
    if (auto* props = appProperties->getUserSettings())
        return props->getValue ("apiToken", "");
    return {};
}

void SettingsManager::setApiToken (const juce::String& token)
{
    if (auto* props = appProperties->getUserSettings())
    {
        props->setValue ("apiToken", token);
        props->saveIfNeeded();
    }
}

bool SettingsManager::hasApiToken() const
{
    return getApiToken().isNotEmpty();
}

juce::String SettingsManager::getLastPresetUuid() const
{
    if (auto* props = appProperties->getUserSettings())
        return props->getValue ("lastPresetUuid", "");
    return {};
}

void SettingsManager::setLastPresetUuid (const juce::String& uuid)
{
    if (auto* props = appProperties->getUserSettings())
    {
        props->setValue ("lastPresetUuid", uuid);
        props->saveIfNeeded();
    }
}

juce::String SettingsManager::getLastManualSettings() const
{
    if (auto* props = appProperties->getUserSettings())
        return props->getValue ("lastManualSettings", "");
    return {};
}

void SettingsManager::setLastManualSettings (const juce::String& jsonString)
{
    if (auto* props = appProperties->getUserSettings())
    {
        props->setValue ("lastManualSettings", jsonString);
        props->saveIfNeeded();
    }
}
