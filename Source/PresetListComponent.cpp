#include "PresetListComponent.h"

PresetListComponent::PresetListComponent()
{
    addAndMakeVisible (label);
    addAndMakeVisible (comboBox);

    comboBox.setTextWhenNothingSelected ("Select a preset...");
    comboBox.onChange = [this]
    {
        // User selected a new preset — clear modified state
        modified = false;
        auto uuid = getSelectedPresetUuid();
        basePresetUuid = uuid;
        basePresetName = getSelectedPresetName();

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

    modified = false;
    basePresetUuid = {};
    basePresetName = {};
}

juce::String PresetListComponent::getSelectedPresetUuid() const
{
    if (modified)
        return {}; // modified means we're not using the preset as-is

    auto id = comboBox.getSelectedId();
    if (id <= 1)
        return {};

    auto idx = id - 2;
    if (idx >= 0 && idx < presetList.size())
        return presetList[idx].uuid;
    return {};
}

juce::String PresetListComponent::getSelectedPresetName() const
{
    auto id = comboBox.getSelectedId();
    if (id <= 1)
        return {};

    auto idx = id - 2;
    if (idx >= 0 && idx < presetList.size())
        return presetList[idx].name;
    return {};
}

bool PresetListComponent::hasSelection() const
{
    return comboBox.getSelectedId() > 1;
}

void PresetListComponent::setSelectedUuid (const juce::String& uuid)
{
    modified = false;

    if (uuid.isEmpty())
    {
        comboBox.setSelectedId (1, juce::dontSendNotification);
        basePresetUuid = {};
        basePresetName = {};
        return;
    }

    for (int i = 0; i < presetList.size(); ++i)
    {
        if (presetList[i].uuid == uuid)
        {
            comboBox.setSelectedId (i + 2, juce::dontSendNotification);
            basePresetUuid = uuid;
            basePresetName = presetList[i].name;
            return;
        }
    }

    comboBox.setSelectedId (1, juce::dontSendNotification);
    basePresetUuid = {};
    basePresetName = {};
}

void PresetListComponent::setModified (bool isNowModified)
{
    if (modified == isNowModified)
        return;

    modified = isNowModified;

    if (modified && basePresetName.isNotEmpty())
    {
        comboBox.setSelectedId (0, juce::dontSendNotification);
        comboBox.setText (basePresetName + " (modified)", juce::dontSendNotification);
    }
}

bool PresetListComponent::isModified() const
{
    return modified;
}

juce::String PresetListComponent::getBasePresetUuid() const
{
    return basePresetUuid;
}

juce::String PresetListComponent::getBasePresetName() const
{
    return basePresetName;
}
