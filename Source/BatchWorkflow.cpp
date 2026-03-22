#include "BatchWorkflow.h"

// --- WorkflowSlot ---

BatchWorkflow::WorkflowSlot::WorkflowSlot (BatchWorkflow& o, int idx, AuphonicApiClient& apiClient)
    : owner (o), index (idx), workflow (apiClient)
{
    workflow.setListener (this);
}

void BatchWorkflow::WorkflowSlot::start (const juce::File& file,
                                          const juce::String& preset,
                                          const juce::var& settings,
                                          bool overwrite,
                                          const juce::String& suffix,
                                          bool writeXml,
                                          int channel,
                                          double preview,
                                          bool timecode)
{
    started = true;
    workflow.start (file, preset, settings,
                    overwrite, suffix, writeXml,
                    channel, preview, timecode);
}

void BatchWorkflow::WorkflowSlot::cancel()
{
    if (started && ! finished)
        workflow.cancel();
    finished = true;
}

void BatchWorkflow::WorkflowSlot::workflowStateChanged (ProcessingWorkflow::State newState)
{
    auto status = stateToStatus (newState);
    if (status.isNotEmpty() && owner.listener)
        owner.listener->batchFileStatusChanged (index, status);
}

void BatchWorkflow::WorkflowSlot::workflowProgressChanged (double, const juce::String& statusText)
{
    if (owner.listener)
        owner.listener->batchFileStatusChanged (index, statusText);
}

void BatchWorkflow::WorkflowSlot::workflowCompleted()
{
    finished = true;
    owner.results.getReference (index).success = true;
    owner.results.getReference (index).outputFile = workflow.getLastOutputFile();

    if (owner.listener)
        owner.listener->batchFileStatusChanged (index, "Done");

    owner.onSlotCompleted (index);
}

void BatchWorkflow::WorkflowSlot::workflowFailed (const juce::String& errorMessage)
{
    finished = true;
    owner.results.getReference (index).success = false;
    owner.results.getReference (index).errorMessage = errorMessage;

    if (owner.listener)
        owner.listener->batchFileStatusChanged (index, "Error: " + errorMessage);

    owner.onSlotCompleted (index);
}

// --- BatchWorkflow ---

BatchWorkflow::BatchWorkflow (AuphonicApiClient& apiClient)
    : api (apiClient)
{
}

BatchWorkflow::~BatchWorkflow()
{
    stopTimer();
}

void BatchWorkflow::start (const juce::Array<juce::File>& files,
                            const juce::String& preset,
                            const juce::var& settings,
                            bool avoidOverwriteFlag,
                            const juce::String& suffix,
                            bool writeXml,
                            int channel,
                            double preview,
                            bool timecode)
{
    cancel();

    presetUuid = preset;
    manualSettings = settings;
    avoidOverwrite = avoidOverwriteFlag;
    outputSuffix = suffix;
    writeSettingsXml = writeXml;
    channelToExtract = channel;
    previewDuration = preview;
    keepTimecode = timecode;

    slots.clear();
    results.clear();
    createTimestamps.clear();
    nextToLaunch = 0;

    for (int i = 0; i < files.size(); ++i)
    {
        slots.add (new WorkflowSlot (*this, i, api));
        results.add ({ files[i], {}, false, {} });
    }

    running = true;

    // Launch as many as rate limit allows immediately
    launchNext();

    // Start timer to check for queued workflows
    if (nextToLaunch < slots.size())
        startTimer (1000);
}

void BatchWorkflow::cancel()
{
    stopTimer();

    for (auto* slot : slots)
        slot->cancel();

    running = false;
}

void BatchWorkflow::timerCallback()
{
    launchNext();

    if (nextToLaunch >= slots.size())
        stopTimer();
}

void BatchWorkflow::launchNext()
{
    auto now = juce::Time::currentTimeMillis();

    // Purge timestamps older than the rate-limit window
    while (! createTimestamps.isEmpty()
           && (now - createTimestamps.getFirst()) > windowMilliseconds)
        createTimestamps.remove (0);

    while (nextToLaunch < slots.size()
           && createTimestamps.size() < maxCreatesPerWindow)
    {
        int idx = nextToLaunch++;
        createTimestamps.add (now);
        slots[idx]->start (results[idx].inputFile,
                           presetUuid, manualSettings,
                           avoidOverwrite, outputSuffix, writeSettingsXml,
                           channelToExtract, previewDuration, keepTimecode);
    }

    // Update overall progress
    int completed = 0;
    for (auto* slot : slots)
        if (slot->isFinished())
            ++completed;

    if (listener)
        listener->batchProgressChanged (completed, slots.size(),
            "Processing " + juce::String (completed) + "/" + juce::String (slots.size()) + " files...");
}

void BatchWorkflow::onSlotCompleted (int)
{
    checkAllDone();
}

void BatchWorkflow::checkAllDone()
{
    int completed = 0;
    for (auto* slot : slots)
        if (slot->isFinished())
            ++completed;

    if (listener)
        listener->batchProgressChanged (completed, slots.size(),
            "Processing " + juce::String (completed) + "/" + juce::String (slots.size()) + " files...");

    if (completed == slots.size())
    {
        stopTimer();
        running = false;

        if (listener)
            listener->batchCompleted (results);
    }
}

juce::File BatchWorkflow::getLastOutputFile() const
{
    // Return first successful output file
    for (auto& r : results)
        if (r.success && r.outputFile.existsAsFile())
            return r.outputFile;
    return {};
}

juce::String BatchWorkflow::stateToStatus (ProcessingWorkflow::State state)
{
    switch (state)
    {
        case ProcessingWorkflow::State::Idle:              return {};
        case ProcessingWorkflow::State::ExtractingChannel: return "Extracting channel...";
        case ProcessingWorkflow::State::Trimming:          return "Trimming...";
        case ProcessingWorkflow::State::CreatingProduction:return "Creating...";
        case ProcessingWorkflow::State::Uploading:         return "Uploading...";
        case ProcessingWorkflow::State::Starting:          return "Starting...";
        case ProcessingWorkflow::State::Processing:        return "Processing...";
        case ProcessingWorkflow::State::Downloading:       return "Downloading...";
        case ProcessingWorkflow::State::Converting:        return "Converting...";
        case ProcessingWorkflow::State::Saving:            return "Saving...";
        case ProcessingWorkflow::State::Done:              return "Done";
        case ProcessingWorkflow::State::Error:             return "Error";
    }
    return {};
}
