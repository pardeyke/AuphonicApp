#pragma once

#include <juce_gui_basics/juce_gui_basics.h>

class PreviewDurationComponent : public juce::Component
{
public:
    PreviewDurationComponent();

    void resized() override;

    void setFileDuration (double durationSeconds);
    double getPreviewDurationSeconds() const;

    void setForceFullDuration (bool force);

    std::function<void()> onChange;

private:
    struct Preset
    {
        juce::String label;
        double seconds; // 0 = full
    };

    static const std::vector<Preset>& getPresets();

    void updateVisibleButtons();
    void selectButton (int index);

    std::vector<std::unique_ptr<juce::TextButton>> buttons;
    int selectedIndex = 0; // 0 = "Full"
    double fileDuration = 0.0;
    bool forceFullDuration = false;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR (PreviewDurationComponent)
};
