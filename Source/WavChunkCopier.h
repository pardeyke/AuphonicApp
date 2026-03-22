#pragma once

#include <juce_core/juce_core.h>

namespace WavChunkCopier
{
    /** Reads the iXML chunk data from a WAV file.
        Returns true if found, with chunkData populated (raw iXML content, excluding header). */
    bool readIxmlChunk (const juce::File& wavFile, juce::MemoryBlock& chunkData);

    /** Parses iXML data and returns track names indexed by channel (1-based).
        Returns an empty array if no TRACK_LIST is found.
        Index 0 is unused; index 1 = channel 1 name, etc. */
    juce::StringArray readIxmlTrackNames (const juce::File& wavFile);

    /** Modifies iXML content to match the output file:
        - Updates AUDIO_BIT_DEPTH to the given value
        - If extractedChannel > 0, removes all tracks except that one and sets TRACK_COUNT to 1
        Returns the modified iXML as a MemoryBlock, or empty on failure. */
    juce::MemoryBlock updateIxmlForOutput (const juce::MemoryBlock& ixmlData,
                                           int outputBitDepth,
                                           int extractedChannel);

    /** Reads the bit depth from a WAV file's fmt chunk. Returns 0 on failure. */
    int readWavBitDepth (const juce::File& wavFile);

    /** Appends an iXML chunk to a WAV file. The file must be a valid RIFF/WAVE.
        Updates the RIFF size header to account for the new chunk.
        If an iXML chunk already exists, does nothing and returns true.
        Returns true on success. */
    bool writeIxmlChunk (const juce::File& wavFile, const juce::MemoryBlock& chunkData);
}
