#pragma once

#include <juce_events/juce_events.h>
#include "AuphonicApiClient.h"
#include "ProcessingWorkflow.h"

class BatchWorkflow : private juce::Timer
{
public:
    struct FileResult {
        juce::File inputFile;
        juce::File outputFile;
        bool success = false;
        juce::String errorMessage;
    };

    struct Listener {
        virtual ~Listener() = default;
        virtual void batchFileStatusChanged (int index, const juce::String& status) = 0;
        virtual void batchProgressChanged (int completed, int total, const juce::String& overallStatus) = 0;
        virtual void batchCompleted (const juce::Array<FileResult>& results) = 0;
    };

    BatchWorkflow (AuphonicApiClient& apiClient);
    ~BatchWorkflow() override;

    void start (const juce::Array<juce::File>& files,
                const juce::String& presetUuid,
                const juce::var& manualSettings,
                bool avoidOverwrite,
                const juce::String& outputSuffix,
                bool writeSettingsXml,
                int channelToExtract = 0,
                double previewDuration = 0.0);
    void cancel();
    bool isRunning() const { return running; }

    juce::Array<FileResult> getResults() const { return results; }
    juce::File getLastOutputFile() const;

    void setListener (Listener* l) { listener = l; }

private:
    void timerCallback() override;
    void launchNext();
    void onSlotCompleted (int index);
    void checkAllDone();

    static juce::String stateToStatus (ProcessingWorkflow::State state);

    class WorkflowSlot : public ProcessingWorkflow::Listener
    {
    public:
        WorkflowSlot (BatchWorkflow& owner, int index, AuphonicApiClient& api);

        void start (const juce::File& file,
                    const juce::String& presetUuid,
                    const juce::var& manualSettings,
                    bool avoidOverwrite,
                    const juce::String& outputSuffix,
                    bool writeSettingsXml,
                    int channelToExtract,
                    double previewDuration);
        void cancel();
        bool isFinished() const { return finished; }

        // ProcessingWorkflow::Listener
        void workflowStateChanged (ProcessingWorkflow::State newState) override;
        void workflowProgressChanged (double progress, const juce::String& statusText) override;
        void workflowCompleted() override;
        void workflowFailed (const juce::String& errorMessage) override;

    private:
        BatchWorkflow& owner;
        int index;
        ProcessingWorkflow workflow;
        bool finished = false;
        bool started = false;
    };

    AuphonicApiClient& api;
    Listener* listener = nullptr;

    juce::OwnedArray<WorkflowSlot> slots;
    juce::Array<FileResult> results;
    bool running = false;

    // Rate limiting: max 38 creates per 2-minute window (conservative under 40 limit)
    static constexpr int maxCreatesPerWindow = 38;
    static constexpr int windowMilliseconds = 120000; // 2 minutes
    juce::Array<juce::int64> createTimestamps;
    int nextToLaunch = 0;

    // Params stored for launching queued workflows
    juce::String presetUuid;
    juce::var manualSettings;
    bool avoidOverwrite = false;
    juce::String outputSuffix;
    bool writeSettingsXml = false;
    int channelToExtract = 0;
    double previewDuration = 0.0;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR (BatchWorkflow)
};
