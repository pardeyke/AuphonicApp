#include "MacStyleLookAndFeel.h"

MacStyleLookAndFeel::MacStyleLookAndFeel()
    : systemFont (juce::FontOptions (13.0f))
{
    // macOS-inspired colour palette
    accentColour       = juce::Colour (0xff007aff); // macOS blue
    bgColour           = juce::Colour (0xff1e1e1e); // dark background
    surfaceColour      = juce::Colour (0xff2a2a2a); // card/surface
    textColour         = juce::Colour (0xffe5e5e5); // primary text
    secondaryTextColour = juce::Colour (0xff8e8e93); // secondary text
    borderColour       = juce::Colour (0xff3a3a3c); // borders

    // System font — try SF Pro, fall back to system UI font
    systemFont = juce::Font (juce::FontOptions ("SF Pro Text", 13.0f, juce::Font::plain));
    if (systemFont.getTypefaceName() == juce::Font (juce::FontOptions (13.0f)).getTypefaceName())
        systemFont = juce::Font (juce::FontOptions (".AppleSystemUIFont", 13.0f, juce::Font::plain));

    // Set colour scheme
    setColour (juce::ResizableWindow::backgroundColourId, bgColour);

    // Buttons
    setColour (juce::TextButton::buttonColourId, surfaceColour);
    setColour (juce::TextButton::buttonOnColourId, accentColour);
    setColour (juce::TextButton::textColourOffId, textColour);
    setColour (juce::TextButton::textColourOnId, juce::Colours::white);

    // ComboBox
    setColour (juce::ComboBox::backgroundColourId, surfaceColour);
    setColour (juce::ComboBox::textColourId, textColour);
    setColour (juce::ComboBox::outlineColourId, borderColour);
    setColour (juce::ComboBox::arrowColourId, secondaryTextColour);
    setColour (juce::ComboBox::focusedOutlineColourId, accentColour);

    // PopupMenu
    setColour (juce::PopupMenu::backgroundColourId, juce::Colour (0xff2c2c2e));
    setColour (juce::PopupMenu::textColourId, textColour);
    setColour (juce::PopupMenu::highlightedBackgroundColourId, accentColour);
    setColour (juce::PopupMenu::highlightedTextColourId, juce::Colours::white);

    // TextEditor
    setColour (juce::TextEditor::backgroundColourId, surfaceColour);
    setColour (juce::TextEditor::textColourId, textColour);
    setColour (juce::TextEditor::outlineColourId, borderColour);
    setColour (juce::TextEditor::focusedOutlineColourId, accentColour);
    setColour (juce::TextEditor::highlightColourId, accentColour.withAlpha (0.4f));

    // Labels
    setColour (juce::Label::textColourId, textColour);
    setColour (juce::Label::outlineColourId, juce::Colours::transparentBlack);

    // ProgressBar
    setColour (juce::ProgressBar::backgroundColourId, surfaceColour);
    setColour (juce::ProgressBar::foregroundColourId, accentColour);

    // ToggleButton
    setColour (juce::ToggleButton::textColourId, textColour);
    setColour (juce::ToggleButton::tickColourId, juce::Colours::white);
    setColour (juce::ToggleButton::tickDisabledColourId, secondaryTextColour);

    // ScrollBar
    setColour (juce::ScrollBar::thumbColourId, juce::Colour (0xff555558));
    setColour (juce::ScrollBar::trackColourId, juce::Colours::transparentBlack);

    // AlertWindow
    setColour (juce::AlertWindow::backgroundColourId, juce::Colour (0xff2c2c2e));
    setColour (juce::AlertWindow::textColourId, textColour);
    setColour (juce::AlertWindow::outlineColourId, borderColour);
}

// ── Buttons ──

void MacStyleLookAndFeel::drawButtonBackground (juce::Graphics& g, juce::Button& button,
                                                  const juce::Colour& backgroundColour,
                                                  bool isHighlighted, bool isDown)
{
    auto bounds = button.getLocalBounds().toFloat().reduced (0.5f);
    auto cornerSize = 6.0f;

    auto baseColour = backgroundColour;
    if (isDown)
        baseColour = baseColour.brighter (0.1f);
    else if (isHighlighted)
        baseColour = baseColour.brighter (0.05f);

    // Primary-style button for "Process"
    if (button.getToggleState() || button.getName().containsIgnoreCase ("process"))
    {
        baseColour = accentColour;
        if (isDown)
            baseColour = baseColour.darker (0.15f);
        else if (isHighlighted)
            baseColour = baseColour.brighter (0.1f);
    }

    g.setColour (baseColour);
    g.fillRoundedRectangle (bounds, cornerSize);

    // Subtle border
    g.setColour (borderColour.withAlpha (0.5f));
    g.drawRoundedRectangle (bounds, cornerSize, 0.5f);

    if (! button.isEnabled())
    {
        g.setColour (bgColour.withAlpha (0.5f));
        g.fillRoundedRectangle (bounds, cornerSize);
    }
}

