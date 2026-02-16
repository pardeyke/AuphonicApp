#pragma once

#include <juce_gui_basics/juce_gui_basics.h>

class FileDropComponent : public juce::Component,
                          public juce::FileDragAndDropTarget
{
public:
    FileDropComponent();

    void paint (juce::Graphics& g) override;
    void resized() override;

    bool isInterestedInFileDrag (const juce::StringArray& files) override;
    void filesDropped (const juce::StringArray& files, int x, int y) override;
    void fileDragEnter (const juce::StringArray& files, int x, int y) override;
    void fileDragExit (const juce::StringArray& files) override;

    void setFile (const juce::File& file);
    juce::File getFile() const { return currentFile; }

    std::function<void (const juce::File&)> onFileSelected;

private:
    juce::File currentFile;
    juce::TextButton chooseFileButton { "Choose File" };
    juce::Label fileLabel;
    bool isDraggingOver = false;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR (FileDropComponent)
};
