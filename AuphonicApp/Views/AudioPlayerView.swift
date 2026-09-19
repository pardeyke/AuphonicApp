import SwiftUI

struct AudioPlayerView: View {
    @Bindable var player: AudioPlayerService

    @State private var zoom: CGFloat = 1
    @State private var magnifyBaseZoom: CGFloat?

    private let maxZoom: CGFloat = 64

    var body: some View {
        VStack(spacing: 4) {
            // Waveforms stacked with solo selectors on the right
            HStack(spacing: 0) {
                // Waveforms column
                VStack(spacing: 0) {
                    WaveformPanel(
                        player: player,
                        label: "Original",
                        data: player.originalWaveform,
                        isActive: player.activeSlot == .original,
                        hasData: player.hasOriginal,
                        slot: .original,
                        widthFraction: 1.0,
                        zoom: zoom
                    )

                    if player.hasProcessed {
                        Divider()

                        WaveformPanel(
                            player: player,
                            label: "Processed",
                            data: player.processedWaveform,
                            isActive: player.activeSlot == .processed,
                            hasData: player.hasProcessed,
                            slot: .processed,
                            widthFraction: processedWidthFraction,
                            zoom: zoom
                        )
                    }
                }
                .simultaneousGesture(
                    MagnifyGesture()
                        .onChanged { value in
                            let base = magnifyBaseZoom ?? zoom
                            magnifyBaseZoom = base
                            zoom = min(maxZoom, max(1, base * value.magnification))
                        }
                        .onEnded { _ in
                            magnifyBaseZoom = nil
                        }
                )

                // Solo selectors column
                if player.channelCountA > 1 || player.channelCountB > 1 {
                    Divider()

                    VStack(spacing: 0) {
                        soloSelector(slot: .original)
                            .frame(maxHeight: .infinity)

                        if player.hasProcessed {
                            Divider()

                            soloSelector(slot: .processed)
                                .frame(maxHeight: .infinity)
                        }
                    }
                    .frame(width: 70)
                }
            }
            .frame(height: waveformHeight)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )

            // Controls row
            HStack(spacing: 8) {
                Button {
                    player.togglePlayPause()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 24, height: 24)
                }
                .disabled(!player.hasOriginal)

                // Zoom controls
                HStack(spacing: 4) {
                    Button {
                        zoom = max(1, zoom / 2)
                    } label: {
                        Image(systemName: "minus.magnifyingglass")
                    }
                    .buttonStyle(.borderless)
                    .disabled(zoom <= 1)

                    Text(zoom <= 1 ? "Fit" : "\(Int(zoom.rounded()))×")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 32)

                    Button {
                        zoom = min(maxZoom, zoom * 2)
                    } label: {
                        Image(systemName: "plus.magnifyingglass")
                    }
                    .buttonStyle(.borderless)
                    .disabled(zoom >= maxZoom)

                    if zoom > 1 {
                        Button("Fit") {
                            zoom = 1
                        }
                        .buttonStyle(.borderless)
                        .font(.system(size: 11))
                    }
                }
                .disabled(!player.hasOriginal)

                Spacer()

                // Live BWF timecode at the playback position
                if let tc = player.currentTimecodeString {
                    Text("TC \(tc)")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(player.isPlaying ? .primary : .secondary)
                }

                Spacer()

