#pragma once

#include <juce_gui_basics/juce_gui_basics.h>
#include <juce_gui_extra/juce_gui_extra.h>
#include "SettingsManager.h"
#include "AuphonicApiClient.h"
#include "ProcessingWorkflow.h"
#include "FileDropComponent.h"
#include "PresetListComponent.h"
#include "ManualOptionsComponent.h"
#include "StatusComponent.h"
#include "CreditsComponent.h"
#include "AudioPlayerComponent.h"
#include "PreviewDurationComponent.h"

class MainComponent : public juce::Component,
                      public ProcessingWorkflow::Listener
{
public:
    explicit MainComponent (const juce::File& initialFile = {});
    ~MainComponent() override;

    void paint (juce::Graphics&) override;
    void resized() override;
    bool keyPressed (const juce::KeyPress& key) override;

    void setFile (const juce::File& file);

    // ProcessingWorkflow::Listener
    void workflowStateChanged (ProcessingWorkflow::State newState) override;
    void workflowProgressChanged (double progress, const juce::String& statusText) override;
    void workflowCompleted() override;
    void workflowFailed (const juce::String& errorMessage) override;

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

    SettingsManager settingsManager;
    std::unique_ptr<AuphonicApiClient> apiClient;
    std::unique_ptr<ProcessingWorkflow> workflow;

    juce::TextButton settingsButton { juce::String::charToString (0x2699) + juce::String::charToString (0xFE0F) };

    FileDropComponent fileDropComponent;
    AudioPlayerComponent audioPlayerComponent;
    PreviewDurationComponent previewDurationComponent;
    CreditsComponent creditsComponent;
    PresetListComponent presetListComponent;
    juce::TextButton savePresetButton { "Save Preset" };
    ManualOptionsComponent manualOptionsComponent;
    juce::Viewport optionsViewport;
    StatusComponent statusComponent;

    juce::TextButton processButton { "Process" };
    juce::TextButton cancelButton { "Cancel" };

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR (MainComponent)
};
