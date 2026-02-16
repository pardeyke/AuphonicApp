#include "FileDropComponent.h"

FileDropComponent::FileDropComponent()
{
    addAndMakeVisible (chooseFileButton);

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
    auto cornerSize = 8.0f;

    auto accent = findColour (juce::TextButton::buttonOnColourId);
    auto textCol = findColour (juce::Label::textColourId);

    g.setColour (isDraggingOver ? accent.withAlpha (0.15f)
                                : textCol.withAlpha (0.05f));
    g.fillRoundedRectangle (bounds, cornerSize);

    g.setColour (isDraggingOver ? accent : textCol.withAlpha (0.3f));
    g.drawRoundedRectangle (bounds, cornerSize, 1.0f);

    auto textArea = bounds.reduced (10, 0).withTrimmedRight (116);

    if (currentFile == juce::File())
    {
        g.setColour (textCol.withAlpha (0.5f));
        g.setFont (juce::FontOptions (14.0f));
        g.drawText ("Drop audio file here", textArea.toNearestInt(),
                     juce::Justification::centredLeft);
    }
    else
    {
        g.setColour (textCol.withAlpha (0.8f));
        g.setFont (juce::FontOptions (12.0f));
        g.drawFittedText (currentFile.getFullPathName(), textArea.toNearestInt(),
                          juce::Justification::centredLeft, 3);
    }
}

void FileDropComponent::resized()
{
    auto area = getLocalBounds().reduced (8);
    chooseFileButton.setBounds (area.removeFromRight (100).withSizeKeepingCentre (100, 26));
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
    repaint();

    if (onFileSelected)
        onFileSelected (file);
}
