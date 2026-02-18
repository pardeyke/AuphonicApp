#include "ProcessingWorkflow.h"
#include <juce_audio_formats/juce_audio_formats.h>

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
                                 const juce::var& manualSettings,
                                 bool avoidOverwriteFlag,
                                 bool writeSettingsXmlFlag)
{
    cancel();

    sourceFile = inputFile;
    presetId = presetUuid;
    settings = manualSettings;
    cancelled = false;
    productionUuid = {};
    lastOutputFile = juce::File();
    targetExtension = {};
    avoidOverwrite   = avoidOverwriteFlag;
    writeSettingsXml = writeSettingsXmlFlag;

    // Resolve "keep" output format based on source file extension
    if (settings.getProperty ("output_format", {}).toString() == "keep")
    {
        auto ext = sourceFile.getFileExtension().toLowerCase();
        juce::String apiFormat;

        if      (ext == ".wav")                   apiFormat = "wav-24bit";
        else if (ext == ".flac")                  apiFormat = "flac";
        else if (ext == ".mp3")                   apiFormat = "mp3";
        else if (ext == ".aac" || ext == ".m4a")  apiFormat = "aac";
        else if (ext == ".ogg")                   apiFormat = "vorbis";
        else if (ext == ".opus")                  apiFormat = "opus";
        else if (ext == ".alac")                  apiFormat = "alac";
        else if (ext == ".aif" || ext == ".aiff")
        {
            apiFormat = "wav-24bit";
            targetExtension = ext; // needs WAV→AIFF conversion after download
        }
        else { apiFormat = "wav-24bit"; } // unknown: safe lossless fallback

        if (auto* obj = settings.getDynamicObject())
            obj->setProperty ("output_format", apiFormat);
    }

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

            if (targetExtension.isNotEmpty()
                && tempFile.getFileExtension().toLowerCase() != targetExtension)
                stepConvert (tempFile);
            else
                stepSave (tempFile);
        });
}

void ProcessingWorkflow::stepConvert (const juce::File& tempFile)
{
    setState (State::Converting);
    if (listener)
        listener->workflowProgressChanged (-1.0, "Converting to "
            + targetExtension.trimCharactersAtStart (".").toUpperCase() + "...");

    auto target = targetExtension;

    juce::Thread::launch ([this, tempFile, target]
    {
        auto convertedFile = juce::File::getSpecialLocation (juce::File::tempDirectory)
            .getChildFile ("auphonic_converted_"
                + juce::String (juce::Random::getSystemRandom().nextInt64()) + target);

        bool success = false;
        juce::String error;

        juce::AudioFormatManager mgr;
        mgr.registerBasicFormats();

        if (auto* reader = mgr.createReaderFor (tempFile))
        {
            std::unique_ptr<juce::AudioFormatReader> readerOwner (reader);

            // For .aif / .aiff we use AiffAudioFormat directly
            juce::AiffAudioFormat aiffFmt;
            auto os = std::make_unique<juce::FileOutputStream> (convertedFile);

            if (os->openedOk())
            {
                if (auto* writer = aiffFmt.createWriterFor (
                        os.get(),
                        reader->sampleRate,
                        reader->numChannels,
                        static_cast<int> (reader->bitsPerSample),
                        reader->metadataValues,
                        0))
                {
                    os.release(); // writer now owns the stream
                    std::unique_ptr<juce::AudioFormatWriter> writerOwner (writer);
                    success = writer->writeFromAudioReader (*reader, 0, reader->lengthInSamples);
                    if (! success) error = "Failed to write converted file";
                }
                else { error = "Could not create AIFF writer"; }
            }
            else { error = "Could not create temp file for conversion"; }
        }
        else { error = "Could not read downloaded file for conversion"; }

        tempFile.deleteFile(); // clean up the WAV temp

        juce::MessageManager::callAsync ([this, success, convertedFile, error]
        {
            if (cancelled) return;
            if (! success) { setError ("Format conversion failed: " + error); return; }
            stepSave (convertedFile);
        });
    });
}

void ProcessingWorkflow::stepSave (const juce::File& tempFile)
{
    setState (State::Saving);

    auto now = juce::Time::getCurrentTime();
    juce::String suffix = avoidOverwrite
        ? ("_auphonic_" + now.formatted ("%Y%m%d_%H%M%S"))
        : juce::String{};

    auto outputFile = sourceFile.getParentDirectory()
        .getChildFile (sourceFile.getFileNameWithoutExtension() + suffix + tempFile.getFileExtension());

    if (listener)
        listener->workflowProgressChanged (-1.0, "Saving " + outputFile.getFileName() + "...");

    // Only delete an existing file when we're NOT using the suffix (i.e. overwrite mode)
    if (suffix.isEmpty() && outputFile != sourceFile && outputFile.existsAsFile())
        outputFile.deleteFile();

    bool success = tempFile.moveFileTo (outputFile);
    if (success)
    {
        lastOutputFile = outputFile;

        if (writeSettingsXml)
        {
            auto root = std::make_unique<juce::DynamicObject>();
            root->setProperty ("input_file",  sourceFile.getFullPathName());
            root->setProperty ("output_file", outputFile.getFullPathName());
            root->setProperty ("processed_at", now.formatted ("%Y-%m-%d %H:%M:%S"));

            if (presetId.isNotEmpty())
            {
                root->setProperty ("processing_mode", "preset");
                root->setProperty ("preset_uuid", presetId);
            }
            else
            {
                root->setProperty ("processing_mode", "manual");
                root->setProperty ("settings", settings);
            }

            auto jsonFile = outputFile.withFileExtension (".json");
            juce::FileOutputStream jsonStream (jsonFile);
            if (jsonStream.openedOk())
                jsonStream.writeText (juce::JSON::toString (juce::var (root.release()), false),
                                      false, false, "\n");
        }

        setState (State::Done);
        if (listener)
        {
            listener->workflowProgressChanged (1.0, "Complete!");
            listener->workflowCompleted();
        }
    }
    else
    {
        setError ("Failed to save output file: " + outputFile.getFullPathName());
    }
}
