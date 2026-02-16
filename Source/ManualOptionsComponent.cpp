#include "ManualOptionsComponent.h"

ManualOptionsComponent::ManualOptionsComponent()
{
    addAndMakeVisible (separatorLabel);
    separatorLabel.setFont (juce::FontOptions (12.0f));
    separatorLabel.setColour (juce::Label::textColourId, juce::Colours::grey);
    separatorLabel.setJustificationType (juce::Justification::centred);

    // ── Adaptive Leveler ──
    addAndMakeVisible (levelerToggle);
    levelerToggle.setToggleState (true, juce::dontSendNotification);
    levelerToggle.onClick = [this] { updateDependentVisibility(); };

    addAndMakeVisible (strengthLabel);
    addAndMakeVisible (strengthCombo);
    populateStrengthCombo (strengthCombo);

    addAndMakeVisible (compressorLabel);
    addAndMakeVisible (compressorCombo);
    populateCompressorCombo (compressorCombo);

    // Separate Music/Speech
    addAndMakeVisible (separateMsToggle);
    separateMsToggle.onClick = [this] { updateDependentVisibility(); };

    addAndMakeVisible (classifierLabel);
    addAndMakeVisible (classifierCombo);
    classifierCombo.addItem ("On", 1);
    classifierCombo.addItem ("Speech", 2);
    classifierCombo.addItem ("Music", 3);
    classifierCombo.setSelectedId (1, juce::dontSendNotification);

    addAndMakeVisible (speechStrengthLabel);
    addAndMakeVisible (speechStrengthCombo);
    populateStrengthCombo (speechStrengthCombo);

    addAndMakeVisible (speechCompressorLabel);
    addAndMakeVisible (speechCompressorCombo);
    populateCompressorCombo (speechCompressorCombo);

    addAndMakeVisible (musicStrengthLabel);
    addAndMakeVisible (musicStrengthCombo);
    populateStrengthCombo (musicStrengthCombo);

    addAndMakeVisible (musicCompressorLabel);
    addAndMakeVisible (musicCompressorCombo);
    populateCompressorCombo (musicCompressorCombo);

    addAndMakeVisible (musicGainLabel);
    addAndMakeVisible (musicGainCombo);
    populateMusicGainCombo (musicGainCombo);

    // Broadcast mode
    addAndMakeVisible (broadcastToggle);
    broadcastToggle.onClick = [this] { updateDependentVisibility(); };

    addAndMakeVisible (maxLraLabel);
    addAndMakeVisible (maxLraCombo);
    maxLraCombo.addItem ("Auto", 1);
    for (int v = 3; v <= 20; ++v)
        maxLraCombo.addItem (juce::String (v) + " LU", v + 10);
    maxLraCombo.setSelectedId (1, juce::dontSendNotification);

    addAndMakeVisible (maxSLabel);
    addAndMakeVisible (maxSCombo);
    maxSCombo.addItem ("Auto", 1);
    for (int v = 3; v <= 12; ++v)
        maxSCombo.addItem (juce::String (v) + " LU", v + 10);
    maxSCombo.setSelectedId (1, juce::dontSendNotification);

    addAndMakeVisible (maxMLabel);
    addAndMakeVisible (maxMCombo);
    maxMCombo.addItem ("Auto", 1);
    for (int v = 8; v <= 20; ++v)
        maxMCombo.addItem (juce::String (v) + " LU", v + 10);
    maxMCombo.setSelectedId (1, juce::dontSendNotification);

    // ── Noise Reduction ──
    addAndMakeVisible (noiseToggle);
    noiseToggle.setToggleState (true, juce::dontSendNotification);
    noiseToggle.onClick = [this] { updateDependentVisibility(); };

    addAndMakeVisible (methodLabel);
    addAndMakeVisible (methodCombo);
    methodCombo.addItem ("Classic", 1);
    methodCombo.addItem ("Dynamic", 2);
    methodCombo.addItem ("Speech Isolation", 3);
    methodCombo.addItem ("Static", 4);
    methodCombo.setSelectedId (1, juce::dontSendNotification);
    methodCombo.onChange = [this] { updateDependentVisibility(); };

    addAndMakeVisible (noiseAmountLabel);
    addAndMakeVisible (noiseAmountCombo);
    populateDbCombo (noiseAmountCombo, false);

    addAndMakeVisible (reverbAmountLabel);
    addAndMakeVisible (reverbAmountCombo);
    populateDbCombo (reverbAmountCombo, false);

    addAndMakeVisible (breathAmountLabel);
    addAndMakeVisible (breathAmountCombo);
    populateDbCombo (breathAmountCombo, true);

    // ── Filtering ──
    addAndMakeVisible (filterToggle);
    filterToggle.setToggleState (true, juce::dontSendNotification);
    filterToggle.onClick = [this] { updateDependentVisibility(); };

    addAndMakeVisible (filterMethodLabel);
    addAndMakeVisible (filterMethodCombo);
    filterMethodCombo.addItem ("High-Pass Filter", 1);
    filterMethodCombo.addItem ("Auto EQ", 2);
    filterMethodCombo.addItem ("Bandwidth Extension", 3);
    filterMethodCombo.setSelectedId (1, juce::dontSendNotification);

    // ── Loudness ──
    addAndMakeVisible (loudnessToggle);
    addAndMakeVisible (loudnessTargetLabel);
    addAndMakeVisible (loudnessTargetCombo);
    loudnessTargetCombo.addItem ("-16 LUFS", 1);
    loudnessTargetCombo.addItem ("-23 LUFS", 2);
    loudnessTargetCombo.addItem ("-24 LUFS", 3);
    loudnessTargetCombo.addItem ("-14 LUFS", 4);
    loudnessTargetCombo.setSelectedId (1, juce::dontSendNotification);

    updateDependentVisibility();
}

