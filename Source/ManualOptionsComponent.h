#pragma once

#include <juce_gui_basics/juce_gui_basics.h>

class ManualOptionsComponent : public juce::Component
{
public:
    ManualOptionsComponent();

    void resized() override;

    juce::var getSettings() const;
    bool hasAnyEnabled() const;

private:
    void populateDbCombo (juce::ComboBox& combo, bool offByDefault);
    void populateStrengthCombo (juce::ComboBox& combo);
    void populateCompressorCombo (juce::ComboBox& combo);
    void populateMusicGainCombo (juce::ComboBox& combo);
    void updateDependentVisibility();

    static constexpr int rowH = 24;
    static constexpr int gap = 4;
    static constexpr int indent = 24;

    juce::Label separatorLabel { {}, "-- OR configure manually --" };

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

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR (ManualOptionsComponent)
};
