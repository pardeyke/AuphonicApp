#include "AudioPlayerComponent.h"

AudioPlayerComponent::AudioPlayerComponent()
{
    formatManager.registerBasicFormats();

    deviceManager.initialiseWithDefaultDevices (0, 2);
    deviceManager.addAudioCallback (&audioSourcePlayer);
    audioSourcePlayer.setSource (&transportSourceA);

    transportSourceA.addChangeListener (this);
    transportSourceB.addChangeListener (this);
    thumbnailA.addChangeListener (this);
    thumbnailB.addChangeListener (this);

    addAndMakeVisible (playButton);
    addAndMakeVisible (stopButton);
    addAndMakeVisible (abButton);
    addAndMakeVisible (timeLabel);

    playButton.onClick = [this] { playButtonClicked(); };
    stopButton.onClick = [this] { stopButtonClicked(); };
    abButton.onClick   = [this] { abButtonClicked(); };

    playButton.setEnabled (false);
    stopButton.setEnabled (false);
    abButton.setEnabled (false);

    // Set up stop icon (square)
    {
        juce::Path stopPath;
        stopPath.addRectangle (0.0f, 0.0f, 10.0f, 10.0f);

        auto normal = std::make_unique<juce::DrawablePath>();
        normal->setPath (stopPath);
        normal->setFill (juce::Colour (0xffe5e5e5));

        auto disabled = std::make_unique<juce::DrawablePath>();
        disabled->setPath (stopPath);
        disabled->setFill (juce::Colour (0xff555555));

        stopButton.setImages (normal.get(), nullptr, nullptr, disabled.get());
    }

    updatePlayButtonIcon();

    timeLabel.setJustificationType (juce::Justification::centredRight);
    timeLabel.setColour (juce::Label::textColourId, juce::Colour (0xff8e8e93));
    timeLabel.setFont (juce::Font (juce::FontOptions (11.0f)));

    abButton.setColour (juce::TextButton::buttonColourId, juce::Colour (0xff3a3a3a));
    abButton.setColour (juce::TextButton::textColourOffId, juce::Colour (0xffe5e5e5));
}

AudioPlayerComponent::~AudioPlayerComponent()
{
    stopTimer();
    transportSourceA.setSource (nullptr);
    transportSourceB.setSource (nullptr);
    audioSourcePlayer.setSource (nullptr);
    deviceManager.removeAudioCallback (&audioSourcePlayer);
}

void AudioPlayerComponent::loadFile (const juce::File& file)
{
    stop();
    transportSourceA.setSource (nullptr);
    readerSourceA.reset();
    fileLoaded = false;

    // Loading a new original clears any processed file
    clearProcessedFile();
    activeSource = ActiveSource::Original;

    auto* reader = formatManager.createReaderFor (file);
    if (reader != nullptr)
    {
        readerSourceA = std::make_unique<juce::AudioFormatReaderSource> (reader, true);
        transportSourceA.setSource (readerSourceA.get(), 0, nullptr, reader->sampleRate);

        thumbnailA.setSource (new juce::FileInputSource (file));
        fileLoaded = true;
        playButton.setEnabled (true);
        stopButton.setEnabled (true);

        audioSourcePlayer.setSource (&transportSourceA);
    }

    updateTimeLabel();
    repaint();
}

void AudioPlayerComponent::loadProcessedFile (const juce::File& file)
{
    transportSourceB.stop();
    transportSourceB.setSource (nullptr);
    readerSourceB.reset();
    processedFileLoaded = false;

    auto* reader = formatManager.createReaderFor (file);
    if (reader != nullptr)
    {
        readerSourceB = std::make_unique<juce::AudioFormatReaderSource> (reader, true);
        transportSourceB.setSource (readerSourceB.get(), 0, nullptr, reader->sampleRate);

        thumbnailB.setSource (new juce::FileInputSource (file));
        processedFileLoaded = true;
        abButton.setEnabled (true);
    }

    repaint();
}

void AudioPlayerComponent::clearProcessedFile()
{
    transportSourceB.stop();
    transportSourceB.setSource (nullptr);
    readerSourceB.reset();
    thumbnailB.clear();
    processedFileLoaded = false;
    abButton.setEnabled (false);

    if (activeSource == ActiveSource::Processed)
    {
        activeSource = ActiveSource::Original;
        audioSourcePlayer.setSource (&transportSourceA);
    }

    repaint();
}

