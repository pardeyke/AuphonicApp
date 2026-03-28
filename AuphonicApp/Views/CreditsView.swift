import SwiftUI

struct CreditsView: View {
    var credits: UserCredits?
    var fileDurations: [Double]     // per-file durations in seconds
    var previewDuration: Double     // 0 = full
    var channelMultiplier: Int      // for per-channel mode

    var body: some View {
        VStack(spacing: 3) {
            if let credits = credits {
                let totalCredits = credits.displayCredits * 3600
                let cost = fileDurations.isEmpty ? 0.0 : estimatedCost
                let remaining = totalCredits - cost

                // Bar
                GeometryReader { geo in
                    let barWidth = geo.size.width
                    let barHeight: CGFloat = 22

                    ZStack(alignment: .leading) {
                        // Background (total credits)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(nsColor: .controlBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
                            )

                        if cost > 0 && totalCredits > 0 {
                            // Remaining portion (green/teal, fills from left)
                            let remainFraction = max(0, min(1, remaining / totalCredits))
                            let costFraction = min(1, cost / totalCredits)

                            // Remaining fill
                            if remainFraction > 0 {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.green.opacity(0.6), Color.green.opacity(0.5)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: barWidth)
                            }

                            // Cost portion (from right side of remaining)
                            let costWidth = costFraction * barWidth
                            HStack(spacing: 0) {
                                Spacer(minLength: 0)
                                if exceedsCredits {
                                    // Overflows: show full bar red
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(
                                            LinearGradient(
                                                colors: [Color.orange.opacity(0.7), Color.red.opacity(0.8)],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .frame(width: barWidth)
                                } else {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(
                                            LinearGradient(
                                                colors: [Color.orange.opacity(0.6), Color.orange.opacity(0.75)],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .frame(width: costWidth)
                                }
                            }

                            // Divider line between remaining and cost
                            if !exceedsCredits && costFraction > 0 && costFraction < 1 {
                                Rectangle()
                                    .fill(Color.orange.opacity(0.8))
                                    .frame(width: 1)
                                    .offset(x: (1 - costFraction) * barWidth)
                            }
                        }

                        // Labels overlay
                        HStack(spacing: 0) {
                            if cost > 0 {
                                // Left: remaining
                                Text(exceedsCredits
                                     ? "Over by \(formatDuration(abs(remaining)))"
                                     : "Remaining: \(formatDuration(remaining))")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.white)
                                    .shadow(color: .black.opacity(0.3), radius: 1, y: 0.5)
                                    .padding(.leading, 6)

                                Spacer(minLength: 4)

                                // Right: cost
                                Text("Cost: \(formatDuration(cost))")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.white)
                                    .shadow(color: .black.opacity(0.3), radius: 1, y: 0.5)
                                    .padding(.trailing, 6)
                            } else {
                                Text("Credits: \(formatDuration(totalCredits))")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.white)
                                    .shadow(color: .black.opacity(0.3), radius: 1, y: 0.5)
                                    .padding(.leading, 6)
                                Spacer()
                            }
                        }
                    }
                    .frame(height: barHeight)
                }
                .frame(height: 22)

                if cost > 0 && hasMinimumApplied {
                    Text("Auphonic bills a 3 minute minimum per file")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private static let minimumBilledSeconds: Double = 180

    private var estimatedCost: Double {
        let multiplier = Double(max(1, channelMultiplier))
        return fileDurations.reduce(0.0) { total, duration in
            let effective = previewDuration > 0 ? min(previewDuration, duration) : duration
            let billed = max(effective, Self.minimumBilledSeconds)
            return total + billed * multiplier
        }
    }

    private var hasMinimumApplied: Bool {
        fileDurations.contains { duration in
            let effective = previewDuration > 0 ? min(previewDuration, duration) : duration
            return effective < Self.minimumBilledSeconds
        }
    }

    private var exceedsCredits: Bool {
        guard let credits = credits else { return false }
        return estimatedCost > credits.displayCredits * 3600
    }

    private func formatDuration(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds.rounded())
        let negative = totalSeconds < 0
        let abs = abs(totalSeconds)
        let h = abs / 3600
        let m = (abs % 3600) / 60
        let s = abs % 60
        if h > 0 {
            return String(format: "%@%d:%02d:%02d", negative ? "-" : "", h, m, s)
        }
        return String(format: "%@%d:%02d", negative ? "-" : "", m, s)
    }
}
