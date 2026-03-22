#pragma once

#include <juce_events/juce_events.h>
#include "AuphonicApiClient.h"

class ProcessingWorkflow : private juce::Timer
{
public:
    enum class State
    {
        Idle,
        ExtractingChannel,
        Trimming,
        CreatingProduction,
        Uploading,
        Starting,
        Processing,
        Downloading,
        Converting,
        Saving,
        Done,
        Error
    };

    struct Listener
    {
        virtual ~Listener() = default;
        virtual void workflowStateChanged (State newState) = 0;
        virtual void workflowProgressChanged (double progress, const juce::String& statusText) = 0;
        virtual void workflowCompleted() = 0;
        virtual void workflowFailed (const juce::String& errorMessage) = 0;
    };

    ProcessingWorkflow (AuphonicApiClient& apiClient);
    ~ProcessingWorkflow() override;

    void start (const juce::File& inputFile,
                const juce::String& presetUuid,
                const juce::var& manualSettings,
                bool avoidOverwrite,
                const juce::String& outputSuffix,
                bool writeSettingsXml,
                int channelToExtract = 0,
                double previewDuration = 0.0,
                bool keepTimecode = false);
    void cancel();

    State getState() const { return state; }
    void setListener (Listener* l) { listener = l; }
    juce::File getLastOutputFile() const { return lastOutputFile; }

private:
    void timerCallback() override;

    void setState (State newState);
    void setError (const juce::String& message);
    void cleanupTempFile (juce::File& tempFile);

    void stepExtractChannel();
    void stepTrimPreview();
    void stepCreateProduction();
    void stepUpload();
    void stepStart();
    void stepPollStatus();
    void stepDownload (const juce::String& downloadUrl);
    void stepConvert (const juce::File& tempFile);
    void stepSave (const juce::File& tempFile);

    AuphonicApiClient& api;
    Listener* listener = nullptr;

    State state = State::Idle;
    juce::File originalSourceFile; // always points to the user's original file (for output path)
    juce::File sourceFile;         // file to upload (may be a temp extracted channel)
    juce::File lastOutputFile;
    juce::String productionUuid;
    juce::String presetId;
    juce::var settings;
    juce::String targetExtension; // set when post-download format conversion is needed
    bool avoidOverwrite   = false;
    juce::String outputSuffix;
    bool writeSettingsXml = false;
    bool cancelled = false;
    int extractChannel = 0;      // 0 = all channels, 1-N = specific channel
    double previewDurationSeconds = 0.0; // 0 = full file
    bool keepTimecode = false;
    juce::File extractedTempFile; // temp mono file when extracting a channel
    juce::File trimmedTempFile;   // temp file when trimming for preview

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR (ProcessingWorkflow)
};
