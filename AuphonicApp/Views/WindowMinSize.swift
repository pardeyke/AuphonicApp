import SwiftUI
import AppKit

/// Sizing limits for the main window.
///
/// `NavigationSplitView` does not propagate a `.frame(minWidth:minHeight:)` to
/// the hosting window, so `.windowResizability` alone lets the window shrink
/// past what the content needs — the split view then keeps its own width and
/// gets clipped at the left and right edges instead of compressing. Pinning the
/// `NSWindow`'s own `minSize` is what actually stops the resize.
///
/// The sidebar keeps whatever width the user dragged it to rather than
/// compressing back toward `sidebarMinWidth`, so the width the content needs is
/// the *current* sidebar width plus the detail minimum — not a constant.
enum MainWindowSize {
    static let sidebarMinWidth: CGFloat = 260
    static let sidebarIdealWidth: CGFloat = 320
    static let sidebarMaxWidth: CGFloat = 460
    static let detailMinWidth: CGFloat = 560
    static let minHeight: CGFloat = 620

    static let defaultWidth: CGFloat = 1080
    static let defaultHeight: CGFloat = 760

    /// Content width required to show a sidebar of `sidebarWidth` without clipping.
    static func minWidth(sidebarWidth: CGFloat) -> CGFloat {
        detailMinWidth + min(max(sidebarWidth, 0), sidebarMaxWidth)
    }
}

/// Reports the sidebar's laid-out width up to `ContentView`.
struct SidebarWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = MainWindowSize.sidebarIdealWidth
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

extension View {
    /// Measures this view's width and publishes it as `SidebarWidthKey`.
    func measuringSidebarWidth() -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(key: SidebarWidthKey.self, value: proxy.size.width)
            }
        )
    }

    /// Pins the hosting window's minimum size, and grows the window if its
    /// current frame is already smaller than that minimum.
    func enforcedWindowMinSize(width: CGFloat, height: CGFloat) -> some View {
        background(WindowMinSizeApplier(contentMinSize: CGSize(width: width, height: height)))
    }
}

private struct WindowMinSizeApplier: NSViewRepresentable {
    let contentMinSize: CGSize

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.isHidden = true
        DispatchQueue.main.async { apply(to: view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { apply(to: nsView.window) }
    }

    private func apply(to window: NSWindow?) {
        guard let window, window.styleMask.contains(.resizable) else { return }

        // Content size → frame size, so the titlebar/toolbar height is included.
        let minFrame = window.frameRect(
            forContentRect: CGRect(origin: .zero, size: contentMinSize)
        ).size

        guard window.minSize != minFrame else { return }
        window.minSize = minFrame

        // The frame can already be smaller: restored from a previous session,
        // or the sidebar was just widened past what the window can show.
        let frame = window.frame
        guard frame.width < minFrame.width || frame.height < minFrame.height else { return }

        var grown = frame
        grown.size.width = max(frame.width, minFrame.width)
        grown.size.height = max(frame.height, minFrame.height)
        // Keep the title bar in place while growing down and to the right.
        grown.origin.y = frame.maxY - grown.height
        window.setFrame(grown, display: true, animate: false)
    }
}
