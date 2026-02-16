#include "StatusComponent.h"

StatusComponent::StatusComponent()
    : progressBar (progress)
{
    addAndMakeVisible (statusLabel);
    addAndMakeVisible (progressBar);
    progressBar.setVisible (false);
}

void StatusComponent::resized()
{
    auto area = getLocalBounds();
    statusLabel.setBounds (area.removeFromTop (22));
    area.removeFromTop (4);
    progressBar.setBounds (area.removeFromTop (20));
}

void StatusComponent::setStatus (const juce::String& text)
{
    statusLabel.setText ("Status: " + text, juce::dontSendNotification);
}

void StatusComponent::setProgress (double value)
{
    progress = value;
    progressBar.setVisible (value >= 0.0);
    repaint();
}

void StatusComponent::reset()
{
    setStatus ("Ready");
    setProgress (-1.0);
}
