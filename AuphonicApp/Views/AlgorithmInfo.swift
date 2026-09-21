import Foundation

/// Explanation texts for the Auphonic audio algorithms, taken from the
/// official docs (https://auphonic.com/help/web/production.html#audio-algorithms).
/// Shown in the info popovers next to each algorithm and parameter.
enum AlgorithmInfo {

    // MARK: Adaptive Leveler

    static let leveler = """
    The Adaptive Leveler corrects level differences between speakers, between music and speech, \
    and applies dynamic range compression to achieve a balanced overall loudness. \
    In contrast to loudness normalization, which corrects the loudness of the whole file, \
    the leveler corrects loudness differences between segments within a file.
    """

    static let levelerMode = """
    Default uses one strength and compressor setting for the whole file. \
    Separate Music/Speech applies independent leveling parameters to music and speech segments \
    (detected automatically by the classifier). \
    Broadcast Mode replaces the strength percentage with broadcast loudness parameters \
    (MaxLRA, MaxS, MaxM) so the output complies with delivery specs.
    """

    static let levelerStrength = """
    Controls how much leveling is applied: 100% means full leveling, 0% no leveling at all. \
    Lower values preserve more of the original dynamics — useful for dynamic narration. \
    110% (Fast Leveler) reacts faster and is meant for extreme level differences; \
    120% (Amplify Everything) additionally amplifies quiet non-speech segments.
    """

    static let compressor = """
    Auto switches between Medium (strength ≤ 100%) and Hard (> 100%). \
    Soft applies minimal dynamic range compression, Medium is the default, \
    Hard applies more compression and especially tries to compress short, extreme level overshoots. \
    Off applies mid-term leveling only.
    """

    static let classifier = """
    Restricts leveling to speech or music segments, or levels both with independent parameters. \
    Music and speech segments are detected automatically.
    """

    static let musicGain = """
    Adjusts the volume of music segments relative to speech, from -6 dB to +6 dB.
    """

    static let maxLRA = """
    Maximum Loudness Range: restricts the output loudness range to the given LU value so the \
    audio complies with broadcast specifications. Typical values: news programs 3 LU, \
    talks and discussions 5 LU.
    """

    static let maxShortTerm = """
    Maximum Short-term Loudness: restricts loudness values measured with an integration time \
    of 3 s, relative to the normalization target (in LU).
    """

    static let maxMomentary = """
    Maximum Momentary Loudness: restricts loudness values measured with an integration time \
    of 0.4 s, relative to the normalization target (in LU).
    """

    // MARK: Loudness Normalization

    static let loudness = """
    Adjusts the whole file to a defined loudness target for consistent delivery levels and \
    applies a true peak limiter. Higher targets result in louder audio outputs.
    """

    static let loudnessTarget = """
    Loudness target in LUFS — higher values result in louder outputs. \
    Common targets: -16 LUFS for podcasts and mobile playback, -23 LUFS for EBU R128 broadcast, \
    -24 LUFS for ATSC A/85.
    """

    static let maxPeak = """
    Maximum true peak level in dBTP, enforced by the true peak limiter. \
    Auto selects -1 dBTP for targets of -23 LUFS and above (EBU R128) and \
    -2 dBTP for targets of -24 LUFS and below (ATSC A/85).
    """

    static let dualMono = """
    If a mono production is played back on a stereo system (dual mono), it sounds louder than an \
    equivalent stereo production. This option adds a -3 LU offset for mono files so they sound \
    equally loud: with a -16 LUFS target, stereo files are normalized to -16 LUFS but mono files \
    to -19 LUFS.
    """

    static let loudnessMethod = """
    Program Loudness measures the whole file (broadcast standard). \
    Dialog Loudness measures speech segments only. \
    RMS normalization is used for Audible/ACX compliance.
    """

    // MARK: Filtering

    static let filtering = """
    Adaptive filtering cleans up the frequency spectrum of the recording. \
    Choose the method depending on the material — from a simple context-aware high-pass filter \
    to full voice spectrum optimization.
    """