// ── Combo population helpers ──

void ManualOptionsComponent::populateStrengthCombo (juce::ComboBox& combo)
{
    // 100% (id 1) down to 0% (id 11) in steps of 10
    for (int pct = 100; pct >= 0; pct -= 10)
        combo.addItem (juce::String (pct) + "%", 101 - pct); // id 1..11

    combo.setSelectedId (1, juce::dontSendNotification); // 100%
}

void ManualOptionsComponent::populateCompressorCombo (juce::ComboBox& combo)
{
    combo.addItem ("Auto", 1);
    combo.addItem ("Soft", 2);
    combo.addItem ("Medium", 3);
    combo.addItem ("Hard", 4);
    combo.addItem ("Off", 5);
    combo.setSelectedId (1, juce::dontSendNotification);
}

void ManualOptionsComponent::populateMusicGainCombo (juce::ComboBox& combo)
{
    // -6 dB to +6 dB  (itemId 1..13)
    for (int db = -6; db <= 6; ++db)
    {
        juce::String label = (db > 0 ? "+" : "") + juce::String (db) + " dB";
        combo.addItem (label, db + 7); // id 1..13
    }
    combo.setSelectedId (7, juce::dontSendNotification); // 0 dB
}

void ManualOptionsComponent::populateDbCombo (juce::ComboBox& combo, bool offByDefault)
{
    combo.addItem ("Off", 1);
    combo.addItem ("100 dB (full)", 2);
    combo.addItem ("3 dB", 3);
    combo.addItem ("6 dB (low)", 4);
    combo.addItem ("9 dB", 5);
    combo.addItem ("12 dB (medium)", 6);
    combo.addItem ("15 dB", 7);
    combo.addItem ("18 dB", 8);
    combo.addItem ("24 dB (high)", 9);
    combo.addItem ("30 dB", 10);
    combo.addItem ("36 dB", 11);

    combo.setSelectedId (offByDefault ? 1 : 2, juce::dontSendNotification);
}

// ── Helpers to extract API values from combos ──

static int dbComboToApiValue (const juce::ComboBox& combo)
{
    static const int values[] = { -1, 0, 3, 6, 9, 12, 15, 18, 24, 30, 36 };
    int idx = combo.getSelectedId() - 1;
    if (idx >= 0 && idx < 11)
        return values[idx];
    return 0;
}

static int strengthComboToApiValue (const juce::ComboBox& combo)
{
    // id 1 = 100%, id 2 = 90%, ... id 11 = 0%
    int id = combo.getSelectedId();
    if (id >= 1 && id <= 11)
        return 100 - (id - 1) * 10;
    return 100;
}

static juce::String compressorComboToApiValue (const juce::ComboBox& combo)
{
    switch (combo.getSelectedId())
    {
        case 1:  return "auto";
        case 2:  return "soft";
        case 3:  return "medium";
        case 4:  return "hard";
        case 5:  return "off";
        default: return "auto";
    }
}

