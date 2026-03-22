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

bool readIxmlChunk (const juce::File& wavFile, juce::MemoryBlock& chunkData)
{
    juce::FileInputStream stream (wavFile);
    if (! stream.openedOk())
        return false;

    if (! isRiffWave (stream))
        return false;

    return findChunk (stream, "iXML", &chunkData);
}

bool writeIxmlChunk (const juce::File& wavFile, const juce::MemoryBlock& chunkData)
{
    // First, verify this is a RIFF/WAVE file and check for existing iXML
    {
        juce::FileInputStream stream (wavFile);
        if (! stream.openedOk())
            return false;

        if (! isRiffWave (stream))
            return false;

        if (findChunk (stream, "iXML", nullptr))
            return true; // already has iXML, nothing to do
    }

    // Build the chunk: "iXML" tag + 4-byte LE size + data + optional pad byte
    auto dataSize = (uint32_t) chunkData.getSize();
    bool needsPad = (dataSize & 1) != 0;
    size_t chunkTotalSize = 8 + dataSize + (needsPad ? 1 : 0);

    juce::MemoryBlock chunkBytes (chunkTotalSize, true);
    auto* dst = static_cast<char*> (chunkBytes.getData());

    // Tag
    std::memcpy (dst, "iXML", 4);

    // Size (little-endian)
    dst[4] = (char) (dataSize & 0xFF);
    dst[5] = (char) ((dataSize >> 8) & 0xFF);
    dst[6] = (char) ((dataSize >> 16) & 0xFF);
    dst[7] = (char) ((dataSize >> 24) & 0xFF);

    // Data
    std::memcpy (dst + 8, chunkData.getData(), dataSize);

    // Pad byte is already zero from MemoryBlock initialization

    // Append chunk to file
    if (! wavFile.appendData (chunkBytes.getData(), chunkBytes.getSize()))
        return false;

    // Update the RIFF size field at offset 4
    auto newFileSize = wavFile.getSize();
    uint32_t riffSize = (uint32_t) (newFileSize - 8);

    // Read entire file, patch the size, write back — safest approach
    // (JUCE FileOutputStream truncates on open, so we can't just seek + write)
    juce::MemoryBlock fileData;
    if (! wavFile.loadFileAsData (fileData))
        return false;

    if (fileData.getSize() < 8)
        return false;

    auto* fileBytes = static_cast<char*> (fileData.getData());
    fileBytes[4] = (char) (riffSize & 0xFF);
    fileBytes[5] = (char) ((riffSize >> 8) & 0xFF);
    fileBytes[6] = (char) ((riffSize >> 16) & 0xFF);
    fileBytes[7] = (char) ((riffSize >> 24) & 0xFF);

    return wavFile.replaceWithData (fileData.getData(), fileData.getSize());
}

} // namespace WavChunkCopier
