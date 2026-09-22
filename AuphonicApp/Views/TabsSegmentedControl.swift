import SwiftUI
import AppKit

/// `NSSegmentedControl` renders at its intrinsic height and ignores the frame
/// it is given, so the height has to come from the control itself.
final class HeightAdjustableSegmentedControl: NSSegmentedControl {
    var preferredHeight: CGFloat = 0 {
        didSet { invalidateIntrinsicContentSize() }
    }

    override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        size.height = max(size.height, preferredHeight)
        return size
    }
}

/// Liquid Glass tabs picker: the capsule with a sliding indicator.
///
/// macOS 27 ships this natively as `.pickerStyle(.tabs)`. The deployment
/// target is 26.2, where SwiftUI's `.segmented` style still renders the
/// classic bordered control, so 26 falls back to the AppKit bridge below.
struct TabsPicker<Value: Hashable>: View {
    let values: [Value]
    let titles: [String]
    @Binding var selection: Value
    /// Size on 27 (`nil` inherits, e.g. from the toolbar); the AppKit fallback
    /// derives its control size and height from it.
    var controlSize: ControlSize? = nil

    var body: some View {
        if #available(macOS 27.0, *) {
            Picker("", selection: $selection) {
                ForEach(values.indices, id: \.self) { index in
                    Text(titles[index]).tag(values[index])
                }
            }
            .pickerStyle(.tabs)
            .labelsHidden()
            .modifier(OptionalControlSize(size: controlSize))
        } else {
            TabsSegmentedControl(
                values: values,
                titles: titles,
                selection: $selection,
                controlSize: fallbackControlSize,
                height: fallbackHeight
            )
        }
    }

    private var fallbackControlSize: NSControl.ControlSize {
        switch controlSize {
        case .large: return .large
        case .small: return .small
        case .mini: return .mini
        default: return .regular
        }
    }

    private var fallbackHeight: CGFloat {
        switch controlSize {
        case .large: return 44
        case .small, .mini: return 24
        default: return 28
        }
    }
}

private struct OptionalControlSize: ViewModifier {
    let size: ControlSize?

    func body(content: Content) -> some View {
        if let size {
            content.controlSize(size)
        } else {
            content
        }
    }
}

/// AppKit fallback for macOS 26: the system segmented control with a capsule
/// border. On 27 the same control gets the tabs role, but there `TabsPicker`
/// uses the SwiftUI style instead.
struct TabsSegmentedControl<Value: Hashable>: NSViewRepresentable {
    let values: [Value]
    let titles: [String]
    @Binding var selection: Value
    var controlSize: NSControl.ControlSize = .large
    var height: CGFloat = 44

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = HeightAdjustableSegmentedControl(
            labels: titles,
            trackingMode: .selectOne,
            target: context.coordinator,
            action: #selector(Coordinator.selectionChanged(_:))
        )
        control.preferredHeight = height

        if #available(macOS 27.0, *) {
            control.role = .tabs        // Liquid Glass capsule + sliding indicator
        }
        control.borderShape = .capsule  // pill ends instead of rounded rect
        control.controlSize = controlSize
        control.segmentDistribution = .fit
        control.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        control.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.parent = self

        if let control = control as? HeightAdjustableSegmentedControl, control.preferredHeight != height {
            control.preferredHeight = height
        }

        // Keep labels in sync if the options change
        if control.segmentCount != titles.count {
            control.segmentCount = titles.count
        }
        for (index, title) in titles.enumerated() where control.label(forSegment: index) != title {
            control.setLabel(title, forSegment: index)
        }

        if let index = values.firstIndex(of: selection), control.selectedSegment != index {
            control.selectedSegment = index
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSSegmentedControl, context: Context) -> CGSize? {
        nsView.intrinsicContentSize
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: TabsSegmentedControl

        init(_ parent: TabsSegmentedControl) {
            self.parent = parent
        }

        @objc func selectionChanged(_ sender: NSSegmentedControl) {
            let index = sender.selectedSegment
            guard parent.values.indices.contains(index) else { return }
            parent.selection = parent.values[index]
        }
    }
}