static int musicGainComboToApiValue (const juce::ComboBox& combo)
{
    // id 1 = -6, id 7 = 0, id 13 = +6
    return combo.getSelectedId() - 7;
}

static int luComboToApiValue (const juce::ComboBox& combo)
{
    // id 1 = Auto (0), id v+10 = v LU
    int id = combo.getSelectedId();
    if (id == 1) return 0;
    return id - 10;
}

// ── Visibility ──

void ManualOptionsComponent::updateDependentVisibility()
{
    bool levelerOn = levelerToggle.getToggleState();
    bool separateMs = levelerOn && separateMsToggle.getToggleState();
    bool broadcast  = levelerOn && broadcastToggle.getToggleState();

    // Basic leveler controls: visible when leveler ON and separate mode OFF
    bool showBasic = levelerOn && ! separateMs;
    strengthLabel.setVisible (showBasic);
    strengthCombo.setVisible (showBasic);
    compressorLabel.setVisible (showBasic);
    compressorCombo.setVisible (showBasic);

    // Sub-mode toggles
    separateMsToggle.setVisible (levelerOn);
    broadcastToggle.setVisible (levelerOn);

    // Separate Music/Speech controls
    classifierLabel.setVisible (separateMs);
    classifierCombo.setVisible (separateMs);
    speechStrengthLabel.setVisible (separateMs);
    speechStrengthCombo.setVisible (separateMs);
    speechCompressorLabel.setVisible (separateMs);
    speechCompressorCombo.setVisible (separateMs);
    musicStrengthLabel.setVisible (separateMs);
    musicStrengthCombo.setVisible (separateMs);
    musicCompressorLabel.setVisible (separateMs);
    musicCompressorCombo.setVisible (separateMs);

    // Music gain: visible when either separate or broadcast
    bool showMusicGain = separateMs || broadcast;
    musicGainLabel.setVisible (showMusicGain);
    musicGainCombo.setVisible (showMusicGain);

    // Broadcast controls
    maxLraLabel.setVisible (broadcast);
    maxLraCombo.setVisible (broadcast);
    maxSLabel.setVisible (broadcast);
    maxSCombo.setVisible (broadcast);
    maxMLabel.setVisible (broadcast);
    maxMCombo.setVisible (broadcast);

    // Noise reduction
    bool noiseEnabled = noiseToggle.getToggleState();
    int methodId = methodCombo.getSelectedId();
    bool hasReverb  = noiseEnabled && (methodId == 2 || methodId == 3 || methodId == 4);
    bool hasBreaths = noiseEnabled && (methodId == 2 || methodId == 3);

    methodLabel.setVisible (noiseEnabled);
    methodCombo.setVisible (noiseEnabled);
    noiseAmountLabel.setVisible (noiseEnabled);
    noiseAmountCombo.setVisible (noiseEnabled);
    reverbAmountLabel.setVisible (hasReverb);
    reverbAmountCombo.setVisible (hasReverb);
    breathAmountLabel.setVisible (hasBreaths);
    breathAmountCombo.setVisible (hasBreaths);

    // Filtering
    bool filterEnabled = filterToggle.getToggleState();
    filterMethodLabel.setVisible (filterEnabled);
    filterMethodCombo.setVisible (filterEnabled);

    resized();
    if (auto* parent = getParentComponent())
        parent->resized();
}

// ── Layout ──

