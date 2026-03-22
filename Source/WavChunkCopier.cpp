#include "WavChunkCopier.h"

namespace WavChunkCopier
{

static bool isRiffWave (juce::InputStream& stream)
{
    char riffTag[4], waveTag[4];
    if (stream.read (riffTag, 4) != 4) return false;
    stream.readInt();  // skip RIFF size
    if (stream.read (waveTag, 4) != 4) return false;

    return std::memcmp (riffTag, "RIFF", 4) == 0
        && std::memcmp (waveTag, "WAVE", 4) == 0;
}

static bool findChunk (juce::InputStream& stream, const char* targetTag, juce::MemoryBlock* outData)
{
    // Stream must be positioned at byte 12 (after RIFF header + "WAVE")
    while (! stream.isExhausted())
    {
        char tag[4];
        if (stream.read (tag, 4) != 4)
            return false;

        auto chunkSize = (uint32_t) stream.readInt();

        if (std::memcmp (tag, targetTag, 4) == 0)
        {
            if (outData != nullptr)
            {
                outData->setSize (chunkSize);
                if (stream.read (outData->getData(), (int) chunkSize) != (int) chunkSize)
                    return false;
            }
            return true;
        }

        // Skip this chunk's data (+ pad byte if size is odd)
        auto skipBytes = (int64_t) chunkSize + (chunkSize & 1);
        if (! stream.setPosition (stream.getPosition() + skipBytes))
            return false;
    }

    return false;
}

// ── Helper: set or create a child element's text ──

static void setChildText (juce::XmlElement* parent, const juce::String& tagName, const juce::String& value)
{
    if (auto* child = parent->getChildByName (tagName))
    {
        child->deleteAllChildElements();
        child->addTextElement (value);
    }
}

// ── Public API ──

bool readChunk (const juce::File& wavFile, const char* chunkId, juce::MemoryBlock& chunkData)
{
    juce::FileInputStream stream (wavFile);
    if (! stream.openedOk())
        return false;

    if (! isRiffWave (stream))
        return false;

    return findChunk (stream, chunkId, &chunkData);
}

bool readIxmlChunk (const juce::File& wavFile, juce::MemoryBlock& chunkData)
{
    return readChunk (wavFile, "iXML", chunkData);
}

juce::StringArray readIxmlTrackNames (const juce::File& wavFile)
{
    juce::MemoryBlock ixmlData;
    if (! readIxmlChunk (wavFile, ixmlData))
        return {};

    auto xmlText = juce::String::fromUTF8 (static_cast<const char*> (ixmlData.getData()),
                                            (int) ixmlData.getSize());
    auto xml = juce::XmlDocument::parse (xmlText);
    if (xml == nullptr)
        return {};

    auto* trackList = xml->getChildByName ("TRACK_LIST");
    if (trackList == nullptr)
        return {};

    // Use INTERLEAVE_INDEX (physical position in the WAV file) to map track names,
    // since CHANNEL_INDEX can be non-contiguous (e.g. mixer channels 1, 2, 4)
    int maxInterleave = 0;
    for (auto* track = trackList->getChildByName ("TRACK"); track != nullptr;
         track = track->getNextElementWithTagName ("TRACK"))
    {
        int idx = track->getChildElementAllSubText ("INTERLEAVE_INDEX", "0").getIntValue();
        if (idx > maxInterleave)
            maxInterleave = idx;
    }

    if (maxInterleave == 0)
        return {};

    // Index 0 unused, indices 1..maxInterleave hold track names
    juce::StringArray names;
    for (int i = 0; i <= maxInterleave; ++i)
        names.add ({});

    for (auto* track = trackList->getChildByName ("TRACK"); track != nullptr;
         track = track->getNextElementWithTagName ("TRACK"))
    {
        int idx = track->getChildElementAllSubText ("INTERLEAVE_INDEX", "0").getIntValue();
        auto name = track->getChildElementAllSubText ("NAME", "").trim();
        if (idx >= 1 && idx <= maxInterleave)
            names.set (idx, name);
    }

    return names;
}

juce::MemoryBlock updateIxmlForOutput (const juce::MemoryBlock& ixmlData,
                                        int outputBitDepth,
                                        int extractedChannel)
{
    auto xmlText = juce::String::fromUTF8 (static_cast<const char*> (ixmlData.getData()),
                                            (int) ixmlData.getSize());
    auto xml = juce::XmlDocument::parse (xmlText);
    if (xml == nullptr)
        return {};

    // Update AUDIO_BIT_DEPTH in SPEED element
    if (auto* speed = xml->getChildByName ("SPEED"))
    {
        if (outputBitDepth > 0)
            setChildText (speed, "AUDIO_BIT_DEPTH", juce::String (outputBitDepth));
    }

    // Update TRACK_LIST if a single channel was extracted
    if (extractedChannel > 0)
    {
        if (auto* trackList = xml->getChildByName ("TRACK_LIST"))
        {
            // Find the track matching the extracted channel and copy its name
            // before deleting (to avoid use-after-free)
            juce::String matchedTrackName;
            bool foundMatch = false;
            for (auto* track = trackList->getChildByName ("TRACK"); track != nullptr;
                 track = track->getNextElementWithTagName ("TRACK"))
            {
                int idx = track->getChildElementAllSubText ("CHANNEL_INDEX", "0").getIntValue();
                if (idx == extractedChannel)
                {
                    matchedTrackName = track->getChildElementAllSubText ("NAME", "");
                    foundMatch = true;
                    break;
                }
            }

            // Now safe to delete all TRACK children
            trackList->deleteAllChildElementsWithTagName ("TRACK");

            setChildText (trackList, "TRACK_COUNT", "1");

            if (foundMatch)
            {
                auto newTrack = std::make_unique<juce::XmlElement> ("TRACK");

                auto addChild = [&] (const juce::String& tag, const juce::String& val) {
                    auto* el = newTrack->createNewChildElement (tag);
                    el->addTextElement (val);
                };

                addChild ("CHANNEL_INDEX", "1");
                addChild ("INTERLEAVE_INDEX", "1");

                if (matchedTrackName.isNotEmpty())
                    addChild ("NAME", matchedTrackName);

                trackList->addChildElement (newTrack.release());
            }
        }
    }

    auto updatedText = xml->toString();
    auto utf8 = updatedText.toUTF8();
    return juce::MemoryBlock (utf8.getAddress(), utf8.sizeInBytes() - 1); // exclude null terminator
}

int readWavBitDepth (const juce::File& wavFile)
{
    juce::FileInputStream stream (wavFile);
    if (! stream.openedOk())
        return 0;

    if (! isRiffWave (stream))
        return 0;

    // Find the "fmt " chunk
    juce::MemoryBlock fmtData;
    if (! findChunk (stream, "fmt ", &fmtData))
        return 0;

    if (fmtData.getSize() < 16)
        return 0;

    // Bits per sample is at offset 14 in the fmt chunk (2 bytes, little-endian)
    auto* bytes = static_cast<const uint8_t*> (fmtData.getData());
    return (int) bytes[14] | ((int) bytes[15] << 8);
}

bool writeChunk (const juce::File& wavFile, const char* chunkId, const juce::MemoryBlock& chunkData)
{
    // Load entire file into memory
    juce::MemoryBlock fileData;
    if (! wavFile.loadFileAsData (fileData))
        return false;

    auto* src = static_cast<const uint8_t*> (fileData.getData());
    auto fileSize = fileData.getSize();

    if (fileSize < 12)
        return false;

    // Verify RIFF/WAVE header
    if (std::memcmp (src, "RIFF", 4) != 0 || std::memcmp (src + 8, "WAVE", 4) != 0)
        return false;

    // Build output: copy all chunks except any existing one with the same ID,
    // then append the new chunk at the end
    juce::MemoryBlock output;
    output.append (src, 12); // RIFF header + "WAVE"

    size_t pos = 12;
    while (pos + 8 <= fileSize)
    {
        auto* tag = src + pos;
        uint32_t sz = (uint32_t) src[pos + 4]
                    | ((uint32_t) src[pos + 5] << 8)
                    | ((uint32_t) src[pos + 6] << 16)
                    | ((uint32_t) src[pos + 7] << 24);
        size_t chunkTotal = 8 + sz + (sz & 1); // header + data + pad

        if (pos + chunkTotal > fileSize)
            chunkTotal = fileSize - pos; // truncated last chunk: keep as-is

        // Skip chunks matching the target ID — we'll append the replacement
        if (std::memcmp (tag, chunkId, 4) != 0)
            output.append (src + pos, chunkTotal);

        pos += chunkTotal;
    }

    // Append the new chunk
    {
        auto dataSize = (uint32_t) chunkData.getSize();
        bool needsPad = (dataSize & 1) != 0;
        size_t newChunkSize = 8 + dataSize + (needsPad ? 1 : 0);

        juce::MemoryBlock chunkBytes (newChunkSize, true);
        auto* dst = static_cast<char*> (chunkBytes.getData());

        std::memcpy (dst, chunkId, 4);
        dst[4] = (char) (dataSize & 0xFF);
        dst[5] = (char) ((dataSize >> 8) & 0xFF);
        dst[6] = (char) ((dataSize >> 16) & 0xFF);
        dst[7] = (char) ((dataSize >> 24) & 0xFF);
        std::memcpy (dst + 8, chunkData.getData(), dataSize);

        output.append (chunkBytes.getData(), chunkBytes.getSize());
    }

    // Patch RIFF size at offset 4
    auto* outBytes = static_cast<char*> (output.getData());
    uint32_t riffSize = (uint32_t) (output.getSize() - 8);
    outBytes[4] = (char) (riffSize & 0xFF);
    outBytes[5] = (char) ((riffSize >> 8) & 0xFF);
    outBytes[6] = (char) ((riffSize >> 16) & 0xFF);
    outBytes[7] = (char) ((riffSize >> 24) & 0xFF);

    return wavFile.replaceWithData (output.getData(), output.getSize());
}

bool removeChunk (const juce::File& wavFile, const char* chunkId)
{
    juce::MemoryBlock fileData;
    if (! wavFile.loadFileAsData (fileData))
        return false;

    auto* src = static_cast<const uint8_t*> (fileData.getData());
    auto fileSize = fileData.getSize();

    if (fileSize < 12)
        return false;

    if (std::memcmp (src, "RIFF", 4) != 0 || std::memcmp (src + 8, "WAVE", 4) != 0)
        return false;

    juce::MemoryBlock output;
    output.append (src, 12);

    bool found = false;
    size_t pos = 12;
    while (pos + 8 <= fileSize)
    {
        auto* tag = src + pos;
        uint32_t sz = (uint32_t) src[pos + 4]
                    | ((uint32_t) src[pos + 5] << 8)
                    | ((uint32_t) src[pos + 6] << 16)
                    | ((uint32_t) src[pos + 7] << 24);
        size_t chunkTotal = 8 + sz + (sz & 1);

        if (pos + chunkTotal > fileSize)
            chunkTotal = fileSize - pos;

        if (std::memcmp (tag, chunkId, 4) == 0)
            found = true;
        else
            output.append (src + pos, chunkTotal);

        pos += chunkTotal;
    }

    if (! found)
        return true; // nothing to remove

    // Patch RIFF size
    auto* outBytes = static_cast<char*> (output.getData());
    uint32_t riffSize = (uint32_t) (output.getSize() - 8);
    outBytes[4] = (char) (riffSize & 0xFF);
    outBytes[5] = (char) ((riffSize >> 8) & 0xFF);
    outBytes[6] = (char) ((riffSize >> 16) & 0xFF);
    outBytes[7] = (char) ((riffSize >> 24) & 0xFF);

    return wavFile.replaceWithData (output.getData(), output.getSize());
}

bool writeIxmlChunk (const juce::File& wavFile, const juce::MemoryBlock& chunkData)
{
    return writeChunk (wavFile, "iXML", chunkData);
}

} // namespace WavChunkCopier