// ── Toggle buttons as macOS-style switches ──

void MacStyleLookAndFeel::drawToggleButton (juce::Graphics& g, juce::ToggleButton& button,
                                             bool isHighlighted, bool /*isDown*/)
{
    auto bounds = button.getLocalBounds().toFloat();

    // Switch dimensions
    float switchW = 36.0f;
    float switchH = 20.0f;
    float knobSize = 16.0f;
    float switchY = (bounds.getHeight() - switchH) / 2.0f;

    auto switchBounds = juce::Rectangle<float> (bounds.getX() + 2, switchY, switchW, switchH);

    bool isOn = button.getToggleState();

    // Track
    auto trackColour = isOn ? accentColour : juce::Colour (0xff48484a);
    if (isHighlighted)
        trackColour = trackColour.brighter (0.08f);

    g.setColour (trackColour);
    g.fillRoundedRectangle (switchBounds, switchH / 2.0f);

    // Knob
    float knobX = isOn ? switchBounds.getRight() - knobSize - 2.0f
                       : switchBounds.getX() + 2.0f;
    float knobY = switchBounds.getY() + (switchH - knobSize) / 2.0f;

    g.setColour (juce::Colours::white);
    g.fillEllipse (knobX, knobY, knobSize, knobSize);

    // Subtle knob shadow
    g.setColour (juce::Colours::black.withAlpha (0.15f));
    g.drawEllipse (knobX, knobY, knobSize, knobSize, 0.5f);

    // Label text
    auto textArea = bounds.withTrimmedLeft (switchW + 8.0f);
    g.setColour (button.isEnabled() ? textColour : secondaryTextColour);
    g.setFont (systemFont);
    g.drawText (button.getButtonText(), textArea.toNearestInt(),
                juce::Justification::centredLeft, true);

    if (! button.isEnabled())
    {
        g.setColour (bgColour.withAlpha (0.4f));
        g.fillRoundedRectangle (switchBounds, switchH / 2.0f);
    }
}

// ── ComboBox ──

void MacStyleLookAndFeel::drawComboBox (juce::Graphics& g, int width, int height,
                                         bool isButtonDown, int, int, int, int,
                                         juce::ComboBox& box)
{
    auto bounds = juce::Rectangle<float> (0, 0, (float) width, (float) height).reduced (0.5f);
    auto cornerSize = 6.0f;

    auto bg = box.findColour (juce::ComboBox::backgroundColourId);
    if (isButtonDown)
        bg = bg.brighter (0.05f);

    g.setColour (bg);
    g.fillRoundedRectangle (bounds, cornerSize);

    auto outlineColour = box.hasKeyboardFocus (true)
        ? box.findColour (juce::ComboBox::focusedOutlineColourId)
        : box.findColour (juce::ComboBox::outlineColourId);

    g.setColour (outlineColour);
    g.drawRoundedRectangle (bounds, cornerSize, 0.5f);

    // Chevron arrow
    auto arrowZone = juce::Rectangle<float> ((float) width - 22.0f,
                                              (float) height * 0.5f - 4.0f,
                                              12.0f, 8.0f);
    juce::Path chevron;
    chevron.addTriangle (arrowZone.getX(), arrowZone.getY(),
                         arrowZone.getCentreX(), arrowZone.getBottom(),
                         arrowZone.getRight(), arrowZone.getY());

    g.setColour (box.findColour (juce::ComboBox::arrowColourId));
    g.fillPath (chevron);
}

// ── PopupMenu ──

void MacStyleLookAndFeel::drawPopupMenuBackground (juce::Graphics& g, int width, int height)
{
    auto bounds = juce::Rectangle<float> (0, 0, (float) width, (float) height);

    // Fill entire area to eliminate default white window background
    g.fillAll (findColour (juce::PopupMenu::backgroundColourId));

    // Draw rounded border on top
    g.setColour (borderColour);
    g.drawRoundedRectangle (bounds.reduced (1), 8.0f, 0.5f);
}

