#pragma once

#include <juce_core/juce_core.h>
#include <juce_events/juce_events.h>

struct AuphonicPreset
{
    juce::String uuid;
    juce::String name;
};

struct ProductionStatus
{
    int statusCode = 0;         // 0=incomplete, 2=production started, 3=processing, 4=done, 5+=error
    juce::String statusString;
    double progress = 0.0;      // 0.0 - 1.0
    juce::String errorMessage;
    juce::String outputFileUrl;
    juce::String uuid;
};

class AuphonicApiClient
{
public:
    explicit AuphonicApiClient (const juce::String& apiToken);
    void setToken (const juce::String& token);

    using PresetsCallback = std::function<void (bool success, const juce::Array<AuphonicPreset>& presets)>;
    void fetchPresets (PresetsCallback callback);

    using ProductionCallback = std::function<void (bool success, const juce::String& uuid, const juce::String& error)>;
    void createProduction (const juce::String& presetUuid,
                           const juce::var& manualSettings,
                           ProductionCallback callback);

    using UploadCallback = std::function<void (bool success, const juce::String& error)>;
    void uploadFile (const juce::String& productionUuid, const juce::File& file, UploadCallback callback);

    using StartCallback = std::function<void (bool success, const juce::String& error)>;
    void startProduction (const juce::String& productionUuid, StartCallback callback);

    using StatusCallback = std::function<void (bool success, const ProductionStatus& status)>;
    void getProductionStatus (const juce::String& productionUuid, StatusCallback callback);

    using DownloadCallback = std::function<void (bool success, const juce::File& tempFile, const juce::String& error)>;
    void downloadFile (const juce::String& url, DownloadCallback callback);

private:
    juce::String token;

    juce::URL makeUrl (const juce::String& endpoint) const;
    juce::String performGet (const juce::URL& url, int& statusCode);
    juce::String performPost (const juce::URL& url, int& statusCode);

    static constexpr auto baseUrl = "https://auphonic.com/api";

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR (AuphonicApiClient)
};
