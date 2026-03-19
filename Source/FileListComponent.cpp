#include "FileListComponent.h"

FileListComponent::FileListComponent()
{
    addAndMakeVisible (addFilesButton);
    addAndMakeVisible (clearButton);
    addAndMakeVisible (viewport);
    viewport.setViewedComponent (&rowContainer, false);
    viewport.setScrollBarsShown (true, false);

    addFilesButton.onClick = [this]
    {
        if (! isEnabled) return;

        auto chooser = std::make_shared<juce::FileChooser> (
            "Select audio files",
            juce::File::getSpecialLocation (juce::File::userHomeDirectory),
            "*.wav;*.mp3;*.flac;*.aac;*.ogg;*.m4a;*.aif;*.aiff");

        chooser->launchAsync (juce::FileBrowserComponent::openMode
                            | juce::FileBrowserComponent::canSelectFiles
                            | juce::FileBrowserComponent::canSelectMultipleItems,
            [this, chooser] (const juce::FileChooser& fc)
            {
                auto results = fc.getResults();
                if (! results.isEmpty())
                    addFiles (results);
            });
    };

    clearButton.onClick = [this]
    {
        if (! isEnabled) return;
        clear();
    };
}

void FileListComponent::paint (juce::Graphics& g)
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

    if (fileEntries.isEmpty())
    {
        g.setColour (textCol.withAlpha (0.5f));
        g.setFont (juce::FontOptions (14.0f));
        g.drawText ("Drop audio files here", getLocalBounds(),
                     juce::Justification::centred);
    }
}

void FileListComponent::resized()
{
    auto area = getLocalBounds().reduced (8);

    auto buttonRow = area.removeFromTop (26);
    clearButton.setBounds (buttonRow.removeFromRight (60));
    buttonRow.removeFromRight (6);
    addFilesButton.setBounds (buttonRow.removeFromRight (80));

    area.removeFromTop (4);
    viewport.setBounds (area);

    int containerHeight = juce::jmax (area.getHeight(), fileEntries.size() * rowHeight);
    int containerWidth = viewport.getMaximumVisibleWidth();
    rowContainer.setSize (containerWidth, containerHeight);

    for (int i = 0; i < rowComponents.size(); ++i)
        rowComponents[i]->setBounds (0, i * rowHeight, containerWidth, rowHeight);
}

bool FileListComponent::isInterestedInFileDrag (const juce::StringArray& files)
{
    if (! isEnabled) return false;
    for (auto& f : files)
        if (juce::File (f).existsAsFile())
            return true;
    return false;
}

void FileListComponent::filesDropped (const juce::StringArray& files, int, int)
{
    isDraggingOver = false;

    juce::Array<juce::File> toAdd;
    for (auto& f : files)
    {
        juce::File file (f);
        if (file.existsAsFile())
            toAdd.add (file);
    }

    if (! toAdd.isEmpty())
        addFiles (toAdd);

    repaint();
}

void FileListComponent::fileDragEnter (const juce::StringArray&, int, int)
{
    if (! isEnabled) return;
    isDraggingOver = true;
    repaint();
}

void FileListComponent::fileDragExit (const juce::StringArray&)
{
    isDraggingOver = false;
    repaint();
}

void FileListComponent::addFiles (const juce::Array<juce::File>& files)
{
    bool anyAdded = false;
    for (auto& file : files)
    {
        // Deduplicate
        bool exists = false;
        for (auto& entry : fileEntries)
        {
            if (entry.file == file)
            {
                exists = true;
                break;
            }
        }

        if (! exists)
        {
            fileEntries.add ({ file, {} });
            anyAdded = true;
        }
    }

    if (anyAdded)
    {
        rebuildRows();
        notifyFilesChanged();
    }
}

void FileListComponent::removeFile (int index)
{
    if (index >= 0 && index < fileEntries.size())
    {
        fileEntries.remove (index);
        rebuildRows();
        notifyFilesChanged();
    }
}

void FileListComponent::clear()
{
    if (fileEntries.isEmpty()) return;

    fileEntries.clear();
    rebuildRows();
    notifyFilesChanged();
}

juce::Array<juce::File> FileListComponent::getFiles() const
{
    juce::Array<juce::File> files;
    for (auto& entry : fileEntries)
        files.add (entry.file);
    return files;
}

void FileListComponent::setFileStatus (int index, const juce::String& status)
{
    if (index >= 0 && index < fileEntries.size())
    {
        fileEntries.getReference (index).status = status;
        if (index < rowComponents.size())
            rowComponents[index]->update (fileEntries[index].file.getFileName(),
                                          status, isEnabled);
    }
}

void FileListComponent::setEnabled (bool shouldBeEnabled)
{
    isEnabled = shouldBeEnabled;
    addFilesButton.setEnabled (shouldBeEnabled);
    clearButton.setEnabled (shouldBeEnabled);

    for (int i = 0; i < rowComponents.size(); ++i)
        rowComponents[i]->update (fileEntries[i].file.getFileName(),
                                  fileEntries[i].status, shouldBeEnabled);
}

int FileListComponent::getDesiredHeight() const
{
    // Button row (26) + padding (4) + file rows, clamped to min 78, max 200
    int contentHeight = 30 + fileEntries.size() * rowHeight;
    return juce::jlimit (78, 200, contentHeight);
}

void FileListComponent::rebuildRows()
{
    rowComponents.clear();

    for (int i = 0; i < fileEntries.size(); ++i)
    {
        auto* row = new FileRowComponent (*this, i);
        row->update (fileEntries[i].file.getFileName(), fileEntries[i].status, isEnabled);
        rowContainer.addAndMakeVisible (row);
        rowComponents.add (row);
    }

    resized();
    repaint();

    // Tell parent to relayout so our dynamic height takes effect
    if (auto* parent = getParentComponent())
        parent->resized();
}

void FileListComponent::notifyFilesChanged()
{
    if (onFilesChanged)
        onFilesChanged();
}

// --- FileRowComponent ---

FileListComponent::FileRowComponent::FileRowComponent (FileListComponent& o, int idx)
    : owner (o), index (idx)
{
    addAndMakeVisible (removeButton);
    removeButton.onClick = [this] { owner.removeFile (index); };
}

void FileListComponent::FileRowComponent::paint (juce::Graphics& g)
{
    auto textCol = findColour (juce::Label::textColourId);
    auto area = getLocalBounds().reduced (2, 1);

    // Filename
    g.setColour (textCol.withAlpha (0.85f));
    g.setFont (juce::FontOptions (12.0f));

    auto nameArea = area.removeFromLeft (area.getWidth() - 140);
    g.drawFittedText (filename, nameArea, juce::Justification::centredLeft, 1);

    // Status
    if (status.isNotEmpty())
    {
        auto statusArea = area.removeFromLeft (area.getWidth() - 24);
        g.setColour (textCol.withAlpha (0.6f));
        g.setFont (juce::FontOptions (11.0f));
        g.drawFittedText (status, statusArea, juce::Justification::centredRight, 1);
    }
}

void FileListComponent::FileRowComponent::resized()
{
    removeButton.setBounds (getLocalBounds().removeFromRight (22).reduced (2));
}

void FileListComponent::FileRowComponent::update (const juce::String& name,
                                                    const juce::String& stat,
                                                    bool canRemove)
{
    filename = name;
    status = stat;
    removeButton.setVisible (canRemove);
    repaint();
}
