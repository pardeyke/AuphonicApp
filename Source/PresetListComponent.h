#pragma once

#include <juce_gui_basics/juce_gui_basics.h>
#include "AuphonicApiClient.h"

class PresetListComponent : public juce::Component
{
public:
    PresetListComponent();

    void resized() override;

    void setPresets (const juce::Array<AuphonicPreset>& presets);
    juce::String getSelectedPresetUuid() const;
    bool hasSelection() const;
    void setSelectedUuid (const juce::String& uuid);

    std::function<void()> onSelectionChanged;

private:
    juce::Label label { {}, "Preset:" };
    juce::ComboBox comboBox;
    juce::Array<AuphonicPreset> presetList;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR (PresetListComponent)
};
