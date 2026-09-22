import Foundation

/// Clock-style durations for the UI: `m:ss`, or `h:mm:ss` from one hour on.
enum DurationText {
    /// - Parameters:
    ///   - seconds: may be negative (shown with a leading minus)
    ///   - rounded: round to the nearest second instead of truncating
    static func clock(_ seconds: Double, rounded: Bool = false) -> String {
        let whole = Int(rounded ? seconds.rounded() : seconds.rounded(.towardZero))
        let sign = whole < 0 ? "-" : ""
        let total = abs(whole)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%@%d:%02d:%02d", sign, h, m, s)
        }
        return String(format: "%@%d:%02d", sign, m, s)
    }
}
