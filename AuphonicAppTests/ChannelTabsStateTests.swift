import Testing
import Foundation
@testable import AuphonicApp

struct ChannelConfigTests {

    // MARK: - configure

    @Test func configureStereo() {
        let config = ChannelConfig()
        config.configure(count: 2, trackNames: [], bitDepth: 24)

        #expect(config.channels.count == 2)
        #expect(config.channels[0].displayName == "Ch 1 (Left)")
        #expect(config.channels[1].displayName == "Ch 2 (Right)")
        #expect(config.fileChannelCount == 2)
        #expect(config.stereoMode == true)
    }

    @Test func configureWithTrackNames() {
        let config = ChannelConfig()
        config.configure(count: 4, trackNames: ["Boom", "Lav1", "Lav2", "Mix"], bitDepth: 24)

        #expect(config.channels[0].displayName == "Ch 1 (Boom)")
        #expect(config.channels[1].displayName == "Ch 2 (Lav1)")
        #expect(config.channels[2].displayName == "Ch 3 (Lav2)")
        #expect(config.channels[3].displayName == "Ch 4 (Mix)")
        #expect(config.stereoMode == false)
    }

    @Test func configureWithPartialTrackNames() {
        let config = ChannelConfig()
        config.configure(count: 4, trackNames: ["Boom", ""], bitDepth: 24)

        #expect(config.channels[0].displayName == "Ch 1 (Boom)")
        #expect(config.channels[1].displayName == "Ch 2")
        #expect(config.channels[2].displayName == "Ch 3")
        #expect(config.channels[3].displayName == "Ch 4")
    }

    @Test func configureMono() {
        let config = ChannelConfig()
        config.configure(count: 1, trackNames: [], bitDepth: 16)

        #expect(config.channels.count == 1)
        #expect(config.channels[0].displayName == "Ch 1")
    }

    @Test func configureForces16BitWav() {
        let config = ChannelConfig()
        config.configure(count: 2, trackNames: [], bitDepth: 16)

        #expect(config.sharedOptions.forcedOutputFormat == "wav-16bit")
        #expect(config.sharedOptions.outputFormat == .wav16)
        #expect(config.channels[0].options.forcedOutputFormat == "wav-16bit")
    }

    @Test func configureForces24BitWav() {
        let config = ChannelConfig()
        config.configure(count: 2, trackNames: [], bitDepth: 24)

        #expect(config.sharedOptions.forcedOutputFormat == "wav-24bit")
        #expect(config.sharedOptions.outputFormat == .wav24)
    }

    // MARK: - Processing Modes

    @Test func monoFileIsWholeFileMode() {
        let config = ChannelConfig()
        config.configure(count: 1, trackNames: [], bitDepth: 24)

        #expect(config.isWholeFileMode)
        #expect(!config.showsModeToggle)
        #expect(!config.showsChannelList)
    }

    @Test func stereoModeIsWholeFileMode() {
        let config = ChannelConfig()
        config.configure(count: 2, trackNames: [], bitDepth: 24)
        config.stereoMode = true

        #expect(config.isWholeFileMode)
        #expect(config.showsModeToggle)
        #expect(!config.showsChannelList)
    }

    @Test func multiMonoIsNotWholeFileMode() {
        let config = ChannelConfig()
        config.configure(count: 2, trackNames: [], bitDepth: 24)
        config.stereoMode = false

        #expect(!config.isWholeFileMode)
        #expect(config.showsModeToggle)
        #expect(config.showsChannelList)
    }

    @Test func multiChannelAlwaysShowsChannelList() {
        let config = ChannelConfig()
        config.configure(count: 4, trackNames: [], bitDepth: 24)

        #expect(!config.isWholeFileMode)
        #expect(!config.showsModeToggle)
        #expect(config.showsChannelList)
    }

    // MARK: - Processing Jobs

    @Test func wholeFileJobForStereoMode() {
        let config = ChannelConfig()
        config.configure(count: 2, trackNames: [], bitDepth: 24)
        config.stereoMode = true

        let jobs = config.processingJobs
        #expect(jobs.count == 1)
        #expect(jobs[0].isWholeFile)
    }

