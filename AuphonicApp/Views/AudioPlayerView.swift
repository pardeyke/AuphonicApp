import SwiftUI

struct AudioPlayerView: View {
    @Bindable var player: AudioPlayerService

    var body: some View {
        VStack(spacing: 4) {
            // Waveforms stacked with solo selectors on the right
            HStack(spacing: 0) {
                // Waveforms column
                VStack(spacing: 0) {
                    waveformPanel(
                        label: "Original",
                        data: player.originalWaveform,
                        isActive: player.activeSlot == .original,
                        hasData: player.hasOriginal,
                        slot: .original,
                        widthFraction: 1.0
                    )

                    if player.hasProcessed {
                        Divider()

                        waveformPanel(
                            label: "Processed",
                            data: player.processedWaveform,
                            isActive: player.activeSlot == .processed,
                            hasData: player.hasProcessed,
                            slot: .processed,
                            widthFraction: processedWidthFraction
                        )
                    }
                }

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

    // MARK: - Waveform Panel with Scrubbing

    private func waveformPanel(label: String, data: [Float], isActive: Bool, hasData: Bool, slot: AudioPlayerService.Slot, widthFraction: CGFloat) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                if hasData && !data.isEmpty {
                    WaveformShape(samples: data)
                        .fill(Color.accentColor.opacity(isActive ? 0.7 : 0.3))
                        .frame(width: geo.size.width * widthFraction)
                        .clipped()

                    // Playback position indicator
                    if isActive {
                        let slotDuration = slot == .original ? player.originalDuration : player.processedDuration
                        let x = slotDuration > 0 ? geo.size.width * widthFraction * (player.currentTime / slotDuration) : 0
                        Rectangle()
                            .fill(Color.white)
                            .frame(width: 1)
                            .position(x: x, y: geo.size.height / 2)
                    }
                } else {
                    Text(hasData ? "" : "No audio")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }

                // Label
                VStack {
                    HStack {
                        Text(label)
                            .font(.system(size: 10))
                            .foregroundStyle(isActive ? .primary : .secondary)
                            .padding(.leading, 4)
                            .padding(.top, 2)
                        Spacer()
                    }
                    Spacer()
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isActive {
                            if slot == .original || player.hasProcessed {
                                player.switchTo(slot)
                            }
                        }
                        let scaledWidth = geo.size.width * widthFraction
                        let fraction = max(0, min(1, value.location.x / scaledWidth))
                        player.isScrubbing = true
                        player.seek(to: fraction)
                    }
                    .onEnded { _ in
                        player.isScrubbing = false
                    }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

struct WaveformShape: Shape {
    let samples: [Float]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard !samples.isEmpty else { return path }

        let midY = rect.midY
        let barWidth = rect.width / CGFloat(samples.count)

        for (i, sample) in samples.enumerated() {
            let x = CGFloat(i) * barWidth
            let height = CGFloat(sample) * rect.height * 0.9
            let barRect = CGRect(
                x: x,
                y: midY - height / 2,
                width: max(barWidth - 0.5, 0.5),
                height: max(height, 1)
            )
            path.addRect(barRect)
        }

        return path
    }
}
