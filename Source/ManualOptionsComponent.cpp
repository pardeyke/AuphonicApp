#include "ManualOptionsComponent.h"

// ── Bitrate tables (indexed by format combo ID) ──────────────────────────────
// Format IDs: 1=WAV16, 2=WAV24, 3=FLAC, 4=ALAC (lossless – no bitrate)
//             5=MP3, 6=MP3-VBR, 7=AAC, 8=OGG, 9=Opus
namespace
{
    static const int kMp3Bitrates[]  = { 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320 };
    static const int kAacBitrates[]  = { 24, 32, 40, 48, 56, 64, 80,  96, 112, 128, 160, 192, 256, 320 };
    static const int kOpusBitrates[] = {  6, 12, 16, 20, 24, 32, 40,  48,  56,  64,  80,  96, 112, 128, 160, 192, 256 };

    struct BitrateInfo { const int* values; int count; int defaultKbps; };

    BitrateInfo bitrateInfoForFormat (int formatComboId)
    {
        switch (formatComboId)
        {
            case 5:  return { kMp3Bitrates,  14, 112 }; // MP3
            case 6:  return { kMp3Bitrates,  14,  96 }; // MP3 VBR
            case 7:  return { kAacBitrates,  14,  80 }; // AAC
            case 8:  return { kMp3Bitrates,  14,  96 }; // OGG Vorbis
            case 9:  return { kOpusBitrates, 17,  48 }; // Opus
            default: return { nullptr,        0,   0 }; // lossless
        }
    }
} // namespace

