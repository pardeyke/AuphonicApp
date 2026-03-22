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

    if (! owner.perChannelMode)
    {
        owner.results.getReference (index).success = true;
        owner.results.getReference (index).outputFile = workflow.getLastOutputFile();

        if (owner.listener)
            owner.listener->batchFileStatusChanged (index, "Done");
    }

    owner.onSlotCompleted (index);
}

void BatchWorkflow::WorkflowSlot::workflowFailed (const juce::String& errorMessage)
{
    finished = true;

    if (! owner.perChannelMode)
    {
        owner.results.getReference (index).success = false;
        owner.results.getReference (index).errorMessage = errorMessage;

        if (owner.listener)
            owner.listener->batchFileStatusChanged (index, "Error: " + errorMessage);
    }

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

    // Clean up any temp files from per-channel mode
    if (perChannelMode)
    {
        for (auto& group : fileGroups)
            for (auto& [ch, file] : group.completedChannelFiles)
                file.deleteFile();
    }

    perChannelMode = false;
    fileGroups.clear();
    slotInfos.clear();
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

        if (perChannelMode)
        {
            auto& info = slotInfos.getReference (idx);
            slots[idx]->getWorkflow().setTempOutputMode (true);
            slots[idx]->start (info.inputFile,
                               info.presetUuid, info.settings,
                               false, {}, false,
                               info.channel, 0.0, false);
        }
        else
        {
            slots[idx]->start (results[idx].inputFile,
                               presetUuid, manualSettings,
                               avoidOverwrite, outputSuffix, writeSettingsXml,
                               channelToExtract, previewDuration, keepTimecode);
        }
    }

    // Update overall progress
    if (perChannelMode)
    {
        // In per-channel mode, report per-file progress
        int completedFiles = 0;
        for (auto& g : fileGroups)
            if (g.mergeComplete)
                ++completedFiles;

        if (listener)
            listener->batchProgressChanged (completedFiles, fileGroups.size(),
                "Processing " + juce::String (completedFiles) + "/" + juce::String (fileGroups.size()) + " files...");
    }
    else
    {
        int completed = 0;
        for (auto* slot : slots)
            if (slot->isFinished())
                ++completed;

        if (listener)
            listener->batchProgressChanged (completed, slots.size(),
                "Processing " + juce::String (completed) + "/" + juce::String (slots.size()) + " files...");
    }
}

