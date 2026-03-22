#include "PreviewDurationComponent.h"

const std::vector<PreviewDurationComponent::Preset>& PreviewDurationComponent::getPresets()
{
    static const std::vector<Preset> presets =
    {
        { "Full",  0.0 },
        { "30s",   30.0 },
        { "1m",    60.0 },
        { "3m",    180.0 },
        { "5m",    300.0 },
        { "10m",   600.0 }
    };
    return presets;
}

PreviewDurationComponent::PreviewDurationComponent()
{
    for (size_t i = 0; i < getPresets().size(); ++i)
    {
        auto btn = std::make_unique<juce::TextButton> (getPresets()[i].label);
        btn->setClickingTogglesState (false);
        btn->onClick = [this, idx = (int) i] { selectButton (idx); };
        addChildComponent (btn.get());
        buttons.push_back (std::move (btn));
    }

    // "Full" is always visible and selected by default
    buttons[0]->setVisible (true);
    selectButton (0);
}

void PreviewDurationComponent::resized()
{
    auto area = getLocalBounds();
    int spacing = 4;

    // Count visible buttons
    int visibleCount = 0;
    for (auto& btn : buttons)
        if (btn->isVisible())
            ++visibleCount;

    if (visibleCount == 0)
        return;

    int totalSpacing = spacing * (visibleCount - 1);
    int btnWidth = (area.getWidth() - totalSpacing) / visibleCount;

    for (auto& btn : buttons)
    {
        if (btn->isVisible())
        {
            btn->setBounds (area.removeFromLeft (btnWidth));
            area.removeFromLeft (spacing);
        }
    }
}

void PreviewDurationComponent::setFileDuration (double durationSeconds)
{
    fileDuration = durationSeconds;
    updateVisibleButtons();

    // If selected preset is now hidden, revert to Full
    if (selectedIndex > 0 && ! buttons[(size_t) selectedIndex]->isVisible())
        selectButton (0);
}

double PreviewDurationComponent::getPreviewDurationSeconds() const
{
    if (selectedIndex <= 0 || selectedIndex >= (int) getPresets().size())
        return 0.0;

    return getPresets()[(size_t) selectedIndex].seconds;
}

void PreviewDurationComponent::updateVisibleButtons()
{
    const auto& presets = getPresets();

    // "Full" is always visible
    buttons[0]->setVisible (true);

    for (size_t i = 1; i < presets.size(); ++i)
        buttons[i]->setVisible (presets[i].seconds < fileDuration);

    resized();
}

void PreviewDurationComponent::setForceFullDuration (bool force)
{
    forceFullDuration = force;

    if (force)
    {
        selectButton (0);
        for (auto& btn : buttons)
            btn->setEnabled (false);
    }
    else
    {
        for (auto& btn : buttons)
            btn->setEnabled (true);
    }
}

void PreviewDurationComponent::selectButton (int index)
{
    selectedIndex = index;

    auto highlight = findColour (juce::TextButton::buttonOnColourId);
    auto normal = findColour (juce::TextButton::buttonColourId);

    for (int i = 0; i < (int) buttons.size(); ++i)
    {
        bool selected = (i == selectedIndex);
        buttons[(size_t) i]->setColour (juce::TextButton::buttonColourId,
                                         selected ? highlight : normal);
    }

    if (onChange)
        onChange();
}
