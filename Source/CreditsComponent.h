#pragma once

#include <juce_gui_basics/juce_gui_basics.h>
#include <juce_audio_formats/juce_audio_formats.h>
#include "AuphonicApiClient.h"

class CreditsComponent : public juce::Component
{
public:
    CreditsComponent();

    void paint (juce::Graphics& g) override;

    void setCredits (const UserCredits& credits);
    void setFile (const juce::File& file);
    int getFileChannels() const { return fileChannels; }

private:
    static juce::String formatTime (double hours);

    double availableCredits = -1.0;  // negative means not yet loaded
    double fileCostHours = 0.0;
    int fileChannels = 0;
    double fileDurationSeconds = 0.0;
    bool fileLoaded = false;

    juce::AudioFormatManager formatManager;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR (CreditsComponent)
};
