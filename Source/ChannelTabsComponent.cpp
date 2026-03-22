#include "ChannelTabsComponent.h"

ChannelTabsComponent::ChannelTabsComponent()
{
    addAndMakeVisible (avoidOverwriteToggle);
    avoidOverwriteToggle.onClick = [this] {
        suffixLabel.setVisible (avoidOverwriteToggle.getToggleState());
        suffixEditor.setVisible (avoidOverwriteToggle.getToggleState());
        resized();
        notifyChange();
    };

    addChildComponent (suffixLabel);
    addChildComponent (suffixEditor);
    suffixEditor.setText ("_auphonic", juce::dontSendNotification);
    suffixEditor.onTextChange = [this] { notifyChange(); };

    addAndMakeVisible (writeXmlToggle);
    writeXmlToggle.onClick = [this] { notifyChange(); };
}

void ChannelTabsComponent::setChannels (int numChannels, const juce::StringArray& trackNames, int bitDepth)
{
    // Remove old tabs
    tabbedComponent.reset();
    channelTabs.clear();

    if (numChannels <= 0)
        return;

    // Determine WAV output format based on bit depth
    juce::String wavFormat = (bitDepth >= 24) ? "wav-24bit" : "wav";

    tabbedComponent = std::make_unique<juce::TabbedComponent> (juce::TabbedButtonBar::TabsAtTop);
    addAndMakeVisible (tabbedComponent.get());

    auto tabColour = findColour (juce::ResizableWindow::backgroundColourId);

    for (int ch = 0; ch < numChannels; ++ch)
    {
        auto tab = new ChannelTab();

        tab->options = std::make_unique<ManualOptionsComponent>();
        tab->options->setPerChannelMode (true);
        tab->options->setForcedOutputFormat (wavFormat);
        tab->options->onChange = [this] { notifyChange(); };

        tab->viewport = std::make_unique<juce::Viewport>();
        tab->viewport->setViewedComponent (tab->options.get(), false);
        tab->viewport->setScrollBarsShown (true, false);

        // Build tab label
        juce::String label = "Ch " + juce::String (ch + 1);
        if (ch + 1 < trackNames.size() && trackNames[ch + 1].isNotEmpty())
            label += " (" + trackNames[ch + 1] + ")";
        else if (numChannels == 2)
            label += (ch == 0 ? " (Left)" : " (Right)");

        tabbedComponent->addTab (label, tabColour, tab->viewport.get(), false);
        channelTabs.add (tab);
    }

    resized();
}

void ChannelTabsComponent::resized()
{
    auto area = getLocalBounds();

    // Shared output settings at bottom
    static constexpr int rowH = 24;
    static constexpr int gap = 4;
    static constexpr int indent = 24;

    auto sharedArea = area.removeFromBottom (rowH); // writeXml
    writeXmlToggle.setBounds (sharedArea);

    area.removeFromBottom (gap);

    if (suffixEditor.isVisible())
    {
        auto suffixRow = area.removeFromBottom (rowH);
        suffixRow.removeFromLeft (indent);
        suffixLabel.setBounds (suffixRow.removeFromLeft (50));
        suffixEditor.setBounds (suffixRow.removeFromLeft (150));
        area.removeFromBottom (gap);
    }

    avoidOverwriteToggle.setBounds (area.removeFromBottom (rowH));
    area.removeFromBottom (gap);

    // Tabs fill remaining space
    if (tabbedComponent != nullptr)
    {
        tabbedComponent->setBounds (area);

        // Size each tab's ManualOptionsComponent
        for (auto* tab : channelTabs)
        {
            if (tab->viewport != nullptr && tab->options != nullptr)
            {
                int vpWidth = tab->viewport->getMaximumVisibleWidth();
                tab->options->setSize (vpWidth, tab->options->getRequiredHeight());
            }
        }
    }
}

juce::Array<ChannelTabsComponent::ChannelSettings> ChannelTabsComponent::getEnabledChannelSettings() const
{
    juce::Array<ChannelSettings> result;
    for (int i = 0; i < channelTabs.size(); ++i)
    {
        auto* opts = channelTabs[i]->options.get();
        if (opts != nullptr && opts->hasAnyEnabled())
            result.add ({ i + 1, opts->getSettings() });
    }
    return result;
}

int ChannelTabsComponent::getEnabledChannelCount() const
{
    int count = 0;
    for (auto* tab : channelTabs)
        if (tab->options != nullptr && tab->options->hasAnyEnabled())
            ++count;
    return count;
}

bool ChannelTabsComponent::hasAnyChannelEnabled() const
{
    return getEnabledChannelCount() > 0;
}

ManualOptionsComponent* ChannelTabsComponent::getChannelOptions (int channelIndex)
{
    int idx = channelIndex - 1; // 1-based to 0-based
    if (idx >= 0 && idx < channelTabs.size())
        return channelTabs[idx]->options.get();
    return nullptr;
}

ManualOptionsComponent* ChannelTabsComponent::getActiveTabOptions()
{
    if (tabbedComponent == nullptr)
        return nullptr;

    int activeIdx = tabbedComponent->getCurrentTabIndex();
    if (activeIdx >= 0 && activeIdx < channelTabs.size())
        return channelTabs[activeIdx]->options.get();
    return nullptr;
}

void ChannelTabsComponent::notifyChange()
{
    if (onChange)
        onChange();
}