void AudioPlayerComponent::stop()
{
    auto& transport = getActiveTransport();
    if (transport.isPlaying())
        transport.stop();

    transportSourceA.setPosition (0.0);
    if (processedFileLoaded)
        transportSourceB.setPosition (0.0);

    stopTimer();
    updatePlayButtonIcon();
    updateTimeLabel();
    repaint();
}

bool AudioPlayerComponent::isPlaying() const
{
    return getActiveTransport().isPlaying();
}

juce::AudioTransportSource& AudioPlayerComponent::getActiveTransport()
{
    return activeSource == ActiveSource::Original ? transportSourceA : transportSourceB;
}

const juce::AudioTransportSource& AudioPlayerComponent::getActiveTransport() const
{
    return activeSource == ActiveSource::Original ? transportSourceA : transportSourceB;
}

juce::AudioThumbnail& AudioPlayerComponent::getActiveThumbnail()
{
    return activeSource == ActiveSource::Original ? thumbnailA : thumbnailB;
}

void AudioPlayerComponent::paint (juce::Graphics& g)
{
    auto bounds = getLocalBounds();
    auto controlHeight = 26;
    auto waveformTotalHeight = bounds.getHeight() - controlHeight;
    auto waveformHalfHeight = waveformTotalHeight / 2;

    auto waveformAreaA = bounds.removeFromTop (waveformHalfHeight).reduced (0, 1);
    auto waveformAreaB = bounds.removeFromTop (waveformTotalHeight - waveformHalfHeight).reduced (0, 1);

    bool isActiveA = (activeSource == ActiveSource::Original);
    bool isActiveB = (activeSource == ActiveSource::Processed);

    // --- Draw Original waveform (A) ---
    {
        g.setColour (juce::Colour (0xff2a2a2a));
        g.fillRoundedRectangle (waveformAreaA.toFloat(), 4.0f);

        if (isActiveA)
        {
            g.setColour (juce::Colour (0xff007aff).withAlpha (0.3f));
            g.drawRoundedRectangle (waveformAreaA.toFloat().reduced (0.5f), 4.0f, 1.0f);
        }

        if (fileLoaded && thumbnailA.getTotalLength() > 0.0)
        {
            float alpha = isActiveA ? 0.7f : 0.3f;
            g.setColour (juce::Colour (0xff007aff).withAlpha (alpha));
            thumbnailA.drawChannels (g, waveformAreaA.reduced (2), 0.0, thumbnailA.getTotalLength(), 1.0f);

            if (isActiveA)
            {
                auto currentPos = transportSourceA.getCurrentPosition();
                auto totalLen = transportSourceA.getLengthInSeconds();
                if (totalLen > 0.0)
                {
                    auto proportion = currentPos / totalLen;
                    auto xPos = waveformAreaA.getX() + 2 + (int) ((waveformAreaA.getWidth() - 4) * proportion);
                    g.setColour (juce::Colour (0xffe5e5e5));
                    g.drawVerticalLine (xPos, (float) waveformAreaA.getY(), (float) waveformAreaA.getBottom());
                }
            }
        }
        else
        {
            g.setColour (juce::Colour (0xff8e8e93));
            g.setFont (juce::Font (juce::FontOptions (12.0f)));
            g.drawText ("No audio loaded", waveformAreaA, juce::Justification::centred);
        }

        // Label
        g.setColour (juce::Colour (isActiveA ? 0xffe5e5e5 : 0xff8e8e93));
        g.setFont (juce::Font (juce::FontOptions (10.0f)));
        g.drawText ("Original", waveformAreaA.reduced (6, 2), juce::Justification::topLeft);
    }

    // --- Draw Processed waveform (B) ---
    {
        g.setColour (juce::Colour (0xff2a2a2a));
        g.fillRoundedRectangle (waveformAreaB.toFloat(), 4.0f);

        if (isActiveB)
        {
            g.setColour (juce::Colour (0xff007aff).withAlpha (0.3f));
            g.drawRoundedRectangle (waveformAreaB.toFloat().reduced (0.5f), 4.0f, 1.0f);
        }

        if (processedFileLoaded && thumbnailB.getTotalLength() > 0.0)
        {
            float alpha = isActiveB ? 0.7f : 0.3f;
            g.setColour (juce::Colour (0xff007aff).withAlpha (alpha));
            thumbnailB.drawChannels (g, waveformAreaB.reduced (2), 0.0, thumbnailB.getTotalLength(), 1.0f);

            if (isActiveB)
            {
                auto currentPos = transportSourceB.getCurrentPosition();
                auto totalLen = transportSourceB.getLengthInSeconds();
                if (totalLen > 0.0)
                {
                    auto proportion = currentPos / totalLen;
                    auto xPos = waveformAreaB.getX() + 2 + (int) ((waveformAreaB.getWidth() - 4) * proportion);
                    g.setColour (juce::Colour (0xffe5e5e5));
                    g.drawVerticalLine (xPos, (float) waveformAreaB.getY(), (float) waveformAreaB.getBottom());
                }
            }
        }
        else
        {
            g.setColour (juce::Colour (0xff555555));
            g.setFont (juce::Font (juce::FontOptions (12.0f)));
            g.drawText ("No processed audio", waveformAreaB, juce::Justification::centred);
        }

        // Label
        g.setColour (juce::Colour (isActiveB ? 0xffe5e5e5 : 0xff8e8e93));
        g.setFont (juce::Font (juce::FontOptions (10.0f)));
        g.drawText ("Processed", waveformAreaB.reduced (6, 2), juce::Justification::topLeft);
    }
}

