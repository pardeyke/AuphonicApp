import SwiftUI

/// Liquid Glass bubble that heads a file group in the sidebar:
/// the timecode range is the heading, the channel/file/mode summary sits below.
/// The active group is tinted blue; the bubble also collapses its files.
struct GroupHeaderBubble: View {
    /// Shared with the selected-file background so both stay in sync
    static let cornerRadius: CGFloat = 12

    let timecodeRange: String
    let channelCount: Int
    let fileCount: Int
    let mode: ProductionMode
    let isSelected: Bool
    let isConfigured: Bool
    var isCollapsed: Bool = false
    var onToggleCollapse: (() -> Void)?

    @State private var showsWarningTooltip = false

    var body: some View {
        HStack(spacing: 8) {
            if let onToggleCollapse {
                Button {
                    onToggleCollapse()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                        .foregroundStyle(isSelected ? .white : .secondary)
                        .frame(width: 12, height: 12)
                }
                .buttonStyle(.plain)
                .help(isCollapsed ? "Show files in this group" : "Hide files in this group")
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(timecodeRange.isEmpty ? "No timecode" : timecodeRange)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(isSelected ? .white : .primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Spacer(minLength: 0)

                    if !isConfigured {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(isSelected ? .white : .orange)
                            .frame(width: 18, height: 18)     // comfortable hover target
                            .contentShape(Rectangle())
                            // `.help` waits for the system tooltip delay —
                            // a hover-driven popover shows without waiting.
                            .onHover { hovering in
                                showsWarningTooltip = hovering
                            }
                            .popover(isPresented: $showsWarningTooltip, arrowEdge: .trailing) {
                                Text("""
                                Nothing to process in this group yet: select at least one channel \
                                and either pick a preset or switch on an algorithm. Groups that \
                                stay unconfigured are skipped when the batch runs.
                                """)
                                .font(.system(size: 11))
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(10)
                                .frame(width: 260)
                            }
                    }
                }

                HStack(spacing: 5) {
                    Image(systemName: "waveform")
                    Text("\(channelCount) ch")
                    Text("·")
                    Text("\(fileCount) file\(fileCount == 1 ? "" : "s")")
                    Text("·")
                    Text(mode.displayName)
                }
                .font(.system(size: 10))
                .foregroundStyle(isSelected ? Color.white.opacity(0.85) : Color.secondary)
                .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Translucent so the file rows stay visible scrolling behind it
        .glassEffect(
            isSelected ? .regular.tint(.blue.opacity(0.8)) : .regular,
            in: .rect(cornerRadius: Self.cornerRadius)
        )
        .padding(.vertical, 4)
    }
}

#Preview("Group header bubbles") {
    VStack(spacing: 6) {
        GroupHeaderBubble(
            timecodeRange: "10:14:03–10:32:02",
            channelCount: 3,
            fileCount: 10,
            mode: .singletrack,
            isSelected: true,
            isConfigured: true,
            isCollapsed: false,
            onToggleCollapse: {}
        )

        GroupHeaderBubble(
            timecodeRange: "10:43:06–12:15:33",
            channelCount: 4,
            fileCount: 29,
            mode: .multitrack,
            isSelected: false,
            isConfigured: true,
            isCollapsed: true,
            onToggleCollapse: {}
        )

        GroupHeaderBubble(
            timecodeRange: "13:04:18–13:07:16",
            channelCount: 2,
            fileCount: 6,
            mode: .singletrack,
            isSelected: false,
            isConfigured: false,
            isCollapsed: false,
            onToggleCollapse: {}
        )
    }
    .padding(12)
    .frame(width: 320)
    .background(Color(nsColor: .windowBackgroundColor))
}
