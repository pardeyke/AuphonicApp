import Foundation

/// Master-track (mixdown) settings of a multitrack production.
/// These apply to the combined mix, not to the individual tracks —
/// per-track settings come from each channel's `ManualOptionsState`.
@Observable
final class MultitrackMasterOptions {
    // Adaptive Leveler (master)
    var levelerEnabled = true
    var broadcastMode = false
    var maxLRA = 0              // 0 = Auto
    var maxShortTerm = 0
    var maxMomentary = 0

    // Gates
    var gate = true             // noise gate
    var crossgate = true        // crosstalk / mic bleed damping between tracks

    // Loudness Normalization
    var loudnessEnabled = true
    var loudnessTarget = -16    // LUFS
    var maxPeak: Double = 0     // 0 = Auto
    var loudnessMethod = 1      // 1=Program, 2=Dialog, 3=RMS
    var dualMono = false

    /// True when at least one master algorithm runs. Gates and crosstalk
    /// damping are master algorithms too — they change the exported tracks.
    var hasAnyEnabled: Bool {
        levelerEnabled || gate || crossgate || loudnessEnabled
    }

    /// Master `algorithms` dict for a multitrack production
    func getSettings() -> [String: Any] {
        var algorithms: [String: Any] = [:]

        algorithms["leveler"] = levelerEnabled
        if levelerEnabled && broadcastMode {
            algorithms["maxlra"] = maxLRA
            algorithms["maxs"] = maxShortTerm
            algorithms["maxm"] = maxMomentary
        }

        algorithms["gate"] = gate
        algorithms["crossgate"] = crossgate

        algorithms["normloudness"] = loudnessEnabled
        if loudnessEnabled {
            algorithms["loudnesstarget"] = loudnessTarget
            algorithms["maxpeak"] = maxPeak
            algorithms["dualmono"] = dualMono
            let methods = ["program", "dialog", "rms"]
            algorithms["loudnessmethod"] = methods[loudnessMethod - 1]
        }

        return algorithms
    }

    // MARK: - Persistence

    func getWidgetState() -> [String: Any] {
        [
            "levelerEnabled": levelerEnabled,
            "broadcastMode": broadcastMode,
            "maxLRA": maxLRA,
            "maxShortTerm": maxShortTerm,
            "maxMomentary": maxMomentary,
            "gate": gate,
            "crossgate": crossgate,
            "loudnessEnabled": loudnessEnabled,
            "loudnessTarget": loudnessTarget,
            "maxPeak": maxPeak,
            "loudnessMethod": loudnessMethod,
            "dualMono": dualMono,
        ]
    }

    func applyWidgetState(_ state: [String: Any]) {
        levelerEnabled = (state["levelerEnabled"] as? Bool) ?? true
        broadcastMode = (state["broadcastMode"] as? Bool) ?? false
        maxLRA = (state["maxLRA"] as? Int) ?? 0
        maxShortTerm = (state["maxShortTerm"] as? Int) ?? 0
        maxMomentary = (state["maxMomentary"] as? Int) ?? 0
        gate = (state["gate"] as? Bool) ?? true
        crossgate = (state["crossgate"] as? Bool) ?? true
        loudnessEnabled = (state["loudnessEnabled"] as? Bool) ?? true
        loudnessTarget = (state["loudnessTarget"] as? Int) ?? -16
        maxPeak = (state["maxPeak"] as? Double) ?? 0
        loudnessMethod = (state["loudnessMethod"] as? Int) ?? 1
        dualMono = (state["dualMono"] as? Bool) ?? false
    }
}
