import SwiftUI
import AVFoundation

/// Mini multitrack player: one waveform lane per channel of the selected take,
/// with mute/solo per lane, a shared playhead and a Liquid Glass transport.
struct MultitrackPlayerView: View {
    @Bindable var player: AudioPlayerService

    @State private var zoom: CGFloat = 1
    @State private var magnifyBaseZoom: CGFloat?
    @State private var scrollPosition = ScrollPosition(edge: .leading)

    // Geometry needed to keep a point fixed while zooming
    @State private var scrollX: CGFloat = 0
    @State private var lastViewWidth: CGFloat = 1
    @State private var cursorX: CGFloat?

    private let maxZoom: CGFloat = 64
    private let laneHeight: CGFloat = 46
    private let headerWidth: CGFloat = 116

    private var slot: AudioPlayerService.Slot { player.activeSlot }

    private var channelCount: Int {
        slot == .original ? player.channelCountA : player.channelCountB
    }

    private var trackNames: [String] {
        slot == .original ? player.trackNamesA : player.trackNamesB
    }

    private var slotDuration: TimeInterval {
        slot == .original ? player.originalDuration : player.processedDuration
    }

    private var anySoloed: Bool {
        (1...max(1, channelCount)).contains { player.isChannelSoloed(slot: slot, channel: $0) }
    }

    var body: some View {
        VStack(spacing: 8) {
            transportBar
            trackLanes
        }
    }

    // MARK: - Transport

