#pragma once

#include <juce_events/juce_events.h>
#include <map>
#include "AuphonicApiClient.h"
#include "ProcessingWorkflow.h"
#include "WavChunkCopier.h"

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

    struct ChannelJob {
        int channel;              // 1-based channel index
        juce::String presetUuid;
        juce::var settings;       // algorithm settings with forced WAV output format
    };

    struct PerChannelFileJob {
        juce::File inputFile;
        juce::Array<ChannelJob> channels;
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
                double previewDuration = 0.0,
                bool keepTimecode = false);
    void startPerChannel (const juce::Array<PerChannelFileJob>& fileJobs,
                          bool avoidOverwrite,
                          const juce::String& outputSuffix,
                          bool writeSettingsXml);
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
    void mergeFileGroup (int groupIndex);
    void checkAllGroupsDone();

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
                    double previewDuration,
                    bool keepTimecode);
        void cancel();
        bool isFinished() const { return finished; }

        // ProcessingWorkflow::Listener
        void workflowStateChanged (ProcessingWorkflow::State newState) override;
        void workflowProgressChanged (double progress, const juce::String& statusText) override;
        void workflowCompleted() override;
        void workflowFailed (const juce::String& errorMessage) override;

        int getChannel() const { return channelNum; }
        ProcessingWorkflow& getWorkflow() { return workflow; }
        void setChannel (int ch) { channelNum = ch; }

    private:
        BatchWorkflow& owner;
        int index;
        int channelNum = 0; // 0 = whole-file mode, 1-based for per-channel
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
    bool keepTimecode = false;

    // Per-channel slot info (used when per-channel mode is active)
    struct SlotInfo {
        juce::File inputFile;
        int channel;              // 1-based
        juce::String presetUuid;
        juce::var settings;
    };
    juce::Array<SlotInfo> slotInfos;

    // Per-channel mode
    struct FileGroup {
        int fileIndex;                                    // index in results array
        juce::File inputFile;
        juce::Array<int> slotIndices;                     // indices into slots array
        std::map<int, int> channelToSlotIndex;            // channel -> slot index
        std::map<int, juce::File> completedChannelFiles;  // channel -> downloaded temp file
        int completedCount = 0;
        int failedCount = 0;
        bool mergeComplete = false;
    };
    juce::Array<FileGroup> fileGroups;
    bool perChannelMode = false;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR (BatchWorkflow)
};
