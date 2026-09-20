import SwiftUI

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
