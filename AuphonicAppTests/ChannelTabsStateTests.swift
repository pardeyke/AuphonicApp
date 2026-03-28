import Testing
import Foundation
@testable import AuphonicApp

struct ChannelTabsStateTests {

    // MARK: - setChannels

    @Test func setChannelsStereo() {
        let state = ChannelTabsState()
        state.setChannels(count: 2, trackNames: [], bitDepth: 24)

        #expect(state.channelNames.count == 2)
        #expect(state.channelNames[0] == "Ch 1 (Left)")
        #expect(state.channelNames[1] == "Ch 2 (Right)")
        #expect(state.channelOptions.count == 2)
        #expect(state.selectedTab == 0)
    }

    @Test func setChannelsWithTrackNames() {
        let state = ChannelTabsState()
        state.setChannels(count: 4, trackNames: ["Boom", "Lav1", "Lav2", "Mix"], bitDepth: 24)

        #expect(state.channelNames[0] == "Ch 1 (Boom)")
        #expect(state.channelNames[1] == "Ch 2 (Lav1)")
        #expect(state.channelNames[2] == "Ch 3 (Lav2)")
        #expect(state.channelNames[3] == "Ch 4 (Mix)")
    }

    @Test func setChannelsWithPartialTrackNames() {
        let state = ChannelTabsState()
        state.setChannels(count: 4, trackNames: ["Boom", ""], bitDepth: 24)

        #expect(state.channelNames[0] == "Ch 1 (Boom)")
        #expect(state.channelNames[1] == "Ch 2")
        #expect(state.channelNames[2] == "Ch 3")
        #expect(state.channelNames[3] == "Ch 4")
    }

    @Test func setChannelsMono() {
        let state = ChannelTabsState()
        state.setChannels(count: 1, trackNames: [], bitDepth: 16)

        #expect(state.channelNames.count == 1)
        #expect(state.channelNames[0] == "Ch 1")
        #expect(state.channelOptions.count == 1)
    }

    @Test func setChannelsForces16BitWav() {
        let state = ChannelTabsState()
        state.setChannels(count: 2, trackNames: [], bitDepth: 16)

        #expect(state.channelOptions[0].forcedOutputFormat == "wav-16bit")
        #expect(state.channelOptions[0].outputFormat == .wav16)
        #expect(state.channelOptions[0].isPerChannelMode)
    }

    @Test func setChannelsForces24BitWav() {
        let state = ChannelTabsState()
        state.setChannels(count: 2, trackNames: [], bitDepth: 24)

        #expect(state.channelOptions[0].forcedOutputFormat == "wav-24bit")
        #expect(state.channelOptions[0].outputFormat == .wav24)
    }

    @Test func setChannelsResetsSelectedTab() {
        let state = ChannelTabsState()
        state.selectedTab = 5
        state.setChannels(count: 2, trackNames: [], bitDepth: 24)
        #expect(state.selectedTab == 0)
    }

    // MARK: - enabledChannelCount

    @Test func enabledChannelCountNone() {
        let state = ChannelTabsState()
        state.setChannels(count: 3, trackNames: [], bitDepth: 24)

        // Default: all have outputFormatEnabled=true so hasAnyEnabled() returns true
        // Disable all
        for opts in state.channelOptions {
            opts.outputFormatEnabled = false
        }
        #expect(state.enabledChannelCount == 0)
    }

    @Test func enabledChannelCountSome() {
        let state = ChannelTabsState()
        state.setChannels(count: 4, trackNames: [], bitDepth: 24)

        // All have outputFormatEnabled by default
        state.channelOptions[0].outputFormatEnabled = false
        state.channelOptions[2].outputFormatEnabled = false

        #expect(state.enabledChannelCount == 2)
    }

    // MARK: - hasAnyChannelEnabled

    @Test func hasAnyChannelEnabledTrue() {
        let state = ChannelTabsState()
        state.setChannels(count: 2, trackNames: [], bitDepth: 24)
        // Default has outputFormatEnabled = true
        #expect(state.hasAnyChannelEnabled)
    }

    @Test func hasAnyChannelEnabledFalse() {
        let state = ChannelTabsState()
        state.setChannels(count: 2, trackNames: [], bitDepth: 24)
        for opts in state.channelOptions {
            opts.outputFormatEnabled = false
        }
        #expect(!state.hasAnyChannelEnabled)
    }

    // MARK: - getEnabledChannelSettings

    @Test func getEnabledChannelSettings() {
        let state = ChannelTabsState()
        state.setChannels(count: 3, trackNames: [], bitDepth: 24)

        // Enable leveler on channel 1
        state.channelOptions[0].levelerEnabled = true
        // Channel 2 has only outputFormatEnabled (default)
        // Disable channel 3 entirely
        state.channelOptions[2].outputFormatEnabled = false

        let settings = state.getEnabledChannelSettings()
        #expect(settings.count == 2)
        #expect(settings[0].channel == 1)
        #expect(settings[1].channel == 2)
    }

    @Test func getEnabledChannelSettingsForcesWavOutput() {
        let state = ChannelTabsState()
        state.setChannels(count: 2, trackNames: [], bitDepth: 24)

        let settings = state.getEnabledChannelSettings()
        for s in settings {
            #expect(s.settings["output_format"] as? String == "wav-24bit")
            let outputFiles = s.settings["output_files"] as? [[String: Any]]
            #expect(outputFiles?.first?["format"] as? String == "wav-24bit")
        }
    }

    @Test func getEnabledChannelSettingsPresetUuidIsEmpty() {
        let state = ChannelTabsState()
        state.setChannels(count: 2, trackNames: [], bitDepth: 24)

        let settings = state.getEnabledChannelSettings()
        for s in settings {
            #expect(s.presetUuid == "")
        }
    }
}
