#include "CreditsComponent.h"

CreditsComponent::CreditsComponent()
{
    formatManager.registerBasicFormats();
}

juce::String CreditsComponent::formatTime (double hours)
{
    if (hours < 0.0)
        hours = 0.0;

    int totalMinutes = juce::roundToInt (hours * 60.0);
    int h = totalMinutes / 60;
    int m = totalMinutes % 60;

    if (h > 0)
        return juce::String (h) + "h " + juce::String (m) + "m";

    return juce::String (m) + "m";
}

void CreditsComponent::setCredits (const UserCredits& credits)
{
    availableCredits = credits.credits;
    repaint();
}

void CreditsComponent::setFile (const juce::File& file)
{
    fileCostHours = 0.0;
    fileChannels = 0;
    fileDurationSeconds = 0.0;
    fileLoaded = false;

    if (file.existsAsFile())
    {
        std::unique_ptr<juce::AudioFormatReader> reader (formatManager.createReaderFor (file));

        if (reader != nullptr)
        {
            fileDurationSeconds = (double) reader->lengthInSamples / reader->sampleRate;
            fileChannels = (int) reader->numChannels;

            double durationHours = fileDurationSeconds / 3600.0;
            fileCostHours = durationHours;
            fileLoaded = true;
        }
    }

    repaint();
}

void CreditsComponent::paint (juce::Graphics& g)
{
    if (availableCredits < 0.0)
        return;  // credits not loaded yet

    auto area = getLocalBounds().reduced (4, 0);
    g.setFont (juce::FontOptions (13.0f));

    // Credits remaining
    g.setColour (findColour (juce::Label::textColourId));
    g.drawText ("Credits: " + formatTime (availableCredits),
                area.removeFromLeft (area.getWidth() / 3),
                juce::Justification::centredLeft, true);

    if (fileLoaded)
    {
        // File cost
        int durationSecs = juce::roundToInt (fileDurationSeconds);
        int mins = durationSecs / 60;
        int secs = durationSecs % 60;
        juce::String costText = "This file: " + juce::String (mins) + "m "
                              + juce::String (secs) + "s ("
                              + juce::String (fileChannels) + "ch)";

        g.drawText (costText,
                    area.removeFromLeft (area.getWidth() / 2),
                    juce::Justification::centred, true);

        // After processing
        double remaining = availableCredits - fileCostHours;
        if (remaining < 0.0)
            g.setColour (juce::Colours::red);

        g.drawText ("After: " + formatTime (remaining),
                    area, juce::Justification::centredRight, true);
    }
}
