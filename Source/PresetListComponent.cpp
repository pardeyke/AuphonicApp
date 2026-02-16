#include "PresetListComponent.h"

PresetListComponent::PresetListComponent()
{
    addAndMakeVisible (label);
    addAndMakeVisible (comboBox);

    comboBox.setTextWhenNothingSelected ("Select a preset...");
    comboBox.onChange = [this]
    {
        if (onSelectionChanged)
            onSelectionChanged();
    };
}

void PresetListComponent::resized()
{
    auto area = getLocalBounds();
    label.setBounds (area.removeFromLeft (60));
    comboBox.setBounds (area);
}

void PresetListComponent::setPresets (const juce::Array<AuphonicPreset>& presets)
{
    presetList = presets;
    comboBox.clear (juce::dontSendNotification);

    for (int i = 0; i < presets.size(); ++i)
        comboBox.addItem (presets[i].name, i + 1);
}

juce::String PresetListComponent::getSelectedPresetUuid() const
{
    auto idx = comboBox.getSelectedItemIndex();
    if (idx >= 0 && idx < presetList.size())
        return presetList[idx].uuid;
    return {};
}

bool PresetListComponent::hasSelection() const
{
    return comboBox.getSelectedItemIndex() >= 0;
}