void AudioPlayerComponent::resized()
{
    auto area = getLocalBounds();
    auto controlArea = area.removeFromBottom (26);

    playButton.setBounds (controlArea.removeFromLeft (30));
    controlArea.removeFromLeft (4);
    stopButton.setBounds (controlArea.removeFromLeft (30));
    controlArea.removeFromLeft (4);
    abButton.setBounds (controlArea.removeFromLeft (36));
    timeLabel.setBounds (controlArea);
}

void AudioPlayerComponent::togglePlayPause()
{
    playButtonClicked();
}

void AudioPlayerComponent::mouseDown (const juce::MouseEvent& e)
{
    auto bounds = getLocalBounds();
    auto controlHeight = 26;
    auto waveformTotalHeight = bounds.getHeight() - controlHeight;
    auto waveformHalfHeight = waveformTotalHeight / 2;

    auto waveformAreaA = juce::Rectangle<int> (bounds.getX(), bounds.getY(), bounds.getWidth(), waveformHalfHeight).reduced (0, 1);
    auto waveformAreaB = juce::Rectangle<int> (bounds.getX(), bounds.getY() + waveformHalfHeight, bounds.getWidth(), waveformTotalHeight - waveformHalfHeight).reduced (0, 1);

    auto pos = e.getPosition();

    // Click on inactive waveform → switch source
    if (waveformAreaA.contains (pos) && activeSource == ActiveSource::Processed && fileLoaded)
    {
        switchActiveSource();
        return;
    }
    if (waveformAreaB.contains (pos) && activeSource == ActiveSource::Original && processedFileLoaded)
    {
        switchActiveSource();
        return;
    }

    // Click on active waveform → seek
    auto& activeArea = (activeSource == ActiveSource::Original) ? waveformAreaA : waveformAreaB;
    auto& transport = getActiveTransport();
    bool loaded = (activeSource == ActiveSource::Original) ? fileLoaded : processedFileLoaded;

    if (loaded && activeArea.contains (pos))
    {
        auto clickX = pos.getX() - activeArea.getX();
        auto proportion = juce::jlimit (0.0, 1.0, (double) clickX / activeArea.getWidth());
        transport.setPosition (proportion * transport.getLengthInSeconds());
        repaint();
    }
}

void AudioPlayerComponent::changeListenerCallback (juce::ChangeBroadcaster* source)
{
    if (source == &transportSourceA || source == &transportSourceB)
    {
        auto& transport = getActiveTransport();

        if (! transport.isPlaying() && transport.getCurrentPosition() >= transport.getLengthInSeconds() - 0.05)
        {
            transport.setPosition (0.0);
            stopTimer();
        }

        updatePlayButtonIcon();
        updateTimeLabel();
        repaint();
    }
    else if (source == &thumbnailA || source == &thumbnailB)
    {
        repaint();
    }
}

void AudioPlayerComponent::timerCallback()
{
    if (fadeState == FadeState::FadingOut)
    {
        fadeGain -= fadeStep;
        if (fadeGain <= 0.0f)
        {
            fadeGain = 0.0f;
            getActiveTransport().setGain (0.0f);
            performSourceSwitch();
            fadeState = FadeState::FadingIn;
        }
        else
        {
            getActiveTransport().setGain (fadeGain);
        }
        return;
    }

    if (fadeState == FadeState::FadingIn)
    {
        fadeGain += fadeStep;
        if (fadeGain >= 1.0f)
        {
            fadeGain = 1.0f;
            getActiveTransport().setGain (1.0f);
            fadeState = FadeState::None;

            // Restore normal timer rate
            if (wasPlayingBeforeSwitch)
                startTimerHz (30);
            else
                stopTimer();
        }
        else
        {
            getActiveTransport().setGain (fadeGain);
        }
        repaint();
        return;
    }

    updateTimeLabel();
    repaint();
}