    @Test func monoJobsForMultiMono() {
        let config = ChannelConfig()
        config.configure(count: 3, trackNames: [], bitDepth: 24)
        // All channels enabled by default

        let jobs = config.processingJobs
        #expect(jobs.count == 3)
        #expect(jobs[0].channelIndices == [1])
        #expect(jobs[1].channelIndices == [2])
        #expect(jobs[2].channelIndices == [3])
    }

    @Test func disabledChannelsExcluded() {
        let config = ChannelConfig()
        config.configure(count: 4, trackNames: [], bitDepth: 24)
        config.channels[1].enabled = false
        config.channels[3].enabled = false

        let jobs = config.processingJobs
        #expect(jobs.count == 2)
        #expect(jobs[0].channelIndices == [1])
        #expect(jobs[1].channelIndices == [3])
    }

    // MARK: - Stereo Pairing

    @Test func linkStereoPair() {
        let config = ChannelConfig()
        config.configure(count: 4, trackNames: [], bitDepth: 24)

        config.linkStereo(ch1: 0, ch2: 1)

        #expect(config.channels[0].stereoPairPartner == 1)
        #expect(config.channels[1].stereoPairPartner == 0)

        let jobs = config.processingJobs
        let stereoJobs = jobs.filter(\.isStereo)
        #expect(stereoJobs.count == 1)
        #expect(stereoJobs[0].channelIndices == [1, 2]) // 1-based
    }

    @Test func unlinkStereoPair() {
        let config = ChannelConfig()
        config.configure(count: 4, trackNames: [], bitDepth: 24)

        config.linkStereo(ch1: 0, ch2: 1)
        config.unlinkStereo(ch: 0)

        #expect(config.channels[0].stereoPairPartner == nil)
        #expect(config.channels[1].stereoPairPartner == nil)
    }

    @Test func stereoPairCountsAsOneApiCall() {
        let config = ChannelConfig()
        config.configure(count: 4, trackNames: [], bitDepth: 24)

        config.linkStereo(ch1: 2, ch2: 3)
        // Channels 0, 1 = 2 mono jobs; Channels 2+3 = 1 stereo job
        #expect(config.apiCallCount == 3)
    }

    // MARK: - Selection

    @Test func selectAll() {
        let config = ChannelConfig()
        config.configure(count: 4, trackNames: [], bitDepth: 24)
        config.deselectAll()
        #expect(config.enabledChannelCount == 0)

        config.selectAll()
        #expect(config.enabledChannelCount == 4)
        #expect(config.allSelected)
    }

    // MARK: - Merge

    @Test func mergeNotAvailableForStereoMode() {
        let config = ChannelConfig()
        config.configure(count: 2, trackNames: [], bitDepth: 24)
        config.stereoMode = true

        #expect(!config.mergeAvailable)
    }

    @Test func mergeAvailableForMultiMono() {
        let config = ChannelConfig()
        config.configure(count: 4, trackNames: [], bitDepth: 24)

        #expect(config.mergeAvailable)
    }

    @Test func mergeNotAvailableForSingleChannel() {
        let config = ChannelConfig()
        config.configure(count: 4, trackNames: [], bitDepth: 24)
        config.deselectAll()
        config.channels[0].enabled = true

        #expect(!config.mergeAvailable)
    }

    // MARK: - API Call Count

    @Test func apiCallCountForStereoMode() {
        let config = ChannelConfig()
        config.configure(count: 2, trackNames: [], bitDepth: 24)
        config.stereoMode = true

        #expect(config.apiCallCount == 1)
    }

    @Test func apiCallCountForMultiMono() {
        let config = ChannelConfig()
        config.configure(count: 4, trackNames: [], bitDepth: 24)

        #expect(config.apiCallCount == 4)
    }

    @Test func apiCallCountWithPairs() {
        let config = ChannelConfig()
        config.configure(count: 6, trackNames: [], bitDepth: 24)
        config.linkStereo(ch1: 0, ch2: 1)
        config.linkStereo(ch1: 4, ch2: 5)
        // 2 stereo pairs (2 calls) + 2 mono (2 calls) = 4
        #expect(config.apiCallCount == 4)
    }
}
