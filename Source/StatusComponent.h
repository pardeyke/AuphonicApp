#pragma once

#include <juce_gui_basics/juce_gui_basics.h>

class StatusComponent : public juce::Component
{
public:
    StatusComponent();

    void resized() override;

    void setStatus (const juce::String& text);
    void setProgress (double value); // 0.0 - 1.0, negative to hide
    void setOutputFile (const juce::File& file);
    void setOutputDirectory (const juce::File& dir);
    void reset();

private:
    juce::Label statusLabel { {}, "Status: Ready" };
    juce::ProgressBar progressBar;
    juce::TextButton showInFinderButton { "Show in Finder" };
    juce::File outputFile;
    juce::File outputDirectory;
    double progress = -1.0;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR (StatusComponent)
};