    private var transportBar: some View {
        HStack(spacing: 12) {
            Button {
                player.togglePlayPause()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!player.hasOriginal)

            // Position
            VStack(alignment: .leading, spacing: 1) {
                if let timecode = player.currentTimecodeString {
                    Text(timecode)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                } else {
                    Text(formatTime(player.currentTime))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }

                Text("\(formatTime(player.currentTime)) / \(formatTime(slotDuration))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            // A/B between the original and the processed result
            if player.hasProcessed {
                TabsSegmentedControl(
                    values: AudioPlayerService.Slot.allCases,
                    titles: AudioPlayerService.Slot.allCases.map(\.displayName),
                    selection: Binding(
                        get: { player.activeSlot },
                        set: { player.switchTo($0) }
                    ),
                    controlSize: .regular,
                    height: 34
                )
                .fixedSize()
            }

            if anySoloed {
                Button("Clear Solo") {
                    player.clearMixerState(slot: slot)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.yellow)
            }

            // Zoom — buttons zoom around the middle of the visible window
            HStack(spacing: 6) {
                Button {
                    setZoom(max(1, zoom / 2), anchorX: lastViewWidth / 2)
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .buttonStyle(.plain)
                .disabled(zoom <= 1)

                Button {
                    setZoom(min(maxZoom, zoom * 2), anchorX: lastViewWidth / 2)
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .buttonStyle(.plain)
                .disabled(zoom >= maxZoom)
            }
            .disabled(!player.hasOriginal)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }

    // MARK: - Lanes

    private var trackLanes: some View {
        GeometryReader { geo in
            let laneWidth = max(geo.size.width - headerWidth, 1)
            let contentWidth = max(laneWidth * zoom, 1)

            HStack(spacing: 0) {
                // Channel strips
                VStack(spacing: 6) {
                    ForEach(1...max(1, channelCount), id: \.self) { channel in
                        channelStrip(channel)
                            .frame(height: laneHeight)
                    }
                }
                .frame(width: headerWidth)

                // Waveforms with one shared horizontal scroll
                ScrollView(.horizontal, showsIndicators: true) {
                    ZStack(alignment: .topLeading) {
                        VStack(spacing: 6) {
                            ForEach(1...max(1, channelCount), id: \.self) { channel in
                                laneWaveform(channel, width: contentWidth)
                                    .frame(width: contentWidth, height: laneHeight)
                            }
                        }

                        // One playhead across all lanes
                        if slotDuration > 0 {
                            Rectangle()
                                .fill(Color.white.opacity(0.9))
                                .frame(width: 1)
                                .offset(x: contentWidth * (player.currentTime / slotDuration))
                                .allowsHitTesting(false)
                        }
                    }
                    .frame(width: contentWidth, alignment: .topLeading)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                player.isScrubbing = true
                                player.seek(to: max(0, min(1, value.location.x / contentWidth)))
                            }
                            .onEnded { _ in player.isScrubbing = false }
                    )
                }
                .scrollDisabled(zoom <= 1)
                .scrollPosition($scrollPosition)
                // Track the scroll offset and pointer so zoom can stay anchored
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentOffset.x
                } action: { _, newValue in
                    scrollX = newValue
                }
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location): cursorX = location.x
                    case .ended: cursorX = nil
                    }
                }
                .onChange(of: player.currentTime) {
                    followPlayhead(viewWidth: laneWidth, contentWidth: contentWidth)
                }
                .simultaneousGesture(
                    MagnifyGesture()
                        .onChanged { value in
                            let base = magnifyBaseZoom ?? zoom
                            magnifyBaseZoom = base
                            // Keep the audio under the pointer in place
                            setZoom(min(maxZoom, max(1, base * value.magnification)),
                                    anchorX: cursorX ?? laneWidth / 2)
                        }
                        .onEnded { _ in magnifyBaseZoom = nil }
                )
            }
            .onAppear { lastViewWidth = laneWidth }
            .onChange(of: laneWidth) { _, newValue in lastViewWidth = newValue }
        }
        .frame(height: lanesHeight)
    }

    private var lanesHeight: CGFloat {
        CGFloat(max(1, channelCount)) * (laneHeight + 6)
    }

    /// Name + mute/solo for one channel
    private func channelStrip(_ channel: Int) -> some View {
        let isMuted = player.isChannelMuted(slot: slot, channel: channel)
        let isSoloed = player.isChannelSoloed(slot: slot, channel: channel)
        let isAudible = player.isChannelAudible(slot: slot, channel: channel)

        return HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(name(for: channel))
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(isAudible ? .primary : .secondary)

                Text("Ch \(channel)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)

            VStack(spacing: 3) {
                MixerToggle(label: "M", isOn: isMuted, tint: .red,
                            help: "Mute this channel") {
                    player.toggleMute(slot: slot, channel: channel)
                }
                MixerToggle(label: "S", isOn: isSoloed, tint: .yellow,
                            help: "Solo this channel") {
                    player.toggleSolo(slot: slot, channel: channel)
                }
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .padding(.vertical, 4)
        .frame(maxHeight: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 10))
        .padding(.trailing, 6)
    }

    private func laneWaveform(_ channel: Int, width: CGFloat) -> some View {
        let samples = player.waveform(slot: slot, channel: channel)
        let isAudible = player.isChannelAudible(slot: slot, channel: channel)
        let isSoloed = player.isChannelSoloed(slot: slot, channel: channel)

        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.22))

            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)

            WaveformShape(samples: samples)
                .fill(
                    isSoloed ? Color.yellow.opacity(0.85)
                             : Color.accentColor.opacity(isAudible ? 0.8 : 0.22)
                )
                .padding(.vertical, 4)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .opacity(isAudible ? 1 : 0.55)
    }

    private func name(for channel: Int) -> String {
        // iXML names are 1-based with an unused slot 0
        if trackNames.indices.contains(channel), !trackNames[channel].isEmpty {
            return trackNames[channel]
        }
        return "Channel \(channel)"
    }

    /// Change the zoom while keeping the audio at `anchorX` (a point in the
    /// visible lane area) under the same screen position.
    private func setZoom(_ newZoom: CGFloat, anchorX: CGFloat) {
        let viewWidth = max(lastViewWidth, 1)
        let oldContent = viewWidth * zoom
        let newContent = viewWidth * newZoom
        guard oldContent > 0 else { zoom = newZoom; return }

        let fractionUnderPointer = (scrollX + anchorX) / oldContent
        zoom = newZoom

        let target = fractionUnderPointer * newContent - anchorX
        let clamped = max(0, min(max(newContent - viewWidth, 0), target))
        scrollPosition.scrollTo(x: clamped)
        scrollX = clamped
    }

    /// Keep the playhead centred while zoomed in and playing
    private func followPlayhead(viewWidth: CGFloat, contentWidth: CGFloat) {
        guard zoom > 1, player.isPlaying, !player.isScrubbing, slotDuration > 0 else { return }
        let playheadX = contentWidth * (player.currentTime / slotDuration)
        scrollPosition.scrollTo(x: max(0, min(contentWidth - viewWidth, playheadX - viewWidth / 2)))
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Small M/S toggle in a channel strip
private struct MixerToggle: View {
    let label: String
    let isOn: Bool
    let tint: Color
    let help: String
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .frame(width: 18, height: 14)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isOn ? tint.opacity(0.85) : Color.secondary.opacity(0.18))
                )
                .foregroundStyle(isOn ? AnyShapeStyle(.black) : AnyShapeStyle(.secondary))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
