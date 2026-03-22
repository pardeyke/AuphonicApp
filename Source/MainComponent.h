#pragma once

#include <juce_gui_basics/juce_gui_basics.h>
#include <juce_gui_extra/juce_gui_extra.h>
#include "SettingsManager.h"
#include "AuphonicApiClient.h"
#include "BatchWorkflow.h"
#include "FileListComponent.h"
#include "PresetListComponent.h"
#include "ManualOptionsComponent.h"
#include "StatusComponent.h"
#include "CreditsComponent.h"
#include "AudioPlayerComponent.h"
#include "PreviewDurationComponent.h"
#include "ChannelTabsComponent.h"

class MainComponent : public juce::Component,
                      public BatchWorkflow::Listener
{
public:
    explicit MainComponent (const juce::File& initialFile = {});
    ~MainComponent() override;

    void paint (juce::Graphics&) override;
    void resized() override;
    bool keyPressed (const juce::KeyPress& key) override;

    void setFile (const juce::File& file);

    // BatchWorkflow::Listener
    void batchFileStatusChanged (int index, const juce::String& status) override;
    void batchProgressChanged (int completed, int total, const juce::String& overallStatus) override;
    void batchCompleted (const juce::Array<BatchWorkflow::FileResult>& results) override;

private:
    void onSettingsClicked();
    void onProcessClicked();
    void onCancelClicked();
    void onSavePresetClicked();
    void connectAndFetchUser();
    void refreshPresets();
    void refreshCredits();
    void updateButtonStates();
    void saveCurrentConfig();
    void restoreLastConfig();
    void setProcessingMode (bool perChannel);

    SettingsManager settingsManager;
    std::unique_ptr<AuphonicApiClient> apiClient;
    std::unique_ptr<BatchWorkflow> batchWorkflow;

    juce::TextButton settingsButton { juce::String::charToString (0x2699) + juce::String::charToString (0xFE0F) };

    FileListComponent fileListComponent;
    AudioPlayerComponent audioPlayerComponent;
    PreviewDurationComponent previewDurationComponent;
    CreditsComponent creditsComponent;
    PresetListComponent presetListComponent;
    juce::TextButton savePresetButton { "Save Preset" };
    ManualOptionsComponent manualOptionsComponent;
    juce::Viewport optionsViewport;
    StatusComponent statusComponent;

    ChannelTabsComponent channelTabsComponent;
    juce::TextButton wholeFileButton { "Whole File" };
    juce::TextButton perChannelButton { "Per Channel" };
    bool perChannelMode = false;

    juce::Label channelWarningLabel;
    juce::TextButton processButton { "Process" };
    juce::TextButton cancelButton { "Cancel" };

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR (MainComponent)
};
