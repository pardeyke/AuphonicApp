#include "FileDropComponent.h"

FileDropComponent::FileDropComponent()
{
    addAndMakeVisible (chooseFileButton);
    addAndMakeVisible (fileLabel);

    fileLabel.setFont (juce::FontOptions (13.0f));
    fileLabel.setColour (juce::Label::textColourId, juce::Colours::white.withAlpha (0.8f));

    chooseFileButton.onClick = [this]
    {
        auto chooser = std::make_shared<juce::FileChooser> (
            "Select an audio file",
            juce::File::getSpecialLocation (juce::File::userHomeDirectory),
            "*.wav;*.mp3;*.flac;*.aac;*.ogg;*.m4a;*.aif;*.aiff");

        chooser->launchAsync (juce::FileBrowserComponent::openMode | juce::FileBrowserComponent::canSelectFiles,
            [this, chooser] (const juce::FileChooser& fc)
            {
                if (auto result = fc.getResult(); result.existsAsFile())
                    setFile (result);
            });
    };
}

void FileDropComponent::paint (juce::Graphics& g)
{
    auto bounds = getLocalBounds().toFloat().reduced (1.0f);

    g.setColour (isDraggingOver ? juce::Colours::lightblue.withAlpha (0.15f)
                                : juce::Colours::white.withAlpha (0.05f));
    g.fillRoundedRectangle (bounds, 6.0f);

    g.setColour (isDraggingOver ? juce::Colours::lightblue : juce::Colours::white.withAlpha (0.3f));
    float dashLengths[] = { 6.0f, 4.0f };
    g.drawDashedLine (juce::Line<float> (bounds.getTopLeft(), bounds.getTopRight()), dashLengths, 2, 1.0f);
    g.drawDashedLine (juce::Line<float> (bounds.getTopRight(), bounds.getBottomRight()), dashLengths, 2, 1.0f);
    g.drawDashedLine (juce::Line<float> (bounds.getBottomRight(), bounds.getBottomLeft()), dashLengths, 2, 1.0f);
    g.drawDashedLine (juce::Line<float> (bounds.getBottomLeft(), bounds.getTopLeft()), dashLengths, 2, 1.0f);

    if (currentFile == juce::File())
    {
        g.setColour (juce::Colours::white.withAlpha (0.5f));
        g.setFont (juce::FontOptions (14.0f));
        g.drawText ("Drop audio file here", bounds.reduced (10, 0).withTrimmedRight (120),
                     juce::Justification::centredLeft);
    }
}

void FileDropComponent::resized()
{
    auto area = getLocalBounds().reduced (8);
    chooseFileButton.setBounds (area.removeFromRight (100).withSizeKeepingCentre (100, 26));
    area.removeFromRight (8);

    if (currentFile != juce::File())
        fileLabel.setBounds (area);
}

bool FileDropComponent::isInterestedInFileDrag (const juce::StringArray& files)
{
    for (auto& f : files)
        if (juce::File (f).existsAsFile())
            return true;
    return false;
}

void FileDropComponent::filesDropped (const juce::StringArray& files, int, int)
{
    isDraggingOver = false;
    for (auto& f : files)
    {
        juce::File file (f);
        if (file.existsAsFile())
        {
            setFile (file);
            break;
        }
    }
    repaint();
}

void FileDropComponent::fileDragEnter (const juce::StringArray&, int, int)
{
    isDraggingOver = true;
    repaint();
}

void FileDropComponent::fileDragExit (const juce::StringArray&)
{
    isDraggingOver = false;
    repaint();
}

void FileDropComponent::setFile (const juce::File& file)
{
    currentFile = file;
    fileLabel.setText ("File: " + file.getFullPathName(), juce::dontSendNotification);
    resized();
    repaint();

    if (onFileSelected)
        onFileSelected (file);
}