void AudioPlayerComponent::playButtonClicked()
{
    bool loaded = (activeSource == ActiveSource::Original) ? fileLoaded : processedFileLoaded;
    if (! loaded)
        return;

    auto& transport = getActiveTransport();

    if (transport.isPlaying())
    {
        transport.stop();
        stopTimer();
    }
    else
    {
        transport.start();
        startTimerHz (30);
    }

    updatePlayButtonIcon();
    updateTimeLabel();
}

void AudioPlayerComponent::updatePlayButtonIcon()
{
    if (getActiveTransport().isPlaying())
    {
        juce::Path pausePath;
        pausePath.addRectangle (0.0f, 0.0f, 3.0f, 10.0f);
        pausePath.addRectangle (5.0f, 0.0f, 3.0f, 10.0f);

        auto normal = std::make_unique<juce::DrawablePath>();
        normal->setPath (pausePath);
        normal->setFill (juce::Colour (0xffe5e5e5));

        playButton.setImages (normal.get());
    }
    else
    {
        juce::Path playPath;
        playPath.addTriangle (0.0f, 0.0f, 0.0f, 10.0f, 8.66f, 5.0f);

        auto normal = std::make_unique<juce::DrawablePath>();
        normal->setPath (playPath);
        normal->setFill (juce::Colour (0xffe5e5e5));

        auto disabled = std::make_unique<juce::DrawablePath>();
        disabled->setPath (playPath);
        disabled->setFill (juce::Colour (0xff555555));

        playButton.setImages (normal.get(), nullptr, nullptr, disabled.get());
    }
}

void AudioPlayerComponent::stopButtonClicked()
{
    stop();
}

void AudioPlayerComponent::abButtonClicked()
{
    if (! processedFileLoaded)
        return;

    switchActiveSource();
}

void AudioPlayerComponent::switchActiveSource()
{
    if (fadeState != FadeState::None)
        return; // already mid-fade

    wasPlayingBeforeSwitch = getActiveTransport().isPlaying();
    switchPosition = getActiveTransport().getCurrentPosition();

    fadeGain = 1.0f;
    fadeState = FadeState::FadingOut;

    // High-rate timer for smooth ~35ms fade (200 Hz × ~7 steps)
    startTimerHz (200);
}

void AudioPlayerComponent::performSourceSwitch()
{
    if (wasPlayingBeforeSwitch)
        getActiveTransport().stop();

    // Toggle
    activeSource = (activeSource == ActiveSource::Original) ? ActiveSource::Processed : ActiveSource::Original;

    // Wire audio output to new active transport
    getActiveTransport().setGain (0.0f);
    audioSourcePlayer.setSource (&getActiveTransport());
    getActiveTransport().setPosition (switchPosition);

    if (wasPlayingBeforeSwitch)
        getActiveTransport().start();

    updatePlayButtonIcon();
    updateTimeLabel();
    repaint();
}

void AudioPlayerComponent::updateTimeLabel()
{
    bool loaded = (activeSource == ActiveSource::Original) ? fileLoaded : processedFileLoaded;
    if (! loaded)
    {
        timeLabel.setText ("", juce::dontSendNotification);
        return;
    }

    auto& transport = getActiveTransport();
    auto current = transport.getCurrentPosition();
    auto total = transport.getLengthInSeconds();
    timeLabel.setText (formatTime (current) + " / " + formatTime (total),
                       juce::dontSendNotification);
}

juce::String AudioPlayerComponent::formatTime (double seconds) const
{
    int mins = (int) seconds / 60;
    int secs = (int) seconds % 60;
    return juce::String::formatted ("%d:%02d", mins, secs);
}

void AudioPlayerComponent::setOutputDevice (const juce::String& deviceName)
{
    if (deviceName.isEmpty())
    {
        deviceManager.initialiseWithDefaultDevices (0, 2);
        return;
    }

    auto* currentType = deviceManager.getCurrentDeviceTypeObject();
    if (currentType != nullptr)
    {
        juce::AudioDeviceManager::AudioDeviceSetup setup;
        deviceManager.getAudioDeviceSetup (setup);
        setup.outputDeviceName = deviceName;
        deviceManager.setAudioDeviceSetup (setup, true);
    }
}
