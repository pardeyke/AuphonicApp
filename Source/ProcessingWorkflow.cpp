#include "ProcessingWorkflow.h"

ProcessingWorkflow::ProcessingWorkflow (AuphonicApiClient& apiClient)
    : api (apiClient)
{
}

ProcessingWorkflow::~ProcessingWorkflow()
{
    stopTimer();
}

void ProcessingWorkflow::start (const juce::File& inputFile,
                                 const juce::String& presetUuid,
                                 const juce::var& manualSettings)
{
    cancel();

    sourceFile = inputFile;
    presetId = presetUuid;
    settings = manualSettings;
    cancelled = false;
    productionUuid = {};

    stepCreateProduction();
}

void ProcessingWorkflow::cancel()
{
    cancelled = true;
    stopTimer();
    setState (State::Idle);
}

void ProcessingWorkflow::setState (State newState)
{
    state = newState;
    if (listener)
        listener->workflowStateChanged (newState);
}

void ProcessingWorkflow::setError (const juce::String& message)
{
    stopTimer();
    setState (State::Error);
    if (listener)
        listener->workflowFailed (message);
}

void ProcessingWorkflow::stepCreateProduction()
{
    setState (State::CreatingProduction);
    if (listener)
        listener->workflowProgressChanged (-1.0, "Creating production...");

    api.createProduction (presetId, settings,
        [this] (bool success, const juce::String& uuid, const juce::String& error)
        {
            if (cancelled) return;
            if (! success) { setError ("Create production failed: " + error); return; }

            productionUuid = uuid;
            stepUpload();
        });
}

void ProcessingWorkflow::stepUpload()
{
    setState (State::Uploading);
    if (listener)
        listener->workflowProgressChanged (-1.0, "Uploading " + sourceFile.getFileName() + "...");

    api.uploadFile (productionUuid, sourceFile,
        [this] (bool success, const juce::String& error)
        {
            if (cancelled) return;
            if (! success) { setError ("Upload failed: " + error); return; }

            stepStart();
        });
}

void ProcessingWorkflow::stepStart()
{
    setState (State::Starting);
    if (listener)
        listener->workflowProgressChanged (-1.0, "Starting production...");

    api.startProduction (productionUuid,
        [this] (bool success, const juce::String& error)
        {
            if (cancelled) return;
            if (! success) { setError ("Start failed: " + error); return; }

            setState (State::Processing);
            startTimer (5000);
        });
}

void ProcessingWorkflow::timerCallback()
{
    stepPollStatus();
}

void ProcessingWorkflow::stepPollStatus()
{
    api.getProductionStatus (productionUuid,
        [this] (bool success, const ProductionStatus& status)
        {
            if (cancelled) return;
            if (! success) { setError ("Could not get production status"); return; }

            if (listener)
                listener->workflowProgressChanged (status.progress, status.statusString);

            // Auphonic status codes:
            // 0=File Upload, 1=Waiting, 2=Error, 3=Done,
            // 4=Audio Processing, 5=Audio Encoding, 6=Outgoing File Transfer,
            // 7=Mono Mixdown, 8=Split on Chapters, 9=Incomplete,
            // 10=Not Started, 11=Outdated, 12=Incoming Transfer,
            // 13=Stopping, 14=Speech Recognition, 15=Changed

            if (status.statusCode == 3) // Done
            {
                stopTimer();
                if (status.outputFileUrl.isNotEmpty())
                    stepDownload (status.outputFileUrl);
                else
                    setError ("Processing complete but no output file URL found");
            }
            else if (status.statusCode == 2) // Error
            {
                stopTimer();
                setError ("Processing failed: " + (status.errorMessage.isNotEmpty()
                    ? status.errorMessage : status.statusString));
            }
            // else still in progress (0,1,4,5,6,7,8,12,14...), keep polling
        });
}

void ProcessingWorkflow::stepDownload (const juce::String& downloadUrl)
{
    setState (State::Downloading);
    if (listener)
        listener->workflowProgressChanged (-1.0, "Downloading result...");

    api.downloadFile (downloadUrl,
        [this] (bool success, const juce::File& tempFile, const juce::String& error)
        {
            if (cancelled) return;
            if (! success) { setError ("Download failed: " + error); return; }

            stepSave (tempFile);
        });
}

void ProcessingWorkflow::stepSave (const juce::File& tempFile)
{
    setState (State::Saving);
    if (listener)
        listener->workflowProgressChanged (-1.0, "Saving to " + sourceFile.getFileName() + "...");

    bool success = tempFile.moveFileTo (sourceFile);
    if (success)
    {
        setState (State::Done);
        if (listener)
        {
            listener->workflowProgressChanged (1.0, "Complete!");
            listener->workflowCompleted();
        }
    }
    else
    {
        setError ("Failed to overwrite original file: " + sourceFile.getFullPathName());
    }
}