void BatchWorkflow::onSlotCompleted (int slotIdx)
{
    if (perChannelMode)
    {
        // Find which file group owns this slot
        for (int gi = 0; gi < fileGroups.size(); ++gi)
        {
            auto& group = fileGroups.getReference (gi);
            for (auto si : group.slotIndices)
            {
                if (si == slotIdx)
                {
                    int channel = slots[slotIdx]->getChannel();

                    if (slots[slotIdx]->isFinished())
                    {
                        // Check if it succeeded by looking at the workflow output
                        auto outputFile = slots[slotIdx]->getWorkflow().getLastOutputFile();
                        if (outputFile.existsAsFile())
                        {
                            group.completedChannelFiles[channel] = outputFile;
                            ++group.completedCount;
                        }
                        else
                        {
                            ++group.failedCount;
                        }
                    }

                    // Report per-file progress
                    int totalChans = group.slotIndices.size();
                    int doneChans = group.completedCount + group.failedCount;

                    if (listener)
                        listener->batchFileStatusChanged (group.fileIndex,
                            "Processing channels (" + juce::String (doneChans) + "/" + juce::String (totalChans) + " done)");

                    // If all channels for this group are done, merge
                    if (doneChans == totalChans)
                    {
                        if (listener)
                            listener->batchFileStatusChanged (group.fileIndex, "Merging...");

                        mergeFileGroup (gi);
                    }
                    return;
                }
            }
        }
    }
    else
    {
        checkAllDone();
    }
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

void BatchWorkflow::startPerChannel (const juce::Array<PerChannelFileJob>& fileJobs,
                                      bool avoidOverwriteFlag,
                                      const juce::String& suffix,
                                      bool writeXml)
{
    cancel();

    perChannelMode = true;
    avoidOverwrite = avoidOverwriteFlag;
    outputSuffix = suffix;
    writeSettingsXml = writeXml;

    slots.clear();
    results.clear();
    fileGroups.clear();
    slotInfos.clear();
    createTimestamps.clear();
    nextToLaunch = 0;

    int slotIndex = 0;
    for (int fi = 0; fi < fileJobs.size(); ++fi)
    {
        const auto& job = fileJobs[fi];
        results.add ({ job.inputFile, {}, false, {} });

        FileGroup group;
        group.fileIndex = fi;
        group.inputFile = job.inputFile;

        for (auto& chJob : job.channels)
        {
            auto* slot = new WorkflowSlot (*this, slotIndex, api);
            slot->setChannel (chJob.channel);
            slots.add (slot);

            slotInfos.add ({ job.inputFile, chJob.channel, chJob.presetUuid, chJob.settings });

            group.slotIndices.add (slotIndex);
            group.channelToSlotIndex[chJob.channel] = slotIndex;
            ++slotIndex;
        }

        fileGroups.add (group);
    }

    running = true;
    launchNext();

    if (nextToLaunch < slots.size())
        startTimer (1000);
}

void BatchWorkflow::mergeFileGroup (int groupIndex)
{
    auto& group = fileGroups.getReference (groupIndex);
    auto inputFile = group.inputFile;
    auto completedFiles = group.completedChannelFiles;
    bool doAvoidOverwrite = avoidOverwrite;
    auto suffix = outputSuffix;
    bool doWriteXml = writeSettingsXml;

    juce::Thread::launch ([this, groupIndex, inputFile, completedFiles, doAvoidOverwrite, suffix, doWriteXml]
    {
        // Convert 1-based channel map to 0-based for mergeChannels
        std::map<int, juce::File> zeroBasedMap;
        for (auto& [ch, file] : completedFiles)
            zeroBasedMap[ch - 1] = file;

        // Compute output path
        auto dir = inputFile.getParentDirectory();
        juce::String suffixStr = doAvoidOverwrite ? suffix : juce::String{};
        auto baseName = inputFile.getFileNameWithoutExtension() + suffixStr;
        auto ext = juce::String (".wav");
        auto outputFile = dir.getChildFile (baseName + ext);

        if (outputFile.existsAsFile() && (doAvoidOverwrite || outputFile != inputFile))
        {
            int counter = 2;
            while (dir.getChildFile (baseName + "_" + juce::String (counter) + ext).existsAsFile())
                ++counter;
            outputFile = dir.getChildFile (baseName + "_" + juce::String (counter) + ext);
        }

        bool mergeOk = WavChunkCopier::mergeChannels (inputFile, outputFile, zeroBasedMap);

        // Write settings XML if requested
        if (mergeOk && doWriteXml)
        {
            auto root = std::make_unique<juce::DynamicObject>();
            root->setProperty ("input_file", inputFile.getFullPathName());
            root->setProperty ("output_file", outputFile.getFullPathName());
            root->setProperty ("processed_at", juce::Time::getCurrentTime().formatted ("%Y-%m-%d %H:%M:%S"));
            root->setProperty ("processing_mode", "per_channel");

            auto jsonFile = outputFile.withFileExtension (".json");
            juce::FileOutputStream jsonStream (jsonFile);
            if (jsonStream.openedOk())
                jsonStream.writeText (juce::JSON::toString (juce::var (root.release()), false),
                                      false, false, "\n");
        }

        // Clean up temp channel files
        for (auto& [ch, file] : completedFiles)
            file.deleteFile();

        juce::MessageManager::callAsync ([this, groupIndex, mergeOk, outputFile]
        {
            auto& g = fileGroups.getReference (groupIndex);
            g.mergeComplete = true;

            if (mergeOk)
            {
                results.getReference (g.fileIndex).success = true;
                results.getReference (g.fileIndex).outputFile = outputFile;

                if (listener)
                    listener->batchFileStatusChanged (g.fileIndex, "Done");
            }
            else
            {
                results.getReference (g.fileIndex).success = false;
                results.getReference (g.fileIndex).errorMessage = "Channel merge failed";

                if (listener)
                    listener->batchFileStatusChanged (g.fileIndex, "Error: Merge failed");
            }

            checkAllGroupsDone();
        });
    });
}

void BatchWorkflow::checkAllGroupsDone()
{
    // Count completed files for progress
    int completedFiles = 0;
    for (auto& g : fileGroups)
        if (g.mergeComplete)
            ++completedFiles;

    if (listener)
        listener->batchProgressChanged (completedFiles, fileGroups.size(),
            "Processing " + juce::String (completedFiles) + "/" + juce::String (fileGroups.size()) + " files...");

    if (completedFiles == fileGroups.size())
    {
        stopTimer();
        running = false;
        if (listener)
            listener->batchCompleted (results);
    }
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
