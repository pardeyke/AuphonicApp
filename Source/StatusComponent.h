#pragma once

#include <juce_gui_basics/juce_gui_basics.h>

class StatusComponent : public juce::Component
{
public:
    StatusComponent();

    void resized() override;

    void setStatus (const juce::String& text);
    void setProgress (double value); // 0.0 - 1.0, negative to hide
    void reset();

private:
    juce::Label statusLabel { {}, "Status: Ready" };
    juce::ProgressBar progressBar;
    double progress = -1.0;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR (StatusComponent)
};
