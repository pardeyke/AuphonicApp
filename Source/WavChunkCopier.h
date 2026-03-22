#pragma once

#include <juce_core/juce_core.h>
#include <map>

namespace WavChunkCopier
{
    /** Reads a named RIFF chunk from a WAV file.
        Returns true if found, with chunkData populated (raw content, excluding 8-byte header). */
    bool readChunk (const juce::File& wavFile, const char* chunkId, juce::MemoryBlock& chunkData);

    /** Reads the iXML chunk data from a WAV file. Convenience wrapper around readChunk. */
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

    /** Writes a named RIFF chunk to a WAV file, replacing any existing chunk with the same ID.
        Updates the RIFF size header. Returns true on success. */
    bool writeChunk (const juce::File& wavFile, const char* chunkId, const juce::MemoryBlock& chunkData);

    /** Removes a named RIFF chunk from a WAV file if present.
        Updates the RIFF size header. Returns true on success (including if chunk was not found). */
    bool removeChunk (const juce::File& wavFile, const char* chunkId);

    /** Convenience wrappers for iXML chunks. */
    bool writeIxmlChunk (const juce::File& wavFile, const juce::MemoryBlock& chunkData);

    /** Merges processed mono channel files back into a multi-channel WAV.
        processedChannelFiles maps 0-based channel index → processed mono WAV file.
        Channels not in the map are copied from the original file.
        Copies iXML and bext chunks from the original and removes LIST chunks. */
    bool mergeChannels (const juce::File& originalFile,
                        const juce::File& outputFile,
                        const std::map<int, juce::File>& processedChannelFiles);
}