    static let filteringMethod = """
    Adaptive High-Pass Filtering cuts disturbing low frequencies and interferences, depending on \
    the context. \
    Voice AutoEQ automatically removes sibilance (De-Esser) and plosives (De-Plosive) and \
    optimizes the frequency spectrum of a voice recording. \
    Voice AutoEQ + Bandwidth Extension additionally recovers lost high frequencies in archival \
    or low-bitrate speech recordings — it is optimized for speech and does not enhance music, \
    noise, reverb or other environmental sounds.

    Studio Voice is Auphonic's most extensive voice enhancement model: instead of only \
    filtering the audio it reconstructs a clear, studio-quality voice. It repairs codec and \
    compression artifacts of low-bitrate recordings, distorted or clipped voices from \
    overdriven microphones, recreates missing high frequencies with an improved bandwidth \
    extension model and removes artifacts left by denoisers, text-to-speech or other voice \
    processors. Auphonic labels it beta — the model is still being improved and problems can \
    appear on some recordings, so check the result before using it on a whole batch.
    """

    // MARK: Multitrack

    static let productionMode = """
    Singletrack sends every selected channel to Auphonic as its own production. \
    Each production is billed separately (3 minute minimum each), and the channels are \
    processed completely independently of each other.

    Multitrack sends all selected channels of a file as tracks of ONE production. \
    Auphonic processes every track individually but also analyses them together, which enables \
    crosstalk/mic bleed damping and a combined master. One production per file means one \
    billing minimum per file instead of one per channel.

    Note: Auphonic currently exports the individual tracks of a multitrack production as \
    16-bit audio, while singletrack returns 24-bit.
    """

    static let multitrackMixdown = """
    A multitrack production always returns the processed individual tracks, which are written \
    back into their own channels of the output file. In addition, Auphonic creates a master \
    mixdown of all tracks — enable this to download it as well.
    """

    static let mixdownTarget = """
    Writes the master mixdown into this channel of the output file, replacing its audio. \
    Choose a channel you don't need separately (e.g. a mix track) or leave it unassigned \
    to keep the mixdown out of the file.
    """

    static let multitrackMasterLeveler = """
    The master leveler balances the final mix of all tracks after the individual tracks have \
    been leveled. Broadcast Mode replaces the automatic behaviour with the loudness range \
    parameters MaxLRA, MaxS and MaxM.
    """

    static let multitrackGates = """
    Gating and crosstalk damping are only possible in multitrack productions, because they \
    need all tracks of a recording at once.
    """

    static let multitrackGate = """
    Automatically mutes tracks while their speaker is silent, which removes background noise \
    and room tone from inactive microphones.
    """

    static let multitrackCrossgate = """
    Reduces bleed of other speakers into a microphone: when a voice is only present because it \
    leaks into another mic, that track is attenuated. Very effective for boom and lavalier \
    microphones recorded in the same room.
    """

    // MARK: Noise & Reverb Reduction

    static let denoise = """
    Removes background noise, hum and reverb from speech recordings. \
    The methods differ in what they keep: from removing only stationary technical noise up to \
    isolating pure speech.
    """

    static let denoiseMethod = """
    Static Denoiser removes reverb and stationary, technical noises. \
    Dynamic Denoiser removes everything but voice and music. \
    Speech Isolation keeps only speech — all noise and even music is removed. \
    Classic Denoiser is a spectral subtraction denoiser that needs a short silent segment to \
    extract a noise print; it also offers dehumming.
    """

    static let denoiseAmount = """
    Maximum noise reduction in dB. Auto lets Auphonic decide how much reduction is reasonable, \
    Full applies maximum reduction. Lower values are less aggressive and keep more of the \
    original ambience.
    """

    static let reverbAmount = """
    Maximum reverb reduction in dB. Full applies maximum de-reverberation; \
    lower values keep more of the room sound.
    """

    static let breathAmount = """
    Reduces inhalation and exhalation sounds between words and sentences by the given amount.
    """

    static let dehum = """
    Removes power-line hum and its harmonics (Classic Denoiser only). \
    Auto detects the base frequency; select 50 Hz or 60 Hz to force it.
    """

    static let dehumAmount = """
    Maximum hum reduction in dB. Auto lets Auphonic decide, lower values are less aggressive.
    """
}
