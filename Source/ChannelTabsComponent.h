#pragma once

#include <juce_gui_basics/juce_gui_basics.h>
#include "ManualOptionsComponent.h"

class ChannelTabsComponent : public juce::Component
{
public:
    ChannelTabsComponent();

    void resized() override;

    void setChannels (int numChannels, const juce::StringArray& trackNames, int bitDepth);

    struct ChannelSettings {
        int channel;        // 1-based channel index
        juce::var settings; // algorithm settings with forced WAV output format
    };

    juce::Array<ChannelSettings> getEnabledChannelSettings() const;
    int getEnabledChannelCount() const;
    bool hasAnyChannelEnabled() const;

    bool shouldAvoidOverwrite() const  { return avoidOverwriteToggle.getToggleState(); }
    juce::String getOutputSuffix() const { return suffixEditor.getText(); }
    bool shouldWriteSettingsXml() const { return writeXmlToggle.getToggleState(); }

    ManualOptionsComponent* getChannelOptions (int channelIndex);
    ManualOptionsComponent* getActiveTabOptions();

    std::function<void()> onChange;

private:
    void notifyChange();

    struct ChannelTab {
        std::unique_ptr<juce::Viewport> viewport;
        std::unique_ptr<ManualOptionsComponent> options;
    };

    std::unique_ptr<juce::TabbedComponent> tabbedComponent;
    juce::OwnedArray<ChannelTab> channelTabs;

    // Shared output settings
    juce::ToggleButton avoidOverwriteToggle { "Create a new file (don't overwrite)" };
    juce::Label suffixLabel { {}, "Suffix:" };
    juce::TextEditor suffixEditor;
    juce::ToggleButton writeXmlToggle { "Write settings JSON alongside output" };

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR (ChannelTabsComponent)
};
