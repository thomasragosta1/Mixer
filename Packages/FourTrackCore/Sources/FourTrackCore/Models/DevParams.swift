import Foundation

/// Developer Mode "exploded" values. Each section is optional: nil means the
/// section follows its macro slider.
public struct DevParams: Codable, Equatable, Sendable {
    public var compressor: CompressorParams?
    public var eq: [EQBandParams]?
    public var reverb: ReverbParams?
    /// Pre-record digital trim applied to newly recorded audio, in dB.
    public var inputGainDB: Double?

    public init(compressor: CompressorParams? = nil, eq: [EQBandParams]? = nil, reverb: ReverbParams? = nil, inputGainDB: Double? = nil) {
        self.compressor = compressor
        self.eq = eq
        self.reverb = reverb
        self.inputGainDB = inputGainDB
    }

    public var isEmpty: Bool {
        compressor == nil && eq == nil && reverb == nil && (inputGainDB ?? 0) == 0
    }

    public static let inputGainRange: ClosedRange<Double> = -12...24
}

/// Parameters for Apple's DynamicsProcessor.
public struct CompressorParams: Codable, Equatable, Sendable {
    public var thresholdDB: Double
    public var headroomDB: Double
    public var attackSeconds: Double
    public var releaseSeconds: Double
    public var makeupGainDB: Double

    public init(thresholdDB: Double, headroomDB: Double, attackSeconds: Double, releaseSeconds: Double, makeupGainDB: Double) {
        self.thresholdDB = thresholdDB
        self.headroomDB = headroomDB
        self.attackSeconds = attackSeconds
        self.releaseSeconds = releaseSeconds
        self.makeupGainDB = makeupGainDB
    }

    func isApproximatelyEqual(to other: CompressorParams) -> Bool {
        abs(thresholdDB - other.thresholdDB) < 0.05
            && abs(headroomDB - other.headroomDB) < 0.05
            && abs(attackSeconds - other.attackSeconds) < 0.00005
            && abs(releaseSeconds - other.releaseSeconds) < 0.0005
            && abs(makeupGainDB - other.makeupGainDB) < 0.05
    }

    /// Ranges for the Developer Mode controls, matching DynamicsProcessor limits.
    public static let thresholdRange: ClosedRange<Double> = -40...20
    public static let headroomRange: ClosedRange<Double> = 0.1...40
    public static let attackRange: ClosedRange<Double> = 0.0001...0.2
    public static let releaseRange: ClosedRange<Double> = 0.01...3
    public static let makeupRange: ClosedRange<Double> = -40...40
}

public enum EQBandKind: String, Codable, Sendable {
    case lowShelf
    case parametric
    case highShelf
}

public struct EQBandParams: Codable, Equatable, Sendable {
    public var kind: EQBandKind
    public var frequency: Double
    public var gainDB: Double
    /// Bandwidth in octaves (parametric band only; ignored by shelves).
    public var bandwidthOctaves: Double

    public init(kind: EQBandKind, frequency: Double, gainDB: Double, bandwidthOctaves: Double) {
        self.kind = kind
        self.frequency = frequency
        self.gainDB = gainDB
        self.bandwidthOctaves = bandwidthOctaves
    }

    func isApproximatelyEqual(to other: EQBandParams) -> Bool {
        kind == other.kind
            && abs(frequency - other.frequency) < 0.5
            && abs(gainDB - other.gainDB) < 0.05
            && abs(bandwidthOctaves - other.bandwidthOctaves) < 0.01
    }

    public static let frequencyRange: ClosedRange<Double> = 20...20_000
    public static let gainRange: ClosedRange<Double> = -24...24
    public static let bandwidthRange: ClosedRange<Double> = 0.05...5
}

/// Mirrors the AVAudioUnitReverbPreset cases the app offers, so the core stays AVFoundation-free.
public enum ReverbPresetChoice: String, Codable, CaseIterable, Sendable {
    case smallRoom, mediumRoom, largeRoom, mediumHall, largeHall, plate, mediumChamber, largeChamber, cathedral

    public var displayName: String {
        switch self {
        case .smallRoom: return "Small Room"
        case .mediumRoom: return "Medium Room"
        case .largeRoom: return "Large Room"
        case .mediumHall: return "Medium Hall"
        case .largeHall: return "Large Hall"
        case .plate: return "Plate"
        case .mediumChamber: return "Medium Chamber"
        case .largeChamber: return "Large Chamber"
        case .cathedral: return "Cathedral"
        }
    }
}

public struct ReverbParams: Codable, Equatable, Sendable {
    public var preset: ReverbPresetChoice
    /// 0...100, as AVAudioUnitReverb.wetDryMix.
    public var wetDryMix: Double

    public init(preset: ReverbPresetChoice, wetDryMix: Double) {
        self.preset = preset
        self.wetDryMix = wetDryMix
    }

    func isApproximatelyEqual(to other: ReverbParams) -> Bool {
        preset == other.preset && abs(wetDryMix - other.wetDryMix) < 0.05
    }
}
