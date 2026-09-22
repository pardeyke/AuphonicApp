import SwiftUI

struct CreditsView: View {
    var credits: UserCredits?
    var estimatedCostSeconds: Double // billed seconds for the whole batch (incl. 3-min minimums)
    var apiCallCount: Int            // number of Auphonic productions in the batch

    var body: some View {
        VStack(spacing: 3) {
            if let credits = credits {
                let totalCredits = credits.displayCredits * 3600
                let cost = estimatedCostSeconds
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

                        // Green fill (always visible when credits exist)
                        if totalCredits > 0 {
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

                        if cost > 0 && totalCredits > 0 {
                            let costFraction = min(1, cost / totalCredits)

                            // Cost portion (from right side)
                            let costWidth = costFraction * barWidth
                            HStack(spacing: 0) {
                                Spacer(minLength: 0)
                                if exceedsCredits {
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
                                     ? "Over by \(DurationText.clock(abs(remaining), rounded: true))"
                                     : "Remaining: \(DurationText.clock(remaining, rounded: true))")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.white)
                                    .shadow(color: .black.opacity(0.3), radius: 1, y: 0.5)
                                    .padding(.leading, 6)

                                Spacer(minLength: 4)

                                // Right: cost
                                Text("Cost: \(DurationText.clock(cost, rounded: true))")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.white)
                                    .shadow(color: .black.opacity(0.3), radius: 1, y: 0.5)
                                    .padding(.trailing, 6)
                            } else {
                                Text("Credits: \(DurationText.clock(totalCredits, rounded: true))")
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

                if cost > 0 {
                    Text("\(apiCallCount) production\(apiCallCount == 1 ? "" : "s") — Auphonic bills a 3 minute minimum each")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var exceedsCredits: Bool {
        guard let credits = credits else { return false }
        return estimatedCostSeconds > credits.displayCredits * 3600
    }
}
