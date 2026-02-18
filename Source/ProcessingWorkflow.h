#pragma once

#include <juce_events/juce_events.h>
#include "AuphonicApiClient.h"

class ProcessingWorkflow : private juce::Timer
{
public:
    enum class State
    {
        Idle,
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
                bool writeSettingsXml);
    void cancel();

    State getState() const { return state; }
    void setListener (Listener* l) { listener = l; }
    juce::File getLastOutputFile() const { return lastOutputFile; }

private:
    void timerCallback() override;

    void setState (State newState);
    void setError (const juce::String& message);

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
    juce::File sourceFile;
    juce::File lastOutputFile;
    juce::String productionUuid;
    juce::String presetId;
    juce::var settings;
    juce::String targetExtension; // set when post-download format conversion is needed
    bool avoidOverwrite   = false;
    bool writeSettingsXml = false;
    bool cancelled = false;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR (ProcessingWorkflow)
};
