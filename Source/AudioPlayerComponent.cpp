#include "AudioPlayerComponent.h"

AudioPlayerComponent::AudioPlayerComponent()
{
    formatManager.registerBasicFormats();

    deviceManager.initialiseWithDefaultDevices (0, 2);
    deviceManager.addAudioCallback (&audioSourcePlayer);
    audioSourcePlayer.setSource (&transportSource);

    transportSource.addChangeListener (this);
    thumbnail.addChangeListener (this);

    addAndMakeVisible (playButton);
    addAndMakeVisible (stopButton);
    addAndMakeVisible (timeLabel);

    playButton.onClick = [this] { playButtonClicked(); };
    stopButton.onClick = [this] { stopButtonClicked(); };

    playButton.setEnabled (false);
    stopButton.setEnabled (false);

    timeLabel.setJustificationType (juce::Justification::centredRight);
    timeLabel.setColour (juce::Label::textColourId, juce::Colour (0xff8e8e93));
    timeLabel.setFont (juce::Font (juce::FontOptions (11.0f)));
}

AudioPlayerComponent::~AudioPlayerComponent()
{
    stopTimer();
    transportSource.setSource (nullptr);
    audioSourcePlayer.setSource (nullptr);
    deviceManager.removeAudioCallback (&audioSourcePlayer);
}

void AudioPlayerComponent::loadFile (const juce::File& file)
{
    stop();
    transportSource.setSource (nullptr);
    readerSource.reset();
    fileLoaded = false;

    auto* reader = formatManager.createReaderFor (file);
    if (reader != nullptr)
    {
        readerSource = std::make_unique<juce::AudioFormatReaderSource> (reader, true);
        transportSource.setSource (readerSource.get(), 0, nullptr, reader->sampleRate);

        thumbnail.setSource (new juce::FileInputSource (file));
        fileLoaded = true;
        playButton.setEnabled (true);
        stopButton.setEnabled (true);
    }

    updateTimeLabel();
    repaint();
}

void AudioPlayerComponent::stop()
{
    if (transportSource.isPlaying())
        transportSource.stop();

    transportSource.setPosition (0.0);
    stopTimer();
    updateTimeLabel();
    repaint();
}

bool AudioPlayerComponent::isPlaying() const
{
    return transportSource.isPlaying();
}

void AudioPlayerComponent::paint (juce::Graphics& g)
{
    auto waveformArea = getLocalBounds().removeFromTop (getHeight() - 30).reduced (0, 2);

    // Waveform background
    g.setColour (juce::Colour (0xff2a2a2a));
    g.fillRoundedRectangle (waveformArea.toFloat(), 4.0f);

    if (fileLoaded && thumbnail.getTotalLength() > 0.0)
    {
        // Draw waveform
        g.setColour (juce::Colour (0xff007aff).withAlpha (0.7f));
        thumbnail.drawChannels (g, waveformArea.reduced (2), 0.0, thumbnail.getTotalLength(), 1.0f);

        // Draw playback position line
        auto currentPos = transportSource.getCurrentPosition();
        auto totalLen = transportSource.getLengthInSeconds();
        if (totalLen > 0.0)
        {
            auto proportion = currentPos / totalLen;
            auto xPos = waveformArea.getX() + 2 + (int) ((waveformArea.getWidth() - 4) * proportion);

            g.setColour (juce::Colour (0xffe5e5e5));
            g.drawVerticalLine (xPos, (float) waveformArea.getY(), (float) waveformArea.getBottom());
        }
    }
    else
    {
        // Empty state
        g.setColour (juce::Colour (0xff8e8e93));
        g.setFont (juce::Font (juce::FontOptions (12.0f)));
        g.drawText ("No audio loaded", waveformArea, juce::Justification::centred);
    }
}

void AudioPlayerComponent::resized()
{
    auto area = getLocalBounds();
    auto controlArea = area.removeFromBottom (26);

    playButton.setBounds (controlArea.removeFromLeft (60));
    controlArea.removeFromLeft (4);
    stopButton.setBounds (controlArea.removeFromLeft (60));
    timeLabel.setBounds (controlArea);
}

void AudioPlayerComponent::mouseDown (const juce::MouseEvent& e)
{
    auto waveformArea = getLocalBounds().removeFromTop (getHeight() - 30).reduced (2, 2);

    if (fileLoaded && waveformArea.contains (e.getPosition()))
    {
        auto clickX = e.getPosition().getX() - waveformArea.getX();
        auto proportion = juce::jlimit (0.0, 1.0, (double) clickX / waveformArea.getWidth());
        transportSource.setPosition (proportion * transportSource.getLengthInSeconds());
        repaint();
    }
}

void AudioPlayerComponent::changeListenerCallback (juce::ChangeBroadcaster* source)
{
    if (source == &transportSource)
    {
        if (! transportSource.isPlaying() && transportSource.getCurrentPosition() >= transportSource.getLengthInSeconds() - 0.05)
        {
            // Playback finished naturally
            transportSource.setPosition (0.0);
            stopTimer();
        }

        updateTimeLabel();
        repaint();
    }
    else if (source == &thumbnail)
    {
        repaint();
    }
}

void AudioPlayerComponent::timerCallback()
{
    updateTimeLabel();
    repaint();
}

void AudioPlayerComponent::playButtonClicked()
{
    if (! fileLoaded)
        return;

    if (transportSource.isPlaying())
    {
        transportSource.stop();
        stopTimer();
    }
    else
    {
        transportSource.start();
        startTimerHz (30);
    }

    updateTimeLabel();
}

void AudioPlayerComponent::stopButtonClicked()
{
    stop();
}

void AudioPlayerComponent::updateTimeLabel()
{
    if (! fileLoaded)
    {
        timeLabel.setText ("", juce::dontSendNotification);
        return;
    }

    auto current = transportSource.getCurrentPosition();
    auto total = transportSource.getLengthInSeconds();
    timeLabel.setText (formatTime (current) + " / " + formatTime (total),
                       juce::dontSendNotification);
}

juce::String AudioPlayerComponent::formatTime (double seconds) const
{
    int mins = (int) seconds / 60;
    int secs = (int) seconds % 60;
    return juce::String::formatted ("%d:%02d", mins, secs);
}