                Text(formatTime(player.currentTime))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)

                Text("/")
                    .foregroundStyle(.secondary)
                    .font(.caption)

                Text(formatTime(player.duration))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Layout

    /// Height per panel based on solo button count (All + N channels), min 40pt
    private var waveformHeight: CGFloat {
        let maxChannels = max(player.channelCountA, player.channelCountB)
        let buttonCount = maxChannels > 1 ? maxChannels + 1 : 0 // "All" + each channel
        let perPanel = max(40, CGFloat(buttonCount) * 18 + 8) // 18pt per button + padding
        let panels = player.hasProcessed ? 2 : 1
        return perPanel * CGFloat(panels)
    }

    /// Fraction of width the processed waveform should fill relative to original
    private var processedWidthFraction: CGFloat {
        guard player.originalDuration > 0, player.processedDuration > 0 else { return 1.0 }
        return min(1.0, player.processedDuration / player.originalDuration)
    }

    // MARK: - Solo Selector (per slot)

    private func soloSelector(slot: AudioPlayerService.Slot) -> some View {
        let channelCount = slot == .original ? player.channelCountA : player.channelCountB
        let soloChannel = slot == .original ? player.soloChannelA : player.soloChannelB
        let trackNames = slot == .original ? player.trackNamesA : player.trackNamesB

        return VStack(spacing: 2) {
            if channelCount > 1 {
                soloButton(label: "All", channel: 0, current: soloChannel, slot: slot)

                ForEach(1...channelCount, id: \.self) { ch in
                    let name = trackNames.indices.contains(ch) && !trackNames[ch].isEmpty
                        ? trackNames[ch]
                        : "\(ch)"
                    soloButton(label: name, channel: ch, current: soloChannel, slot: slot)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }

    private func soloButton(label: String, channel: Int, current: Int, slot: AudioPlayerService.Slot) -> some View {
        Button(label) {
            player.setSoloChannel(slot: slot, channel: channel)
            if player.activeSlot != slot {
                player.switchTo(slot)
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: 9))
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .frame(maxWidth: .infinity)
        .background(
            current == channel && player.activeSlot == slot
                ? Color.accentColor.opacity(0.4)
                : Color(nsColor: .controlBackgroundColor).opacity(0.6)
        )
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    // MARK: - Formatting

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Zoomable Waveform Panel

/// One waveform lane: zoomable (content width = view width × zoom), pannable
/// via trackpad scroll, scrubbable via click-drag, with a playhead that the
/// view follows automatically during playback.
private struct WaveformPanel: View {
    @Bindable var player: AudioPlayerService
    let label: String
    let data: [Float]
    let isActive: Bool
    let hasData: Bool
    let slot: AudioPlayerService.Slot
    let widthFraction: CGFloat
    let zoom: CGFloat

    @State private var scrollPosition = ScrollPosition(edge: .leading)

    private var slotDuration: Double {
        slot == .original ? player.originalDuration : player.processedDuration
    }

    var body: some View {
        GeometryReader { geo in
            let viewWidth = geo.size.width
            let contentWidth = max(viewWidth * widthFraction * zoom, 1)

            ZStack(alignment: .topLeading) {
                ScrollView(.horizontal, showsIndicators: false) {
                    ZStack(alignment: .leading) {
                        if hasData && !data.isEmpty {
                            // Center line
                            Rectangle()
                                .fill(Color(nsColor: .separatorColor).opacity(0.6))
                                .frame(width: contentWidth, height: 1)

                            WaveformShape(samples: data)
                                .fill(Color.accentColor.opacity(isActive ? 0.7 : 0.3))
                                .frame(width: contentWidth)

                            // Playback position indicator
                            if isActive, slotDuration > 0 {
                                Rectangle()
                                    .fill(Color.white)
                                    .frame(width: 1)
                                    .offset(x: contentWidth * (player.currentTime / slotDuration))
                            }
                        } else {
                            Text(hasData ? "" : "No audio")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                                .frame(width: viewWidth)
                        }
                    }
                    .frame(width: contentWidth, height: geo.size.height, alignment: .leading)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if !isActive {
                                    if slot == .original || player.hasProcessed {
                                        player.switchTo(slot)
                                    }
                                }
                                let fraction = max(0, min(1, value.location.x / contentWidth))
                                player.isScrubbing = true
                                player.seek(to: fraction)
                            }
                            .onEnded { _ in
                                player.isScrubbing = false
                            }
                    )
                }
                .scrollDisabled(zoom <= 1)
                .scrollPosition($scrollPosition)

                // Fixed label (doesn't scroll with the waveform)
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(isActive ? .primary : .secondary)
                    .padding(.leading, 4)
                    .padding(.top, 2)
            }
            .onChange(of: player.currentTime) {
                followPlayhead(viewWidth: viewWidth, contentWidth: contentWidth, onlyWhenPlaying: true)
            }
            .onChange(of: zoom) {
                followPlayhead(viewWidth: viewWidth, contentWidth: contentWidth, onlyWhenPlaying: false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Keep the playhead centered in the visible window while zoomed in
    private func followPlayhead(viewWidth: CGFloat, contentWidth: CGFloat, onlyWhenPlaying: Bool) {
        guard zoom > 1, isActive, slotDuration > 0 else { return }
        if onlyWhenPlaying && (!player.isPlaying || player.isScrubbing) { return }

        let playheadX = contentWidth * (player.currentTime / slotDuration)
        let target = max(0, min(contentWidth - viewWidth, playheadX - viewWidth / 2))
        scrollPosition.scrollTo(x: target)
    }
}

// MARK: - Waveform Shape

/// Symmetric peak waveform. The sample array is high-resolution (8192 bins);
/// each rendered column takes the max of the bins it covers, so the drawing
/// adapts to any content width without exceeding one bar per bin.
struct WaveformShape: Shape {
    let samples: [Float]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard !samples.isEmpty, rect.width > 0 else { return path }

        let columns = min(Int(rect.width.rounded()), samples.count)
        guard columns > 0 else { return path }

        let columnWidth = rect.width / CGFloat(columns)
        let midY = rect.midY

        for column in 0..<columns {
            let binStart = column * samples.count / columns
            let binEnd = max(binStart + 1, (column + 1) * samples.count / columns)

            var peak: Float = 0
            for bin in binStart..<min(binEnd, samples.count) {
                if samples[bin] > peak { peak = samples[bin] }
            }

            let height = max(CGFloat(peak) * rect.height * 0.92, 1)
            path.addRect(CGRect(
                x: CGFloat(column) * columnWidth,
                y: midY - height / 2,
                width: max(columnWidth - 0.5, 0.5),
                height: height
            ))
        }

        return path
    }
}
