#include "ProcessingWorkflow.h"
#include "WavChunkCopier.h"
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
                                 const juce::String& outputSuffixStr,
                                 bool writeSettingsXmlFlag,
                                 int channelToExtract,
                                 double previewDuration,
                                 bool keepTimecodeFlag)
{
    cancel();

    originalSourceFile = inputFile;
    sourceFile = inputFile;
    presetId = presetUuid;
    settings = manualSettings;
    cancelled = false;
    productionUuid = {};
    lastOutputFile = juce::File();
    targetExtension = {};
    avoidOverwrite   = avoidOverwriteFlag;
    outputSuffix     = outputSuffixStr;
    writeSettingsXml = writeSettingsXmlFlag;
    extractChannel = channelToExtract;
    previewDurationSeconds = previewDuration;
    keepTimecode = keepTimecodeFlag;
    extractedTempFile = juce::File();
    trimmedTempFile = juce::File();

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

    if (extractChannel != 0)
        stepExtractChannel();
    else if (previewDurationSeconds > 0.0)
        stepTrimPreview();
    else
        stepCreateProduction();
}

void ProcessingWorkflow::cancel()
{
    cancelled = true;
    stopTimer();

    cleanupTempFile (extractedTempFile);
    cleanupTempFile (trimmedTempFile);

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

void ProcessingWorkflow::cleanupTempFile (juce::File& tempFile)
{
    if (tempFile.existsAsFile())
    {
        tempFile.deleteFile();
        tempFile = juce::File();
    }
}

void ProcessingWorkflow::stepExtractChannel()
{
    setState (State::ExtractingChannel);

    bool stereoExtract = (extractChannel == -1);
    int channel = extractChannel; // -1 = L+R stereo, >0 = single channel

    if (stereoExtract)
    {
        if (listener)
            listener->workflowProgressChanged (-1.0, "Extracting L+R channels...");
    }
    else
    {
        if (listener)
            listener->workflowProgressChanged (-1.0, "Extracting channel " + juce::String (channel) + "...");
    }

    juce::Thread::launch ([this, channel, stereoExtract]
    {
        juce::AudioFormatManager mgr;
        mgr.registerBasicFormats();

        bool success = false;
        juce::String error;

        if (auto* reader = mgr.createReaderFor (sourceFile))
        {
            std::unique_ptr<juce::AudioFormatReader> readerOwner (reader);

            int outChannels = stereoExtract ? 2 : 1;

            if (! stereoExtract && (channel < 1 || channel > (int) reader->numChannels))
            {
                error = "Channel " + juce::String (channel) + " does not exist in this file";
            }
            else if (stereoExtract && reader->numChannels < 2)
            {
                error = "File has fewer than 2 channels for L+R extraction";
            }
            else
            {
                auto tempFile = juce::File::getSpecialLocation (juce::File::tempDirectory)
                    .getChildFile ("auphonic_ch_" + juce::String (juce::Random::getSystemRandom().nextInt64()) + ".wav");

                juce::WavAudioFormat wavFormat;
                auto os = std::make_unique<juce::FileOutputStream> (tempFile);

                if (os->openedOk())
                {
                    if (auto* writer = wavFormat.createWriterFor (
                            os.get(),
                            reader->sampleRate,
                            (unsigned int) outChannels,
                            static_cast<int> (reader->bitsPerSample),
                            reader->metadataValues,
                            0))
                    {
                        os.release(); // writer owns the stream
                        std::unique_ptr<juce::AudioFormatWriter> writerOwner (writer);

                        const int blockSize = 65536;
                        juce::AudioBuffer<float> buffer (static_cast<int> (reader->numChannels), blockSize);
                        juce::AudioBuffer<float> outBuffer (outChannels, blockSize);
                        juce::int64 samplesRemaining = reader->lengthInSamples;
                        juce::int64 startSample = 0;

                        success = true;
                        while (samplesRemaining > 0)
                        {
                            int samplesToRead = (int) juce::jmin ((juce::int64) blockSize, samplesRemaining);
                            if (! reader->read (&buffer, 0, samplesToRead, startSample, true, true))
                            {
                                success = false;
                                error = "Failed to read source audio";
                                break;
                            }

                            if (stereoExtract)
                            {
                                outBuffer.copyFrom (0, 0, buffer, 0, 0, samplesToRead);
                                outBuffer.copyFrom (1, 0, buffer, 1, 0, samplesToRead);
                            }
                            else
                            {
                                outBuffer.copyFrom (0, 0, buffer, channel - 1, 0, samplesToRead);
                            }

                            if (! writer->writeFromAudioSampleBuffer (outBuffer, 0, samplesToRead))
                            {
                                success = false;
                                error = "Failed to write extracted channel";
                                break;
                            }

                            startSample += samplesToRead;
                            samplesRemaining -= samplesToRead;
                        }

                        if (success)
                        {
                            juce::MessageManager::callAsync ([this, tempFile]
                            {
                                if (cancelled) return;
                                extractedTempFile = tempFile;
                                sourceFile = tempFile;

                                if (previewDurationSeconds > 0.0)
                                    stepTrimPreview();
                                else
                                    stepCreateProduction();
                            });
                            return;
                        }
                    }
                    else { error = "Could not create WAV writer"; }
                }
                else { error = "Could not create temp file for channel extraction"; }

                tempFile.deleteFile();
            }
        }
        else { error = "Could not read source file"; }

        juce::MessageManager::callAsync ([this, error]
        {
            if (cancelled) return;
            setError ("Channel extraction failed: " + error);
        });
    });
}

void ProcessingWorkflow::stepTrimPreview()
{
    setState (State::Trimming);
    if (listener)
        listener->workflowProgressChanged (-1.0, "Trimming to " + juce::String (juce::roundToInt (previewDurationSeconds)) + "s preview...");

    double trimSeconds = previewDurationSeconds;

    juce::Thread::launch ([this, trimSeconds]
    {
        juce::AudioFormatManager mgr;
        mgr.registerBasicFormats();

        bool success = false;
        juce::String error;

        if (auto* reader = mgr.createReaderFor (sourceFile))
        {
            std::unique_ptr<juce::AudioFormatReader> readerOwner (reader);

            juce::int64 samplesToWrite = (juce::int64) (reader->sampleRate * trimSeconds);
            if (samplesToWrite > reader->lengthInSamples)
                samplesToWrite = reader->lengthInSamples;

            auto tempFile = juce::File::getSpecialLocation (juce::File::tempDirectory)
                .getChildFile ("auphonic_trim_" + juce::String (juce::Random::getSystemRandom().nextInt64()) + ".wav");

            juce::WavAudioFormat wavFormat;
            auto os = std::make_unique<juce::FileOutputStream> (tempFile);

            if (os->openedOk())
            {
                if (auto* writer = wavFormat.createWriterFor (
                        os.get(),
                        reader->sampleRate,
                        reader->numChannels,
                        static_cast<int> (reader->bitsPerSample),
                        reader->metadataValues,
                        0))
                {
                    os.release(); // writer owns the stream
                    std::unique_ptr<juce::AudioFormatWriter> writerOwner (writer);

                    const int blockSize = 65536;
                    juce::AudioBuffer<float> buffer (static_cast<int> (reader->numChannels), blockSize);
                    juce::int64 samplesRemaining = samplesToWrite;
                    juce::int64 startSample = 0;

                    success = true;
                    while (samplesRemaining > 0)
                    {
                        int samplesToRead = (int) juce::jmin ((juce::int64) blockSize, samplesRemaining);
                        if (! reader->read (&buffer, 0, samplesToRead, startSample, true, true))
                        {
                            success = false;
                            error = "Failed to read source audio";
                            break;
                        }

                        if (! writer->writeFromAudioSampleBuffer (buffer, 0, samplesToRead))
                        {
                            success = false;
                            error = "Failed to write trimmed audio";
                            break;
                        }

                        startSample += samplesToRead;
                        samplesRemaining -= samplesToRead;
                    }

                    if (success)
                    {
                        juce::MessageManager::callAsync ([this, tempFile]
                        {
                            if (cancelled) return;
                            trimmedTempFile = tempFile;
                            sourceFile = tempFile;
                            stepCreateProduction();
                        });
                        return;
                    }
                }
                else { error = "Could not create WAV writer"; }
            }
            else { error = "Could not create temp file for trimming"; }

            tempFile.deleteFile();
        }
        else { error = "Could not read source file"; }

        juce::MessageManager::callAsync ([this, error]
        {
            if (cancelled) return;
            setError ("Preview trimming failed: " + error);
        });
    });
}

void ProcessingWorkflow::stepCreateProduction()
{
    setState (State::CreatingProduction);
    if (listener)
        listener->workflowProgressChanged (-1.0, "Creating production...");

    api.createProduction (presetId, settings, originalSourceFile.getFileNameWithoutExtension(),
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

            // Clean up temp files after successful upload
            cleanupTempFile (extractedTempFile);
            cleanupTempFile (trimmedTempFile);

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

    juce::String suffix = avoidOverwrite ? outputSuffix : juce::String{};
    auto dir = originalSourceFile.getParentDirectory();
    auto baseName = originalSourceFile.getFileNameWithoutExtension() + suffix;
    auto ext = tempFile.getFileExtension();

    auto outputFile = dir.getChildFile (baseName + ext);

    // If the file already exists (and it's not the original we intend to overwrite), add _2, _3, etc.
    if (outputFile.existsAsFile() && (avoidOverwrite || outputFile != originalSourceFile))
    {
        int counter = 2;
        while (dir.getChildFile (baseName + "_" + juce::String (counter) + ext).existsAsFile())
            ++counter;
        outputFile = dir.getChildFile (baseName + "_" + juce::String (counter) + ext);
    }

    if (listener)
        listener->workflowProgressChanged (-1.0, "Saving " + outputFile.getFileName() + "...");

    bool success = tempFile.moveFileTo (outputFile);
    if (success)
    {
        lastOutputFile = outputFile;

        if (keepTimecode && outputFile.getFileExtension().toLowerCase() == ".wav")
        {
            juce::MemoryBlock ixmlData;
            if (WavChunkCopier::readIxmlChunk (originalSourceFile, ixmlData))
            {
                int outputBitDepth = WavChunkCopier::readWavBitDepth (outputFile);
                auto updatedIxml = WavChunkCopier::updateIxmlForOutput (ixmlData, outputBitDepth, extractChannel);

                if (updatedIxml.getSize() > 0)
                {
                    if (! WavChunkCopier::writeIxmlChunk (outputFile, updatedIxml))
                        DBG ("Warning: failed to write iXML chunk to output file");
                }
                else
                {
                    DBG ("Warning: failed to update iXML content");
                }
            }

            juce::MemoryBlock bextData;
            if (WavChunkCopier::readChunk (originalSourceFile, "bext", bextData))
            {
                if (! WavChunkCopier::writeChunk (outputFile, "bext", bextData))
                    DBG ("Warning: failed to write bext chunk to output file");
            }

            // Remove the LIST/INFO chunk that Auphonic adds (duplicates bext metadata)
            WavChunkCopier::removeChunk (outputFile, "LIST");
        }

        if (writeSettingsXml)
        {
            auto root = std::make_unique<juce::DynamicObject>();
            root->setProperty ("input_file",  originalSourceFile.getFullPathName());
            root->setProperty ("output_file", outputFile.getFullPathName());
            root->setProperty ("processed_at", juce::Time::getCurrentTime().formatted ("%Y-%m-%d %H:%M:%S"));

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
