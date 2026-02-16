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

    comboBox.addItem ("(No preset)", 1);

    for (int i = 0; i < presets.size(); ++i)
        comboBox.addItem (presets[i].name, i + 2);
}

juce::String PresetListComponent::getSelectedPresetUuid() const
{
    auto id = comboBox.getSelectedId();
    if (id <= 1) // nothing selected or "(No preset)"
        return {};

    auto idx = id - 2;
    if (idx >= 0 && idx < presetList.size())
        return presetList[idx].uuid;
    return {};
}

bool PresetListComponent::hasSelection() const
{
    return comboBox.getSelectedId() > 1;
}

void PresetListComponent::setSelectedUuid (const juce::String& uuid)
{
    if (uuid.isEmpty())
    {
        comboBox.setSelectedId (1, juce::dontSendNotification);
        return;
    }

    for (int i = 0; i < presetList.size(); ++i)
    {
        if (presetList[i].uuid == uuid)
        {
            comboBox.setSelectedId (i + 2, juce::dontSendNotification);
            return;
        }
    }

    comboBox.setSelectedId (1, juce::dontSendNotification);
}
