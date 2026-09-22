import SwiftUI

/// Checkbox styled as a Liquid Glass pill. Used for channel selection and
/// the boolean options of the processing settings. Put rows of these inside
/// a `GlassEffectContainer` so they render as one glass layer.
struct GlassCheckbox: View {
    let label: String
    @Binding var isOn: Bool
    var systemImage: String?
    var tint: Color = .accentColor

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12))
                    .foregroundStyle(isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))

                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 10))
                        .foregroundStyle(isOn ? AnyShapeStyle(.white.opacity(0.9)) : AnyShapeStyle(.secondary))
                }

                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .glassEffect(
                isOn ? .regular.tint(tint.opacity(0.8)).interactive() : .regular.interactive(),
                in: .rect(cornerRadius: 9)
            )
        }
        .buttonStyle(.plain)
    }
}

/// Distance below which neighbouring glass shapes in one container start to
/// blend. Chips sit 6 pt apart and should stay distinct, so this is smaller.
enum GlassSpacing {
    static let chips: CGFloat = 2
}

/// Section heading with an optional trailing accessory
struct SectionHeading<Accessory: View>: View {
    let title: String
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.largeTitle.weight(.bold))

            Spacer()

            accessory()
        }
    }
}

extension SectionHeading where Accessory == EmptyView {
    init(_ title: String) {
        self.init(title: title) { EmptyView() }
    }
}

/// Small caption above a block of settings
struct SettingsGroupLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .kerning(0.5)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("Glass controls") {
    struct Host: View {
        @State private var a = true
        @State private var b = false

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeading(title: "Processing") {
                    Text("4 ch")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                SettingsGroupLabel(text: "Channels")

                GlassEffectContainer(spacing: GlassSpacing.chips) {
                    HStack(spacing: 8) {
                        GlassCheckbox(label: "Ch 1 (BOOM)", isOn: .constant(true), systemImage: "waveform")
                        GlassCheckbox(label: "Ch 2 (LAVMIX)", isOn: .constant(false), systemImage: "waveform")
                    }
                }

                GlassEffectContainer(spacing: GlassSpacing.chips) {
                    HStack(spacing: 8) {
                        GlassCheckbox(label: "Link settings", isOn: $a)
                        GlassCheckbox(label: "Settings JSON", isOn: $b)
                    }
                }
            }
            .padding(16)
            .frame(width: 520)
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }
    return Host()
}