void ManualOptionsComponent::resized()
{
    auto area = getLocalBounds();

    separatorLabel.setBounds (area.removeFromTop (rowH));
    area.removeFromTop (gap);

    // ── Leveler ──
    levelerToggle.setBounds (area.removeFromTop (rowH));
    area.removeFromTop (gap);

    if (strengthCombo.isVisible())
    {
        auto row = area.removeFromTop (rowH);
        row.removeFromLeft (indent);
        strengthLabel.setBounds (row.removeFromLeft (70));
        strengthCombo.setBounds (row.removeFromLeft (80));
        row.removeFromLeft (8);
        compressorLabel.setBounds (row.removeFromLeft (80));
        compressorCombo.setBounds (row.removeFromLeft (90));
        area.removeFromTop (gap);
    }

    if (separateMsToggle.isVisible())
    {
        auto row = area.removeFromTop (rowH);
        row.removeFromLeft (indent);
        separateMsToggle.setBounds (row);
        area.removeFromTop (gap);
    }

    if (classifierCombo.isVisible())
    {
        auto row = area.removeFromTop (rowH);
        row.removeFromLeft (indent * 2);
        classifierLabel.setBounds (row.removeFromLeft (70));
        classifierCombo.setBounds (row.removeFromLeft (90));
        area.removeFromTop (gap);

        row = area.removeFromTop (rowH);
        row.removeFromLeft (indent * 2);
        speechStrengthLabel.setBounds (row.removeFromLeft (110));
        speechStrengthCombo.setBounds (row.removeFromLeft (80));
        row.removeFromLeft (8);
        speechCompressorLabel.setBounds (row.removeFromLeft (80));
        speechCompressorCombo.setBounds (row.removeFromLeft (90));
        area.removeFromTop (gap);

        row = area.removeFromTop (rowH);
        row.removeFromLeft (indent * 2);
        musicStrengthLabel.setBounds (row.removeFromLeft (110));
        musicStrengthCombo.setBounds (row.removeFromLeft (80));
        row.removeFromLeft (8);
        musicCompressorLabel.setBounds (row.removeFromLeft (80));
        musicCompressorCombo.setBounds (row.removeFromLeft (90));
        area.removeFromTop (gap);
    }

    if (musicGainCombo.isVisible())
    {
        auto row = area.removeFromTop (rowH);
        row.removeFromLeft (indent * 2);
        musicGainLabel.setBounds (row.removeFromLeft (80));
        musicGainCombo.setBounds (row.removeFromLeft (90));
        area.removeFromTop (gap);
    }

    if (broadcastToggle.isVisible())
    {
        auto row = area.removeFromTop (rowH);
        row.removeFromLeft (indent);
        broadcastToggle.setBounds (row);
        area.removeFromTop (gap);
    }

    if (maxLraCombo.isVisible())
    {
        auto row = area.removeFromTop (rowH);
        row.removeFromLeft (indent * 2);
        maxLraLabel.setBounds (row.removeFromLeft (80));
        maxLraCombo.setBounds (row.removeFromLeft (80));
        area.removeFromTop (gap);

        row = area.removeFromTop (rowH);
        row.removeFromLeft (indent * 2);
        maxSLabel.setBounds (row.removeFromLeft (110));
        maxSCombo.setBounds (row.removeFromLeft (80));
        area.removeFromTop (gap);

        row = area.removeFromTop (rowH);
        row.removeFromLeft (indent * 2);
        maxMLabel.setBounds (row.removeFromLeft (110));
        maxMCombo.setBounds (row.removeFromLeft (80));
        area.removeFromTop (gap);
    }

    // ── Noise Reduction ──
    noiseToggle.setBounds (area.removeFromTop (rowH));
    area.removeFromTop (gap);

    if (methodCombo.isVisible())
    {
        auto row = area.removeFromTop (rowH);
        row.removeFromLeft (indent);
        methodLabel.setBounds (row.removeFromLeft (60));
        methodCombo.setBounds (row.removeFromLeft (200));
        area.removeFromTop (gap);
    }

    if (noiseAmountCombo.isVisible())
    {
        auto row = area.removeFromTop (rowH);
        row.removeFromLeft (indent);
        noiseAmountLabel.setBounds (row.removeFromLeft (100));
        noiseAmountCombo.setBounds (row.removeFromLeft (140));
        area.removeFromTop (gap);
    }

    if (reverbAmountCombo.isVisible())
    {
        auto row = area.removeFromTop (rowH);
        row.removeFromLeft (indent);
        reverbAmountLabel.setBounds (row.removeFromLeft (100));
        reverbAmountCombo.setBounds (row.removeFromLeft (140));
        area.removeFromTop (gap);
    }

    if (breathAmountCombo.isVisible())
    {
        auto row = area.removeFromTop (rowH);
        row.removeFromLeft (indent);
        breathAmountLabel.setBounds (row.removeFromLeft (100));
        breathAmountCombo.setBounds (row.removeFromLeft (140));
        area.removeFromTop (gap);
    }

    // ── Filtering ──
    filterToggle.setBounds (area.removeFromTop (rowH));
    area.removeFromTop (gap);

    if (filterMethodCombo.isVisible())
    {
        auto row = area.removeFromTop (rowH);
        row.removeFromLeft (indent);
        filterMethodLabel.setBounds (row.removeFromLeft (60));
        filterMethodCombo.setBounds (row.removeFromLeft (180));
        area.removeFromTop (gap);
    }

    // ── Loudness ──
    {
        auto row = area.removeFromTop (rowH);
        loudnessToggle.setBounds (row.removeFromLeft (200));
        loudnessTargetLabel.setBounds (row.removeFromLeft (50));
        loudnessTargetCombo.setBounds (row.removeFromLeft (100));
    }
}

