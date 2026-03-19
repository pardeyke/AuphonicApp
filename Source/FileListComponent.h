#pragma once

#include <juce_gui_basics/juce_gui_basics.h>

class FileListComponent : public juce::Component,
                          public juce::FileDragAndDropTarget
{
public:
    FileListComponent();

    void paint (juce::Graphics& g) override;
    void resized() override;

    bool isInterestedInFileDrag (const juce::StringArray& files) override;
    void filesDropped (const juce::StringArray& files, int x, int y) override;
    void fileDragEnter (const juce::StringArray& files, int x, int y) override;
    void fileDragExit (const juce::StringArray& files) override;

    void addFiles (const juce::Array<juce::File>& files);
    void removeFile (int index);
    void clear();
    juce::Array<juce::File> getFiles() const;
    bool hasFiles() const { return ! fileEntries.isEmpty(); }
    int getFileCount() const { return fileEntries.size(); }

    void setFileStatus (int index, const juce::String& status);
    void setEnabled (bool shouldBeEnabled);

    int getDesiredHeight() const;

    std::function<void()> onFilesChanged;

private:
    struct FileEntry {
        juce::File file;
        juce::String status;
    };

    class FileRowComponent : public juce::Component
    {
    public:
        FileRowComponent (FileListComponent& owner, int index);
        void paint (juce::Graphics& g) override;
        void resized() override;
        void update (const juce::String& filename, const juce::String& status, bool canRemove);

    private:
        FileListComponent& owner;
        int index;
        juce::String filename;
        juce::String status;
        juce::TextButton removeButton { "x" };

        JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR (FileRowComponent)
    };

    void rebuildRows();
    void notifyFilesChanged();

    juce::Array<FileEntry> fileEntries;
    juce::TextButton addFilesButton { "Add Files" };
    juce::TextButton clearButton { "Clear" };
    juce::Viewport viewport;
    juce::Component rowContainer;
    juce::OwnedArray<FileRowComponent> rowComponents;
    bool isDraggingOver = false;
    bool isEnabled = true;

    static constexpr int rowHeight = 24;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR (FileListComponent)
};
