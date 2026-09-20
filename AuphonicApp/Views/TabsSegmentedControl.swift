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

/// The system segmented control in its "tabs" role, which is what gives it the
/// Liquid Glass capsule treatment on macOS 27. SwiftUI's `.segmented` picker
/// style still renders the classic bordered control, so this bridges to AppKit.
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
