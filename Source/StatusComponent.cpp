#include "StatusComponent.h"

StatusComponent::StatusComponent()
    : progressBar (progress)
{
    addAndMakeVisible (statusLabel);
    addAndMakeVisible (progressBar);
    progressBar.setVisible (false);

    addChildComponent (showInFinderButton);
    showInFinderButton.onClick = [this] { outputFile.revealToUser(); };
}

void StatusComponent::resized()
{
    auto area = getLocalBounds();
    auto statusRow = area.removeFromTop (22);

    if (showInFinderButton.isVisible())
    {
        showInFinderButton.setBounds (statusRow.removeFromRight (110));
        statusRow.removeFromRight (4);
    }

    statusLabel.setBounds (statusRow);
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

void StatusComponent::setOutputFile (const juce::File& file)
{
    outputFile = file;
    showInFinderButton.setVisible (file.existsAsFile());
    resized();
}

void StatusComponent::reset()
{
    setStatus ("Ready");
    setProgress (-1.0);
    setOutputFile ({});
}
