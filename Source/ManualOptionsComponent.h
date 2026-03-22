#pragma once

#include <juce_gui_basics/juce_gui_basics.h>

class ManualOptionsComponent : public juce::Component
{
public:
    ManualOptionsComponent();

    void resized() override;

    int getRequiredHeight() const;

    juce::var getSettings() const;
    bool hasAnyEnabled() const;

    juce::var getWidgetState() const;
    void applyWidgetState (const juce::var& state);

    void applyApiSettings (const juce::var& algorithms);

    void setFileChannelCount (int numChannels);
    int getSelectedChannel() const;

    bool shouldAvoidOverwrite() const  { return avoidOverwriteToggle.getToggleState(); }
    juce::String getOutputSuffix() const { return suffixEditor.getText(); }
    bool shouldWriteSettingsXml() const { return writeXmlToggle.getToggleState(); }
    bool shouldKeepTimecode() const    { return keepTimecodeToggle.getToggleState(); }

    std::function<void()> onChange;

private:
    void notifyChange();
    bool suppressCallbacks = false;
    void populateDbCombo (juce::ComboBox& combo, bool offByDefault);
    void populateStrengthCombo (juce::ComboBox& combo);
    void populateCompressorCombo (juce::ComboBox& combo);
    void populateMusicGainCombo (juce::ComboBox& combo);
    void populateBitrateCombo();
    void updateDependentVisibility();

    static constexpr int rowH = 24;
    static constexpr int gap = 4;
    static constexpr int indent = 24;

    juce::Label separatorLabel { {}, "Settings:" };

    // --- Channel Selector ---
    juce::Label channelLabel { {}, "Channel:" };
    juce::ComboBox channelCombo;
    int currentFileChannels = 0;

    // --- Adaptive Leveler ---
    juce::ToggleButton levelerToggle { "Adaptive Leveler" };

    juce::Label strengthLabel { {}, "Strength:" };
    juce::ComboBox strengthCombo;
    juce::Label compressorLabel { {}, "Compressor:" };
    juce::ComboBox compressorCombo;

    // Separate Music/Speech mode
    juce::ToggleButton separateMsToggle { "Separate Music/Speech" };
    juce::Label classifierLabel { {}, "Classifier:" };
    juce::ComboBox classifierCombo;
    juce::Label speechStrengthLabel { {}, "Speech Strength:" };
    juce::ComboBox speechStrengthCombo;
    juce::Label speechCompressorLabel { {}, "Compressor:" };
    juce::ComboBox speechCompressorCombo;
    juce::Label musicStrengthLabel { {}, "Music Strength:" };
    juce::ComboBox musicStrengthCombo;
    juce::Label musicCompressorLabel { {}, "Compressor:" };
    juce::ComboBox musicCompressorCombo;
    juce::Label musicGainLabel { {}, "Music Gain:" };
    juce::ComboBox musicGainCombo;

    // Broadcast mode
    juce::ToggleButton broadcastToggle { "Broadcast Mode" };
    juce::Label maxLraLabel { {}, "Max LRA:" };
    juce::ComboBox maxLraCombo;
    juce::Label maxSLabel { {}, "Max Short-term:" };
    juce::ComboBox maxSCombo;
    juce::Label maxMLabel { {}, "Max Momentary:" };
    juce::ComboBox maxMCombo;

    // --- Noise Reduction ---
    juce::ToggleButton noiseToggle { "Noise Reduction" };

    juce::Label methodLabel { {}, "Method:" };
    juce::ComboBox methodCombo;

    juce::Label noiseAmountLabel { {}, "Remove Noise:" };
    juce::ComboBox noiseAmountCombo;

    juce::Label reverbAmountLabel { {}, "Remove Reverb:" };
    juce::ComboBox reverbAmountCombo;

    juce::Label breathAmountLabel { {}, "Remove Breaths:" };
    juce::ComboBox breathAmountCombo;

    // --- Filtering ---
    juce::ToggleButton filterToggle { "Filtering" };
    juce::Label filterMethodLabel { {}, "Method:" };
    juce::ComboBox filterMethodCombo;

    juce::ToggleButton loudnessToggle { "Loudness Normalization" };
    juce::Label loudnessTargetLabel { {}, "Target:" };
    juce::ComboBox loudnessTargetCombo;

    // --- Output Format ---
    juce::Label outputFormatLabel { {}, "Output Format:" };
    juce::ComboBox outputFormatCombo;
    juce::Label bitrateLabel { {}, "Bitrate:" };
    juce::ComboBox bitrateCombo;

    // --- Output Behavior ---
    juce::ToggleButton avoidOverwriteToggle { "Create a new file (don't overwrite)" };
    juce::Label suffixLabel { {}, "Suffix:" };
    juce::TextEditor suffixEditor;
    juce::ToggleButton writeXmlToggle       { "Write settings JSON alongside output" };
    juce::ToggleButton keepTimecodeToggle   { "Keep timecode (iXML)" };

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR (ManualOptionsComponent)
};
