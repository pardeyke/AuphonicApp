#pragma once

#include <juce_core/juce_core.h>

namespace WavChunkCopier
{
    /** Reads the iXML chunk data from a WAV file.
        Returns true if found, with chunkData populated (raw iXML content, excluding header). */
    bool readIxmlChunk (const juce::File& wavFile, juce::MemoryBlock& chunkData);

    /** Appends an iXML chunk to a WAV file. The file must be a valid RIFF/WAVE.
        Updates the RIFF size header to account for the new chunk.
        If an iXML chunk already exists, does nothing and returns true.
        Returns true on success. */
    bool writeIxmlChunk (const juce::File& wavFile, const juce::MemoryBlock& chunkData);
}
