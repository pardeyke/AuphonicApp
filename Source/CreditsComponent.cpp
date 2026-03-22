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
    // Subtract 2 free hours (watermarked) to show only paid credits
    availableCredits = credits.credits - 2.0;
    repaint();
}

void CreditsComponent::setFile (const juce::File& file)
{
    fileCostHours = 0.0;
    fileChannels = 0;
    fileDurationSeconds = 0.0;
    fileLoaded = false;
    batchFileCount = 0;
    batchTotalDurationSeconds = 0.0;

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

void CreditsComponent::setFiles (const juce::Array<juce::File>& files)
{
    batchFileCount = files.size();
    batchTotalDurationSeconds = 0.0;

    for (auto& file : files)
    {
        if (file.existsAsFile())
        {
            std::unique_ptr<juce::AudioFormatReader> reader (formatManager.createReaderFor (file));
            if (reader != nullptr)
                batchTotalDurationSeconds += (double) reader->lengthInSamples / reader->sampleRate;
        }
    }

    fileCostHours = batchTotalDurationSeconds / 3600.0;
    fileDurationSeconds = batchTotalDurationSeconds;
    fileLoaded = batchFileCount > 0;
    repaint();
}

void CreditsComponent::setPreviewDurationSeconds (double seconds)
{
    previewDuration = seconds;
    repaint();
}

void CreditsComponent::setChannelMultiplier (int multiplier)
{
    channelMultiplier = juce::jmax (1, multiplier);
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
        juce::String costText;

        if (batchFileCount > 1)
        {
            // Batch mode: show total for all files
            double displayDuration = (previewDuration > 0.0)
                ? previewDuration * batchFileCount
                : batchTotalDurationSeconds;
            double displayCostHours = displayDuration / 3600.0 * channelMultiplier;

            int durationSecs = juce::roundToInt (displayDuration);
            int mins = durationSecs / 60;
            int secs = durationSecs % 60;
            costText = juce::String (batchFileCount) + " files, ~"
                     + juce::String (mins) + "m " + juce::String (secs) + "s total";

            if (previewDuration > 0.0)
                costText += " [preview]";

            g.drawText (costText,
                        area.removeFromLeft (area.getWidth() / 2),
                        juce::Justification::centred, true);

            double remaining = availableCredits - displayCostHours;
            if (remaining < 0.0)
                g.setColour (juce::Colours::red);

            g.drawText ("After: " + formatTime (remaining),
                        area, juce::Justification::centredRight, true);
        }
        else
        {
            // Single file mode (original behavior)
            double displayDuration = (previewDuration > 0.0) ? previewDuration : fileDurationSeconds;
            double displayCostHours = displayDuration / 3600.0 * channelMultiplier;

            int durationSecs = juce::roundToInt (displayDuration);
            int mins = durationSecs / 60;
            int secs = durationSecs % 60;
            costText = "This file: " + juce::String (mins) + "m "
                     + juce::String (secs) + "s ("
                     + juce::String (fileChannels) + "ch)";

            if (previewDuration > 0.0)
                costText += " [preview]";

            g.drawText (costText,
                        area.removeFromLeft (area.getWidth() / 2),
                        juce::Justification::centred, true);

            // After processing
            double remaining = availableCredits - displayCostHours;
            if (remaining < 0.0)
                g.setColour (juce::Colours::red);

            g.drawText ("After: " + formatTime (remaining),
                        area, juce::Justification::centredRight, true);
        }
    }
}
