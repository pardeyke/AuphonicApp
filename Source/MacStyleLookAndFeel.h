#pragma once

#include <juce_gui_basics/juce_gui_basics.h>

class MacStyleLookAndFeel : public juce::LookAndFeel_V4
{
public:
    MacStyleLookAndFeel();

    void drawButtonBackground (juce::Graphics&, juce::Button&,
                               const juce::Colour& backgroundColour,
                               bool shouldDrawButtonAsHighlighted,
                               bool shouldDrawButtonAsDown) override;

    void drawToggleButton (juce::Graphics&, juce::ToggleButton&,
                           bool shouldDrawButtonAsHighlighted,
                           bool shouldDrawButtonAsDown) override;

    void drawComboBox (juce::Graphics&, int width, int height, bool isButtonDown,
                       int buttonX, int buttonY, int buttonW, int buttonH,
                       juce::ComboBox&) override;

    void drawPopupMenuBackground (juce::Graphics&, int width, int height) override;

    void drawPopupMenuItem (juce::Graphics&, const juce::Rectangle<int>& area,
                            bool isSeparator, bool isActive, bool isHighlighted,
                            bool isTicked, bool hasSubMenu,
                            const juce::String& text, const juce::String& shortcutKeyText,
                            const juce::Drawable* icon, const juce::Colour* textColour) override;

    void drawProgressBar (juce::Graphics&, juce::ProgressBar&,
                          int width, int height,
                          double progress, const juce::String& textToShow) override;

    void drawTextEditorOutline (juce::Graphics&, int width, int height,
                                juce::TextEditor&) override;

    void drawLabel (juce::Graphics&, juce::Label&) override;

    juce::Font getComboBoxFont (juce::ComboBox&) override;
    juce::Font getPopupMenuFont() override;
    juce::Font getLabelFont (juce::Label&) override;
    juce::Font getTextButtonFont (juce::TextButton&, int buttonHeight) override;

private:
    juce::Colour accentColour;
    juce::Colour bgColour;
    juce::Colour surfaceColour;
    juce::Colour textColour;
    juce::Colour secondaryTextColour;
    juce::Colour borderColour;

    juce::Font systemFont;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR (MacStyleLookAndFeel)
};