// ── Build settings JSON ──

juce::var ManualOptionsComponent::getSettings() const
{
    auto settings = std::make_unique<juce::DynamicObject>();
    auto algorithms = std::make_unique<juce::DynamicObject>();

    if (levelerToggle.getToggleState())
    {
        algorithms->setProperty ("leveler", true);

        bool separateMs = separateMsToggle.getToggleState();
        bool broadcast  = broadcastToggle.getToggleState();

        if (separateMs)
        {
            // Separate Music/Speech mode
            int clsId = classifierCombo.getSelectedId();
            if (clsId == 1)      algorithms->setProperty ("msclassifier", "on");
            else if (clsId == 2) algorithms->setProperty ("msclassifier", "speech");
            else if (clsId == 3) algorithms->setProperty ("msclassifier", "music");

            algorithms->setProperty ("levelerstrength_speech", strengthComboToApiValue (speechStrengthCombo));
            algorithms->setProperty ("levelerstrength_music",  strengthComboToApiValue (musicStrengthCombo));
            algorithms->setProperty ("compressor_speech",      compressorComboToApiValue (speechCompressorCombo));
            algorithms->setProperty ("compressor_music",       compressorComboToApiValue (musicCompressorCombo));
            algorithms->setProperty ("musicgain",              musicGainComboToApiValue (musicGainCombo));
        }
        else
        {
            // Single mode
            algorithms->setProperty ("levelerstrength", strengthComboToApiValue (strengthCombo));
            algorithms->setProperty ("compressor",      compressorComboToApiValue (compressorCombo));
        }

        if (broadcast)
        {
            algorithms->setProperty ("maxlra", luComboToApiValue (maxLraCombo));
            algorithms->setProperty ("maxs",   luComboToApiValue (maxSCombo));
            algorithms->setProperty ("maxm",   luComboToApiValue (maxMCombo));

            // Music gain also relevant in broadcast mode (if not already set by separate mode)
            if (! separateMs)
                algorithms->setProperty ("musicgain", musicGainComboToApiValue (musicGainCombo));
        }
    }

    if (noiseToggle.getToggleState())
    {
        algorithms->setProperty ("denoise", true);

        int methodId = methodCombo.getSelectedId();
        if (methodId == 1)      algorithms->setProperty ("denoisemethod", "classic");
        else if (methodId == 2) algorithms->setProperty ("denoisemethod", "dynamic");
        else if (methodId == 3) algorithms->setProperty ("denoisemethod", "speech_isolation");
        else if (methodId == 4) algorithms->setProperty ("denoisemethod", "static");

        algorithms->setProperty ("denoiseamount", dbComboToApiValue (noiseAmountCombo));

        if (methodId >= 2)
            algorithms->setProperty ("deverbamount", dbComboToApiValue (reverbAmountCombo));

        if (methodId == 2 || methodId == 3)
            algorithms->setProperty ("debreathamount", dbComboToApiValue (breathAmountCombo));
    }

    if (filterToggle.getToggleState())
    {
        algorithms->setProperty ("filtering", true);

        int fmId = filterMethodCombo.getSelectedId();
        if (fmId == 1)      algorithms->setProperty ("filtermethod", "hipfilter");
        else if (fmId == 2) algorithms->setProperty ("filtermethod", "autoeq");
        else if (fmId == 3) algorithms->setProperty ("filtermethod", "bwe");
    }

    if (loudnessToggle.getToggleState())
    {
        algorithms->setProperty ("normloudness", true);
        int target = loudnessTargetCombo.getSelectedId();
        if (target == 1) algorithms->setProperty ("loudnesstarget", -16.0);
        else if (target == 2) algorithms->setProperty ("loudnesstarget", -23.0);
        else if (target == 3) algorithms->setProperty ("loudnesstarget", -24.0);
        else if (target == 4) algorithms->setProperty ("loudnesstarget", -14.0);
    }

    settings->setProperty ("algorithms", juce::var (algorithms.release()));
    return juce::var (settings.release());
}

bool ManualOptionsComponent::hasAnyEnabled() const
{
    return levelerToggle.getToggleState()
        || noiseToggle.getToggleState()
        || filterToggle.getToggleState()
        || loudnessToggle.getToggleState();
}