void MacStyleLookAndFeel::drawPopupMenuItem (juce::Graphics& g, const juce::Rectangle<int>& area,
                                              bool isSeparator, bool isActive, bool isHighlighted,
                                              bool isTicked, bool hasSubMenu,
                                              const juce::String& text, const juce::String&,
                                              const juce::Drawable*, const juce::Colour*)
{
    if (isSeparator)
    {
        auto sepArea = area.reduced (8, 0);
        g.setColour (borderColour);
        g.fillRect (sepArea.withHeight (1).withY (area.getCentreY()));
        return;
    }

    auto r = area.reduced (4, 1);

    if (isHighlighted && isActive)
    {
        g.setColour (accentColour);
        g.fillRoundedRectangle (r.toFloat(), 4.0f);
        g.setColour (juce::Colours::white);
    }
    else
    {
        g.setColour (isActive ? textColour : secondaryTextColour);
    }

    auto textArea = r.reduced (8, 0);

    if (isTicked)
    {
        auto checkArea = textArea.removeFromLeft (20);
        auto dotSize = 6.0f;
        auto dotX = checkArea.getCentreX() - dotSize / 2.0f;
        auto dotY = checkArea.getCentreY() - dotSize / 2.0f;
        g.fillEllipse (dotX, dotY, dotSize, dotSize);
    }

    g.setFont (systemFont);
    g.drawFittedText (text, textArea, juce::Justification::centredLeft, 1);

    if (hasSubMenu)
    {
        auto arrowArea = r.removeFromRight (14);
        g.drawText (">", arrowArea, juce::Justification::centred);
    }
}

// ── ProgressBar ──

void MacStyleLookAndFeel::drawProgressBar (juce::Graphics& g, juce::ProgressBar&,
                                            int width, int height,
                                            double progress, const juce::String&)
{
    auto bounds = juce::Rectangle<float> (0, 0, (float) width, (float) height);
    auto barHeight = juce::jmin (6.0f, bounds.getHeight());
    auto barBounds = bounds.withSizeKeepingCentre (bounds.getWidth(), barHeight);
    auto cornerSize = barHeight / 2.0f;

    // Track
    g.setColour (surfaceColour);
    g.fillRoundedRectangle (barBounds, cornerSize);

    // Fill
    if (progress >= 0.0 && progress <= 1.0)
    {
        auto fillBounds = barBounds.withWidth (barBounds.getWidth() * (float) progress);
        if (fillBounds.getWidth() > 0)
        {
            g.setColour (accentColour);
            g.fillRoundedRectangle (fillBounds, cornerSize);
        }
    }
    else
    {
        // Indeterminate — pulse animation
        g.setColour (accentColour.withAlpha (0.6f));
        g.fillRoundedRectangle (barBounds, cornerSize);
    }
}

// ── TextEditor ──

void MacStyleLookAndFeel::drawTextEditorOutline (juce::Graphics& g, int width, int height,
                                                   juce::TextEditor& editor)
{
    auto bounds = juce::Rectangle<float> (0, 0, (float) width, (float) height).reduced (0.5f);
    auto cornerSize = 6.0f;

    auto outlineColour = editor.hasKeyboardFocus (true)
        ? editor.findColour (juce::TextEditor::focusedOutlineColourId)
        : editor.findColour (juce::TextEditor::outlineColourId);

    g.setColour (outlineColour);
    g.drawRoundedRectangle (bounds, cornerSize, editor.hasKeyboardFocus (true) ? 1.5f : 0.5f);
}

// ── Label ──

void MacStyleLookAndFeel::drawLabel (juce::Graphics& g, juce::Label& label)
{
    g.fillAll (label.findColour (juce::Label::backgroundColourId));

    auto textArea = getLabelBorderSize (label).subtractedFrom (label.getLocalBounds());

    g.setColour (label.findColour (juce::Label::textColourId));
    g.setFont (getLabelFont (label));
    g.drawFittedText (label.getText(), textArea, label.getJustificationType(),
                      juce::jmax (1, (int) ((float) textArea.getHeight() / g.getCurrentFont().getHeight())),
                      label.getMinimumHorizontalScale());
}

// ── Fonts ──

juce::Label* MacStyleLookAndFeel::createComboBoxTextBox (juce::ComboBox&)
{
    auto* label = new juce::Label ({}, {});
    label->setColour (juce::Label::outlineColourId, juce::Colours::transparentBlack);
    label->setColour (juce::Label::outlineWhenEditingColourId, juce::Colours::transparentBlack);
    return label;
}

juce::Font MacStyleLookAndFeel::getComboBoxFont (juce::ComboBox&)
{
    return systemFont;
}

juce::Font MacStyleLookAndFeel::getPopupMenuFont()
{
    return systemFont;
}

juce::Font MacStyleLookAndFeel::getLabelFont (juce::Label& label)
{
    // Respect font already set on the label (for size/bold overrides)
    auto f = label.getFont();
    return f;
}

juce::Font MacStyleLookAndFeel::getTextButtonFont (juce::TextButton&, int)
{
    return systemFont.withHeight (13.0f);
}
