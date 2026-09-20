import Testing
import Foundation
@testable import AuphonicApp

// MARK: - ChannelConfig / Upload Job Tests

struct ChannelConfigTests {

    private func makeConfig(channels: Int, bitDepth: Int = 24) -> ChannelConfig {
        let config = ChannelConfig()
        config.configure(count: channels, trackNames: [], bitDepth: bitDepth)
        return config
    }

    // MARK: Configuration

    @Test func configureCreatesChannelEntries() {
        let config = makeConfig(channels: 5)
        #expect(config.channels.count == 5)
        #expect(config.fileChannelCount == 5)
        #expect(config.allSelected)
    }

    @Test func trackNamesUsedInDisplayNames() {
        let config = ChannelConfig()
        config.configure(count: 3, trackNames: ["Boom", "", "Lav 1"], bitDepth: 24)
        #expect(config.channels[0].displayName == "Ch 1 (Boom)")
        #expect(config.channels[1].displayName == "Ch 2")
        #expect(config.channels[2].displayName == "Ch 3 (Lav 1)")
    }

    // MARK: Upload Jobs — always one mono production per enabled channel

    @Test func everyEnabledChannelBecomesAMonoUpload() {
        let config = makeConfig(channels: 5)
        #expect(config.uploadJobs == [
            UploadJob(channelIndices: [1]),
            UploadJob(channelIndices: [2]),
            UploadJob(channelIndices: [3]),
            UploadJob(channelIndices: [4]),
            UploadJob(channelIndices: [5]),
        ])
    }

    @Test func twoChannelFilesAreAlsoProcessedAsMonoChannels() {
        let config = makeConfig(channels: 2)
        #expect(config.uploadJobs == [
            UploadJob(channelIndices: [1]),
            UploadJob(channelIndices: [2]),
        ])
    }

    @Test func disabledChannelsAreExcluded() {
        let config = makeConfig(channels: 4)
        config.channels[1].enabled = false
        #expect(config.uploadJobs == [
            UploadJob(channelIndices: [1]),
            UploadJob(channelIndices: [3]),
            UploadJob(channelIndices: [4]),
        ])
    }

    @Test func apiCallCountMatchesEnabledChannels() {
        let config = makeConfig(channels: 8)
        #expect(config.apiCallCount == 8)
        config.deselectAll()
        #expect(config.apiCallCount == 0)
    }

    // MARK: Settings

    @Test func settingsForJobForcesWavOutput() {
        let config = makeConfig(channels: 4, bitDepth: 32)
        config.sharedOptions.levelerEnabled = true
        let job = config.uploadJobs[0]
        let settings = config.settingsForJob(job)
        #expect(settings["output_format"] as? String == "wav-24bit")
    }

    @Test func settingsForJobUses16BitFor16BitSource() {
        let config = makeConfig(channels: 3, bitDepth: 16)
        let settings = config.settingsForJob(config.uploadJobs[0])
        #expect(settings["output_format"] as? String == "wav-16bit")
    }

    @Test func unlinkedSettingsUseTheChannelsOwnOptions() {
        let config = makeConfig(channels: 3)
        config.linkedSettings = false
        config.channels[1].options.levelerEnabled = true

        #expect(config.optionsForJob(UploadJob(channelIndices: [2])) === config.channels[1].options)
        #expect(config.optionsForJob(UploadJob(channelIndices: [1])) === config.channels[0].options)
    }

    @Test func presetOnlyUsedWhenLinkedAndUnmodified() {
        let config = makeConfig(channels: 4)
        config.selectedPresetUuid = "abc"
        let job = config.uploadJobs[0]

        #expect(config.presetUuidForJob(job) == "abc")

        config.presetModified = true
        #expect(config.presetUuidForJob(job) == "")

        config.presetModified = false
        config.linkedSettings = false
        #expect(config.presetUuidForJob(job) == "")
    }

    @Test func validConfigurationRequiresPresetOrOptions() {
        let config = makeConfig(channels: 4)
        #expect(!config.hasValidJobConfiguration)

        config.selectedPresetUuid = "abc"
        #expect(config.hasValidJobConfiguration)

        config.selectedPresetUuid = ""
        config.sharedOptions.levelerEnabled = true
        #expect(config.hasValidJobConfiguration)

        config.deselectAll()
        #expect(!config.hasValidJobConfiguration)
    }
}
