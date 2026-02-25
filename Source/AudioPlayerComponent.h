#pragma once

#include <juce_gui_basics/juce_gui_basics.h>
#include <juce_audio_basics/juce_audio_basics.h>
#include <juce_audio_devices/juce_audio_devices.h>
#include <juce_audio_formats/juce_audio_formats.h>
#include <juce_audio_utils/juce_audio_utils.h>

class AudioPlayerComponent : public juce::Component,
                              private juce::ChangeListener,
                              private juce::Timer
{
public:
    AudioPlayerComponent();
    ~AudioPlayerComponent() override;

    void loadFile (const juce::File& file);
    void stop();
    bool isPlaying() const;
    bool hasFileLoaded() const { return fileLoaded; }
    void togglePlayPause();
    void setOutputDevice (const juce::String& deviceName);

    void paint (juce::Graphics& g) override;
    void resized() override;
    void mouseDown (const juce::MouseEvent& e) override;

private:
    void changeListenerCallback (juce::ChangeBroadcaster* source) override;
    void timerCallback() override;

    void playButtonClicked();
    void stopButtonClicked();
    void updateTimeLabel();
    juce::String formatTime (double seconds) const;

    juce::AudioDeviceManager deviceManager;
    juce::AudioFormatManager formatManager;
    juce::AudioSourcePlayer audioSourcePlayer;
    juce::AudioTransportSource transportSource;
    std::unique_ptr<juce::AudioFormatReaderSource> readerSource;

    juce::AudioThumbnailCache thumbnailCache { 5 };
    juce::AudioThumbnail thumbnail { 512, formatManager, thumbnailCache };

    juce::DrawableButton playButton { "Play", juce::DrawableButton::ImageFitted };
    juce::DrawableButton stopButton { "Stop", juce::DrawableButton::ImageFitted };
    juce::Label timeLabel;

    void updatePlayButtonIcon();

    bool fileLoaded = false;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR (AudioPlayerComponent)
};
