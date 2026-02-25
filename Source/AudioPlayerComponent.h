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
    void loadProcessedFile (const juce::File& file);
    void clearProcessedFile();
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
    void abButtonClicked();
    void updateTimeLabel();
    juce::String formatTime (double seconds) const;
    void updatePlayButtonIcon();
    void switchActiveSource();
    void performSourceSwitch();

    juce::AudioTransportSource& getActiveTransport();
    const juce::AudioTransportSource& getActiveTransport() const;
    juce::AudioThumbnail& getActiveThumbnail();

    enum class ActiveSource { Original, Processed };
    ActiveSource activeSource = ActiveSource::Original;

    // Crossfade state for click-free switching
    enum class FadeState { None, FadingOut, FadingIn };
    FadeState fadeState = FadeState::None;
    float fadeGain = 1.0f;
    bool wasPlayingBeforeSwitch = false;
    double switchPosition = 0.0;
    static constexpr float fadeStep = 0.15f; // ~7 steps × 5ms = ~35ms fade

    juce::AudioDeviceManager deviceManager;
    juce::AudioFormatManager formatManager;
    juce::AudioSourcePlayer audioSourcePlayer;

    // Slot A — Original
    juce::AudioTransportSource transportSourceA;
    std::unique_ptr<juce::AudioFormatReaderSource> readerSourceA;
    juce::AudioThumbnailCache thumbnailCacheA { 5 };
    juce::AudioThumbnail thumbnailA { 512, formatManager, thumbnailCacheA };

    // Slot B — Processed
    juce::AudioTransportSource transportSourceB;
    std::unique_ptr<juce::AudioFormatReaderSource> readerSourceB;
    juce::AudioThumbnailCache thumbnailCacheB { 5 };
    juce::AudioThumbnail thumbnailB { 512, formatManager, thumbnailCacheB };

    juce::DrawableButton playButton { "Play", juce::DrawableButton::ImageFitted };
    juce::DrawableButton stopButton { "Stop", juce::DrawableButton::ImageFitted };
    juce::TextButton abButton { "A/B" };
    juce::Label timeLabel;

    bool fileLoaded = false;
    bool processedFileLoaded = false;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR (AudioPlayerComponent)
};
