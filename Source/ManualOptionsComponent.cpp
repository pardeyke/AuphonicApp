#include "ManualOptionsComponent.h"

ManualOptionsComponent::ManualOptionsComponent()
{
    addAndMakeVisible (separatorLabel);
    separatorLabel.setFont (juce::FontOptions (12.0f));
    separatorLabel.setColour (juce::Label::textColourId, juce::Colours::grey);
    separatorLabel.setJustificationType (juce::Justification::centredLeft);

    // ── Adaptive Leveler ──
    addAndMakeVisible (levelerToggle);
    levelerToggle.setToggleState (true, juce::dontSendNotification);
    levelerToggle.onClick = [this] { updateDependentVisibility(); notifyChange(); };

    addAndMakeVisible (strengthLabel);
    addAndMakeVisible (strengthCombo);
    populateStrengthCombo (strengthCombo);
    strengthCombo.onChange = [this] { notifyChange(); };

    addAndMakeVisible (compressorLabel);
    addAndMakeVisible (compressorCombo);
    populateCompressorCombo (compressorCombo);
    compressorCombo.onChange = [this] { notifyChange(); };

    // Separate Music/Speech
    addAndMakeVisible (separateMsToggle);
    separateMsToggle.onClick = [this] { updateDependentVisibility(); notifyChange(); };

    addAndMakeVisible (classifierLabel);
    addAndMakeVisible (classifierCombo);
    classifierCombo.addItem ("On", 1);
    classifierCombo.addItem ("Speech", 2);
    classifierCombo.addItem ("Music", 3);
    classifierCombo.setSelectedId (1, juce::dontSendNotification);
    classifierCombo.onChange = [this] { notifyChange(); };

    addAndMakeVisible (speechStrengthLabel);
    addAndMakeVisible (speechStrengthCombo);
    populateStrengthCombo (speechStrengthCombo);
    speechStrengthCombo.onChange = [this] { notifyChange(); };

    addAndMakeVisible (speechCompressorLabel);
    addAndMakeVisible (speechCompressorCombo);
    populateCompressorCombo (speechCompressorCombo);
    speechCompressorCombo.onChange = [this] { notifyChange(); };

    addAndMakeVisible (musicStrengthLabel);
    addAndMakeVisible (musicStrengthCombo);
    populateStrengthCombo (musicStrengthCombo);
    musicStrengthCombo.onChange = [this] { notifyChange(); };

    addAndMakeVisible (musicCompressorLabel);
    addAndMakeVisible (musicCompressorCombo);
    populateCompressorCombo (musicCompressorCombo);
    musicCompressorCombo.onChange = [this] { notifyChange(); };

    addAndMakeVisible (musicGainLabel);
    addAndMakeVisible (musicGainCombo);
    populateMusicGainCombo (musicGainCombo);
    musicGainCombo.onChange = [this] { notifyChange(); };

    // Broadcast mode
    addAndMakeVisible (broadcastToggle);
    broadcastToggle.onClick = [this] { updateDependentVisibility(); notifyChange(); };

    addAndMakeVisible (maxLraLabel);
    addAndMakeVisible (maxLraCombo);
    maxLraCombo.addItem ("Auto", 1);
    for (int v = 3; v <= 20; ++v)
        maxLraCombo.addItem (juce::String (v) + " LU", v + 10);
    maxLraCombo.setSelectedId (1, juce::dontSendNotification);
    maxLraCombo.onChange = [this] { notifyChange(); };

    addAndMakeVisible (maxSLabel);
    addAndMakeVisible (maxSCombo);
    maxSCombo.addItem ("Auto", 1);
    for (int v = 3; v <= 12; ++v)
        maxSCombo.addItem (juce::String (v) + " LU", v + 10);
    maxSCombo.setSelectedId (1, juce::dontSendNotification);
    maxSCombo.onChange = [this] { notifyChange(); };

    addAndMakeVisible (maxMLabel);
    addAndMakeVisible (maxMCombo);
    maxMCombo.addItem ("Auto", 1);
    for (int v = 8; v <= 20; ++v)
        maxMCombo.addItem (juce::String (v) + " LU", v + 10);
    maxMCombo.setSelectedId (1, juce::dontSendNotification);
    maxMCombo.onChange = [this] { notifyChange(); };

    // ── Noise Reduction ──
    addAndMakeVisible (noiseToggle);
    noiseToggle.setToggleState (true, juce::dontSendNotification);
    noiseToggle.onClick = [this] { updateDependentVisibility(); notifyChange(); };

    addAndMakeVisible (methodLabel);
    addAndMakeVisible (methodCombo);
    methodCombo.addItem ("Classic", 1);
    methodCombo.addItem ("Dynamic", 2);
    methodCombo.addItem ("Speech Isolation", 3);
    methodCombo.addItem ("Static", 4);
    methodCombo.setSelectedId (1, juce::dontSendNotification);
    methodCombo.onChange = [this] { updateDependentVisibility(); notifyChange(); };

    addAndMakeVisible (noiseAmountLabel);
    addAndMakeVisible (noiseAmountCombo);
    populateDbCombo (noiseAmountCombo, false);
    noiseAmountCombo.onChange = [this] { notifyChange(); };

    addAndMakeVisible (reverbAmountLabel);
    addAndMakeVisible (reverbAmountCombo);
    populateDbCombo (reverbAmountCombo, false);
    reverbAmountCombo.onChange = [this] { notifyChange(); };

    addAndMakeVisible (breathAmountLabel);
    addAndMakeVisible (breathAmountCombo);
    populateDbCombo (breathAmountCombo, true);
    breathAmountCombo.onChange = [this] { notifyChange(); };

    // ── Filtering ──
    addAndMakeVisible (filterToggle);
    filterToggle.setToggleState (true, juce::dontSendNotification);
    filterToggle.onClick = [this] { updateDependentVisibility(); notifyChange(); };

    addAndMakeVisible (filterMethodLabel);
    addAndMakeVisible (filterMethodCombo);
    filterMethodCombo.addItem ("High-Pass Filter", 1);
    filterMethodCombo.addItem ("Auto EQ", 2);
    filterMethodCombo.addItem ("Bandwidth Extension", 3);
    filterMethodCombo.setSelectedId (1, juce::dontSendNotification);
    filterMethodCombo.onChange = [this] { notifyChange(); };

    // ── Loudness ──
    addAndMakeVisible (loudnessToggle);
    loudnessToggle.onClick = [this] { notifyChange(); };
    addAndMakeVisible (loudnessTargetLabel);
    addAndMakeVisible (loudnessTargetCombo);
    loudnessTargetCombo.addItem ("-16 LUFS", 1);
    loudnessTargetCombo.addItem ("-23 LUFS", 2);
    loudnessTargetCombo.addItem ("-24 LUFS", 3);
    loudnessTargetCombo.addItem ("-14 LUFS", 4);
    loudnessTargetCombo.setSelectedId (1, juce::dontSendNotification);
    loudnessTargetCombo.onChange = [this] { notifyChange(); };

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

juce::var ManualOptionsComponent::getWidgetState() const
{
    auto state = std::make_unique<juce::DynamicObject>();

    // Toggles
    state->setProperty ("leveler", levelerToggle.getToggleState());
    state->setProperty ("separateMs", separateMsToggle.getToggleState());
    state->setProperty ("broadcast", broadcastToggle.getToggleState());
    state->setProperty ("noise", noiseToggle.getToggleState());
    state->setProperty ("filter", filterToggle.getToggleState());
    state->setProperty ("loudness", loudnessToggle.getToggleState());

    // Combos
    state->setProperty ("strength", strengthCombo.getSelectedId());
    state->setProperty ("compressor", compressorCombo.getSelectedId());
    state->setProperty ("classifier", classifierCombo.getSelectedId());
    state->setProperty ("speechStrength", speechStrengthCombo.getSelectedId());
    state->setProperty ("speechCompressor", speechCompressorCombo.getSelectedId());
    state->setProperty ("musicStrength", musicStrengthCombo.getSelectedId());
    state->setProperty ("musicCompressor", musicCompressorCombo.getSelectedId());
    state->setProperty ("musicGain", musicGainCombo.getSelectedId());
    state->setProperty ("maxLra", maxLraCombo.getSelectedId());
    state->setProperty ("maxS", maxSCombo.getSelectedId());
    state->setProperty ("maxM", maxMCombo.getSelectedId());
    state->setProperty ("method", methodCombo.getSelectedId());
    state->setProperty ("noiseAmount", noiseAmountCombo.getSelectedId());
    state->setProperty ("reverbAmount", reverbAmountCombo.getSelectedId());
    state->setProperty ("breathAmount", breathAmountCombo.getSelectedId());
    state->setProperty ("filterMethod", filterMethodCombo.getSelectedId());
    state->setProperty ("loudnessTarget", loudnessTargetCombo.getSelectedId());

    return juce::var (state.release());
}

void ManualOptionsComponent::applyWidgetState (const juce::var& state)
{
    if (! state.isObject())
        return;

    suppressCallbacks = true;

    auto setToggle = [&] (juce::ToggleButton& toggle, const juce::Identifier& key, bool defaultVal)
    {
        toggle.setToggleState ((bool) state.getProperty (key, defaultVal), juce::dontSendNotification);
    };

    auto setCombo = [&] (juce::ComboBox& combo, const juce::Identifier& key, int defaultId)
    {
        int id = (int) state.getProperty (key, defaultId);
        if (id > 0)
            combo.setSelectedId (id, juce::dontSendNotification);
    };

    setToggle (levelerToggle, "leveler", true);
    setToggle (separateMsToggle, "separateMs", false);
    setToggle (broadcastToggle, "broadcast", false);
    setToggle (noiseToggle, "noise", true);
    setToggle (filterToggle, "filter", true);
    setToggle (loudnessToggle, "loudness", false);

    setCombo (strengthCombo, "strength", 1);
    setCombo (compressorCombo, "compressor", 1);
    setCombo (classifierCombo, "classifier", 1);
    setCombo (speechStrengthCombo, "speechStrength", 1);
    setCombo (speechCompressorCombo, "speechCompressor", 1);
    setCombo (musicStrengthCombo, "musicStrength", 1);
    setCombo (musicCompressorCombo, "musicCompressor", 1);
    setCombo (musicGainCombo, "musicGain", 7);
    setCombo (maxLraCombo, "maxLra", 1);
    setCombo (maxSCombo, "maxS", 1);
    setCombo (maxMCombo, "maxM", 1);
    setCombo (methodCombo, "method", 1);
    setCombo (noiseAmountCombo, "noiseAmount", 2);
    setCombo (reverbAmountCombo, "reverbAmount", 2);
    setCombo (breathAmountCombo, "breathAmount", 1);
    setCombo (filterMethodCombo, "filterMethod", 1);
    setCombo (loudnessTargetCombo, "loudnessTarget", 1);

    suppressCallbacks = false;
    updateDependentVisibility();
}

void ManualOptionsComponent::notifyChange()
{
    if (! suppressCallbacks && onChange)
        onChange();
}

// ── Reverse-map API algorithms to widget states ──

static int apiValueToStrengthId (int pct)
{
    // API value 0-100, id = 101 - value  (id 1 = 100%, id 11 = 0%)
    pct = juce::jlimit (0, 100, pct);
    return 101 - (pct / 10) * 10;  // snap to nearest 10
}

static int apiValueToCompressorId (const juce::String& val)
{
    if (val == "soft")   return 2;
    if (val == "medium") return 3;
    if (val == "hard")   return 4;
    if (val == "off")    return 5;
    return 1; // auto
}

static int apiValueToDbId (int val)
{
    // values[] = { -1, 0, 3, 6, 9, 12, 15, 18, 24, 30, 36 }  → id 1..11
    static const int values[] = { -1, 0, 3, 6, 9, 12, 15, 18, 24, 30, 36 };
    for (int i = 0; i < 11; ++i)
        if (values[i] == val)
            return i + 1;
    return 1; // Off
}

static int apiValueToLuId (int val)
{
    if (val == 0) return 1; // Auto
    return val + 10;
}

void ManualOptionsComponent::applyApiSettings (const juce::var& algorithms)
{
    suppressCallbacks = true;

    // ── Adaptive Leveler ──
    bool hasLeveler = (bool) algorithms.getProperty ("leveler", false);
    levelerToggle.setToggleState (hasLeveler, juce::dontSendNotification);

    bool hasMsClassifier = algorithms.hasProperty ("msclassifier");
    separateMsToggle.setToggleState (hasMsClassifier, juce::dontSendNotification);

    bool hasBroadcast = algorithms.hasProperty ("maxlra")
                     || algorithms.hasProperty ("maxs")
                     || algorithms.hasProperty ("maxm");
    broadcastToggle.setToggleState (hasBroadcast, juce::dontSendNotification);

    if (hasMsClassifier)
    {
        auto cls = algorithms.getProperty ("msclassifier", "on").toString();
        if (cls == "speech")     classifierCombo.setSelectedId (2, juce::dontSendNotification);
        else if (cls == "music") classifierCombo.setSelectedId (3, juce::dontSendNotification);
        else                     classifierCombo.setSelectedId (1, juce::dontSendNotification);

        speechStrengthCombo.setSelectedId (apiValueToStrengthId ((int) algorithms.getProperty ("levelerstrength_speech", 100)), juce::dontSendNotification);
        musicStrengthCombo.setSelectedId (apiValueToStrengthId ((int) algorithms.getProperty ("levelerstrength_music", 100)), juce::dontSendNotification);
        speechCompressorCombo.setSelectedId (apiValueToCompressorId (algorithms.getProperty ("compressor_speech", "auto").toString()), juce::dontSendNotification);
        musicCompressorCombo.setSelectedId (apiValueToCompressorId (algorithms.getProperty ("compressor_music", "auto").toString()), juce::dontSendNotification);
    }
    else
    {
        strengthCombo.setSelectedId (apiValueToStrengthId ((int) algorithms.getProperty ("levelerstrength", 100)), juce::dontSendNotification);
        compressorCombo.setSelectedId (apiValueToCompressorId (algorithms.getProperty ("compressor", "auto").toString()), juce::dontSendNotification);
    }

    if (algorithms.hasProperty ("musicgain"))
        musicGainCombo.setSelectedId ((int) algorithms.getProperty ("musicgain", 0) + 7, juce::dontSendNotification);

    if (hasBroadcast)
    {
        maxLraCombo.setSelectedId (apiValueToLuId ((int) algorithms.getProperty ("maxlra", 0)), juce::dontSendNotification);
        maxSCombo.setSelectedId (apiValueToLuId ((int) algorithms.getProperty ("maxs", 0)), juce::dontSendNotification);
        maxMCombo.setSelectedId (apiValueToLuId ((int) algorithms.getProperty ("maxm", 0)), juce::dontSendNotification);
    }

    // ── Noise Reduction ──
    bool hasDenoise = (bool) algorithms.getProperty ("denoise", false);
    noiseToggle.setToggleState (hasDenoise, juce::dontSendNotification);

    if (hasDenoise)
    {
        auto method = algorithms.getProperty ("denoisemethod", "classic").toString();
        if (method == "dynamic")               methodCombo.setSelectedId (2, juce::dontSendNotification);
        else if (method == "speech_isolation")  methodCombo.setSelectedId (3, juce::dontSendNotification);
        else if (method == "static")           methodCombo.setSelectedId (4, juce::dontSendNotification);
        else                                   methodCombo.setSelectedId (1, juce::dontSendNotification);

        noiseAmountCombo.setSelectedId (apiValueToDbId ((int) algorithms.getProperty ("denoiseamount", 0)), juce::dontSendNotification);

        if (algorithms.hasProperty ("deverbamount"))
            reverbAmountCombo.setSelectedId (apiValueToDbId ((int) algorithms.getProperty ("deverbamount", 0)), juce::dontSendNotification);

        if (algorithms.hasProperty ("debreathamount"))
            breathAmountCombo.setSelectedId (apiValueToDbId ((int) algorithms.getProperty ("debreathamount", -1)), juce::dontSendNotification);
    }

    // ── Filtering ──
    bool hasFiltering = (bool) algorithms.getProperty ("filtering", false);
    filterToggle.setToggleState (hasFiltering, juce::dontSendNotification);

    if (hasFiltering)
    {
        auto fm = algorithms.getProperty ("filtermethod", "hipfilter").toString();
        if (fm == "autoeq")      filterMethodCombo.setSelectedId (2, juce::dontSendNotification);
        else if (fm == "bwe")    filterMethodCombo.setSelectedId (3, juce::dontSendNotification);
        else                     filterMethodCombo.setSelectedId (1, juce::dontSendNotification);
    }

    // ── Loudness ──
    bool hasLoudness = (bool) algorithms.getProperty ("normloudness", false);
    loudnessToggle.setToggleState (hasLoudness, juce::dontSendNotification);

    if (hasLoudness)
    {
        int target = juce::roundToInt ((double) algorithms.getProperty ("loudnesstarget", -16.0));
        if (target == -23)      loudnessTargetCombo.setSelectedId (2, juce::dontSendNotification);
        else if (target == -24) loudnessTargetCombo.setSelectedId (3, juce::dontSendNotification);
        else if (target == -14) loudnessTargetCombo.setSelectedId (4, juce::dontSendNotification);
        else                    loudnessTargetCombo.setSelectedId (1, juce::dontSendNotification);
    }

    suppressCallbacks = false;
    updateDependentVisibility();
}