ManualOptionsComponent::ManualOptionsComponent()
{
    // ── Channel Selector (hidden by default, shown for multi-channel files) ──
    addChildComponent (channelLabel);
    addChildComponent (channelCombo);
    channelCombo.onChange = [this] { notifyChange(); };

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

    // ── Output Format ──
    addAndMakeVisible (outputFormatLabel);
    addAndMakeVisible (outputFormatCombo);
    outputFormatCombo.addItem ("Keep Format", 10);
    outputFormatCombo.addSeparator();
    outputFormatCombo.addItem ("WAV 16-bit", 1);
    outputFormatCombo.addItem ("WAV 24-bit", 2);
    outputFormatCombo.addItem ("FLAC",       3);
    outputFormatCombo.addItem ("ALAC",       4);
    outputFormatCombo.addItem ("MP3",        5);
    outputFormatCombo.addItem ("MP3 VBR",    6);
    outputFormatCombo.addItem ("AAC",        7);
    outputFormatCombo.addItem ("OGG Vorbis", 8);
    outputFormatCombo.addItem ("Opus",       9);
    outputFormatCombo.setSelectedId (10, juce::dontSendNotification);
    outputFormatCombo.onChange = [this] { populateBitrateCombo(); updateDependentVisibility(); notifyChange(); };

    addAndMakeVisible (bitrateLabel);
    addAndMakeVisible (bitrateCombo);
    populateBitrateCombo();
    bitrateCombo.onChange = [this] { notifyChange(); };

    // ── Output Behavior ──
    addAndMakeVisible (avoidOverwriteToggle);
    avoidOverwriteToggle.onClick = [this] { updateDependentVisibility(); notifyChange(); };

    addAndMakeVisible (suffixLabel);
    addAndMakeVisible (suffixEditor);
    suffixEditor.setText ("_auphonic", juce::dontSendNotification);
    suffixEditor.onTextChange = [this] { notifyChange(); };

    addAndMakeVisible (writeXmlToggle);
    writeXmlToggle.onClick = [this] { notifyChange(); };

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

void ManualOptionsComponent::populateBitrateCombo()
{
    bitrateCombo.clear (juce::dontSendNotification);

    auto info = bitrateInfoForFormat (outputFormatCombo.getSelectedId());
    if (info.values == nullptr)
        return;

    for (int i = 0; i < info.count; ++i)
        bitrateCombo.addItem (juce::String (info.values[i]) + " kbps", i + 1);

    // Select the default bitrate
    for (int i = 0; i < info.count; ++i)
    {
        if (info.values[i] == info.defaultKbps)
        {
            bitrateCombo.setSelectedId (i + 1, juce::dontSendNotification);
            break;
        }
    }
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
    // IDs are 101 - pct: id 1 = 100%, id 11 = 90%, id 21 = 80%, ... id 101 = 0%
    int id = combo.getSelectedId();
    return juce::jlimit (0, 100, 101 - id);
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

    // Suffix field (visible when "create new file" is on)
    bool showSuffix = avoidOverwriteToggle.getToggleState();
    suffixLabel.setVisible (showSuffix);
    suffixEditor.setVisible (showSuffix);

    // Bitrate (lossy formats only: IDs 5–9, not Keep Format ID=10)
    int fmtId = outputFormatCombo.getSelectedId();
    bool showBitrate = (fmtId >= 5 && fmtId <= 9);
    bitrateLabel.setVisible (showBitrate);
    bitrateCombo.setVisible (showBitrate);

    setSize (getWidth(), getRequiredHeight());
}

// ── Layout ──

void ManualOptionsComponent::resized()
{
    auto area = getLocalBounds();

    auto toggleWidth = [] (const juce::ToggleButton& t) {
        return 36 + 8 + (int) juce::Font (juce::FontOptions (13.0f)).getStringWidthFloat (t.getButtonText()) + 4;
    };

    auto addGap = [&] { area.removeFromTop (gap); };

    // Layout a toggle button row with optional indent
    auto layoutToggle = [&] (juce::ToggleButton& toggle, int indentMul = 0) {
        auto row = area.removeFromTop (rowH);
        row.removeFromLeft (indent * indentMul);
        toggle.setBounds (row.removeFromLeft (toggleWidth (toggle)));
        addGap();
    };

    // Layout a label + combo row with optional indent
    auto layoutLabelCombo = [&] (int indentMul, juce::Label& lbl, int lblW, juce::ComboBox& cmb, int cmbW) {
        auto row = area.removeFromTop (rowH);
        row.removeFromLeft (indent * indentMul);
        lbl.setBounds (row.removeFromLeft (lblW));
        cmb.setBounds (row.removeFromLeft (cmbW));
        addGap();
    };

    // Layout two label + combo pairs on one row
    auto layoutDualCombo = [&] (int indentMul,
                                 juce::Label& lbl1, int lbl1W, juce::ComboBox& cmb1, int cmb1W,
                                 juce::Label& lbl2, int lbl2W, juce::ComboBox& cmb2, int cmb2W) {
        auto row = area.removeFromTop (rowH);
        row.removeFromLeft (indent * indentMul);
        lbl1.setBounds (row.removeFromLeft (lbl1W));
        cmb1.setBounds (row.removeFromLeft (cmb1W));
        row.removeFromLeft (8);
        lbl2.setBounds (row.removeFromLeft (lbl2W));
        cmb2.setBounds (row.removeFromLeft (cmb2W));
        addGap();
    };

    // ── Channel Selector ──
    if (channelCombo.isVisible())
        layoutLabelCombo (0, channelLabel, 70, channelCombo, 180);

    // ── Leveler ──
    layoutToggle (levelerToggle);

    if (strengthCombo.isVisible())
        layoutDualCombo (1, strengthLabel, 70, strengthCombo, 80,
                            compressorLabel, 80, compressorCombo, 90);

    if (separateMsToggle.isVisible())
        layoutToggle (separateMsToggle, 1);

    if (classifierCombo.isVisible())
    {
        layoutLabelCombo (2, classifierLabel, 70, classifierCombo, 90);
        layoutDualCombo (2, speechStrengthLabel, 110, speechStrengthCombo, 80,
                            speechCompressorLabel, 80, speechCompressorCombo, 90);
        layoutDualCombo (2, musicStrengthLabel, 110, musicStrengthCombo, 80,
                            musicCompressorLabel, 80, musicCompressorCombo, 90);
    }

    if (musicGainCombo.isVisible())
        layoutLabelCombo (2, musicGainLabel, 80, musicGainCombo, 90);

    if (broadcastToggle.isVisible())
        layoutToggle (broadcastToggle, 1);

    if (maxLraCombo.isVisible())
    {
        layoutLabelCombo (2, maxLraLabel, 80, maxLraCombo, 80);
        layoutLabelCombo (2, maxSLabel, 110, maxSCombo, 80);
        layoutLabelCombo (2, maxMLabel, 110, maxMCombo, 80);
    }

    // ── Noise Reduction ──
    layoutToggle (noiseToggle);

    if (methodCombo.isVisible())
        layoutLabelCombo (1, methodLabel, 60, methodCombo, 200);
    if (noiseAmountCombo.isVisible())
        layoutLabelCombo (1, noiseAmountLabel, 100, noiseAmountCombo, 140);
    if (reverbAmountCombo.isVisible())
        layoutLabelCombo (1, reverbAmountLabel, 100, reverbAmountCombo, 140);
    if (breathAmountCombo.isVisible())
        layoutLabelCombo (1, breathAmountLabel, 100, breathAmountCombo, 140);

    // ── Filtering ──
    layoutToggle (filterToggle);

    if (filterMethodCombo.isVisible())
        layoutLabelCombo (1, filterMethodLabel, 60, filterMethodCombo, 180);

    // ── Loudness ──
    {
        auto row = area.removeFromTop (rowH);
        loudnessToggle.setBounds (row.removeFromLeft (toggleWidth (loudnessToggle)));
        row.removeFromLeft (8);
        loudnessTargetLabel.setBounds (row.removeFromLeft (50));
        loudnessTargetCombo.setBounds (row.removeFromLeft (100));
    }

    // ── Output Format ──
    addGap();
    layoutLabelCombo (0, outputFormatLabel, 100, outputFormatCombo, 120);

    if (bitrateCombo.isVisible())
        layoutLabelCombo (0, bitrateLabel, 100, bitrateCombo, 120);

    // ── Output Behavior ──
    area.removeFromTop (2);
    avoidOverwriteToggle.setBounds (area.removeFromTop (rowH));
    addGap();

    if (suffixEditor.isVisible())
    {
        auto row = area.removeFromTop (rowH);
        row.removeFromLeft (indent);
        suffixLabel.setBounds (row.removeFromLeft (50));
        suffixEditor.setBounds (row.removeFromLeft (150));
        addGap();
    }

    writeXmlToggle.setBounds (area.removeFromTop (rowH));
}

int ManualOptionsComponent::getRequiredHeight() const
{
    int h = 0;
    auto addRow = [&] { h += rowH + gap; };

    // Channel selector
    if (channelCombo.isVisible()) addRow();

    // Leveler toggle
    addRow();

    if (strengthCombo.isVisible()) addRow();
    if (separateMsToggle.isVisible()) addRow();

    if (classifierCombo.isVisible())
    {
        addRow(); // classifier
        addRow(); // speech strength/compressor
        addRow(); // music strength/compressor
    }

    if (musicGainCombo.isVisible()) addRow();
    if (broadcastToggle.isVisible()) addRow();

    if (maxLraCombo.isVisible())
    {
        addRow(); // max LRA
        addRow(); // max S
        addRow(); // max M
    }

    // Noise toggle
    addRow();
    if (methodCombo.isVisible()) addRow();
    if (noiseAmountCombo.isVisible()) addRow();
    if (reverbAmountCombo.isVisible()) addRow();
    if (breathAmountCombo.isVisible()) addRow();

    // Filter toggle
    addRow();
    if (filterMethodCombo.isVisible()) addRow();

    // Loudness row
    h += rowH;

    // Output format row
    h += gap + rowH;

    // Bitrate row (lossy formats only)
    if (bitrateCombo.isVisible())
        h += gap + rowH;

    // Output behavior toggles (always visible)
    h += gap + 2 + rowH + gap; // avoidOverwrite toggle + gap
    if (suffixEditor.isVisible()) h += rowH + gap;
    h += rowH; // writeXml toggle

    return h;
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
    else
    {
        algorithms->setProperty ("leveler", false);
        algorithms->setProperty ("levelerstrength", 0);
        algorithms->setProperty ("compressor", "off");
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
    else
    {
        algorithms->setProperty ("denoise", false);
        algorithms->setProperty ("denoiseamount", -1);
        algorithms->setProperty ("debreathamount", -1);
        algorithms->setProperty ("dehumamount", -1);
    }

    if (filterToggle.getToggleState())
    {
        algorithms->setProperty ("filtering", true);

        int fmId = filterMethodCombo.getSelectedId();
        if (fmId == 1)      algorithms->setProperty ("filtermethod", "hipfilter");
        else if (fmId == 2) algorithms->setProperty ("filtermethod", "autoeq");
        else if (fmId == 3) algorithms->setProperty ("filtermethod", "bwe");
    }
    else
    {
        algorithms->setProperty ("filtering", false);
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
    else
    {
        algorithms->setProperty ("normloudness", false);
    }

    settings->setProperty ("algorithms", juce::var (algorithms.release()));

    static const char* formats[] = { "wav", "wav-24bit", "flac", "alac", "mp3", "mp3-vbr", "aac", "vorbis", "opus" };
    int fmtId = outputFormatCombo.getSelectedId();
    if (fmtId == 10)
        settings->setProperty ("output_format", "keep");
    else if (fmtId >= 1 && fmtId <= 9)
        settings->setProperty ("output_format", juce::String (formats[fmtId - 1]));

    auto bitrateInfo = bitrateInfoForFormat (fmtId);
    int bitrateIdx = bitrateCombo.getSelectedId() - 1;
    if (bitrateInfo.values != nullptr && bitrateIdx >= 0 && bitrateIdx < bitrateInfo.count)
        settings->setProperty ("output_bitrate", bitrateInfo.values[bitrateIdx]);

    return juce::var (settings.release());
}

bool ManualOptionsComponent::hasAnyEnabled() const
{
    return levelerToggle.getToggleState()
        || noiseToggle.getToggleState()
        || filterToggle.getToggleState()
        || loudnessToggle.getToggleState()
        || outputFormatCombo.getSelectedId() != 1; // non-default format (Keep Format or explicit selection)
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
    // Note: outputFormat and outputBitrate are intentionally NOT saved.
    // "Keep Format" is always the default.
    state->setProperty ("avoidOverwrite",  avoidOverwriteToggle.getToggleState());
    state->setProperty ("outputSuffix",    suffixEditor.getText());
    state->setProperty ("writeXml",        writeXmlToggle.getToggleState());
    state->setProperty ("selectedChannel", channelCombo.getSelectedId());

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
    // outputFormat is always "Keep Format" (id 10) — not restored from saved state.
    outputFormatCombo.setSelectedId (10, juce::dontSendNotification);
    populateBitrateCombo();
    setToggle (avoidOverwriteToggle, "avoidOverwrite", false);
    {
        auto suffix = state.getProperty ("outputSuffix", "_auphonic").toString();
        suffixEditor.setText (suffix, juce::dontSendNotification);
    }
    setToggle (writeXmlToggle, "writeXml", false);
    setCombo (channelCombo, "selectedChannel", 1);

    suppressCallbacks = false;
    updateDependentVisibility();
}

void ManualOptionsComponent::setFileChannelCount (int numChannels)
{
    currentFileChannels = numChannels;
    channelCombo.clear (juce::dontSendNotification);

    bool show = numChannels >= 2;
    channelLabel.setVisible (show);
    channelCombo.setVisible (show);

    if (show)
    {
        int previousId = channelCombo.getSelectedId();

        channelCombo.addItem ("All Channels", 1);
        for (int ch = 1; ch <= numChannels; ++ch)
        {
            juce::String name = "Channel " + juce::String (ch);
            if (numChannels == 2)
                name += (ch == 1 ? " (Left)" : " (Right)");
            channelCombo.addItem (name, ch + 1); // id 2 = ch 1, id 3 = ch 2, etc.
        }

        // Preserve previous channel selection if still valid, otherwise default to All Channels
        if (previousId >= 1 && previousId <= numChannels + 1)
            channelCombo.setSelectedId (previousId, juce::dontSendNotification);
        else
            channelCombo.setSelectedId (1, juce::dontSendNotification);
    }

    setSize (getWidth(), getRequiredHeight());
    resized();
}

int ManualOptionsComponent::getSelectedChannel() const
{
    if (! channelCombo.isVisible())
        return 0;
    int id = channelCombo.getSelectedId();
    return (id <= 1) ? 0 : (id - 1); // id 1 = All (0), id 2 = ch 1, id 3 = ch 2, etc.
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
