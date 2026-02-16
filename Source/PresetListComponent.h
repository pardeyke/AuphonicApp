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
    juce::String getSelectedPresetName() const;
    bool hasSelection() const;
    void setSelectedUuid (const juce::String& uuid);

    void setModified (bool modified);
    bool isModified() const;
    juce::String getBasePresetUuid() const;
    juce::String getBasePresetName() const;

    std::function<void()> onSelectionChanged;

private:
    juce::Label label { {}, "Preset:" };
    juce::ComboBox comboBox;
    juce::Array<AuphonicPreset> presetList;

    bool modified = false;
    juce::String basePresetUuid;
    juce::String basePresetName;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR (PresetListComponent)
};
