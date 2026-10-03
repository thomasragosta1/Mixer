import AVFoundation
import AudioToolbox
import FourTrackCore

/// Audio formats used throughout the engine.
enum EngineFormat {
    static let sampleRate = CAFFormat.defaultSampleRate
    /// Track files and players: 48 kHz Float32 non-interleaved mono.
    static let mono = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    /// Effects and mixing run in stereo so reverb has width; tracks stay centered.
    static let stereo = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
}

/// One track's processing chain:
///
///     playerDry ┐
///               ├─> cleanupMix -> EQ -> Compressor -> Warmth -> Reverb -> trackMixer
///     playerClean┘
///
/// `playerClean` plays the full-strength Cleanup render; the Cleanup slider
/// sets the two players' volumes. Built once per project open and only
/// re-parameterized afterwards.
final class TrackChain {
    let index: Int
    let playerDry = AVAudioPlayerNode()
    let playerClean = AVAudioPlayerNode()
    let cleanupMix = AVAudioMixerNode()
    let eq = AVAudioUnitEQ(numberOfBands: 3)
    let compressor = AVAudioUnitEffect(audioComponentDescription: AudioComponentDescription(
        componentType: kAudioUnitType_Effect,
        componentSubType: kAudioUnitSubType_DynamicsProcessor,
        componentManufacturer: kAudioUnitManufacturer_Apple,
        componentFlags: 0,
        componentFlagsMask: 0
    ))
    let warmth = AVAudioUnitDistortion()
    let reverb = AVAudioUnitReverb()
    let trackMixer = AVAudioMixerNode()

    private(set) var file: AVAudioFile?
    private(set) var cleanFile: AVAudioFile?
    private var appliedReverbPreset: ReverbPresetChoice?
    private var appliedWarmthEnabled: Bool?

    init(index: Int) {
        self.index = index
        warmth.loadFactoryPreset(.multiDistortedCubed)
        warmth.bypass = true
    }

    var nodes: [AVAudioNode] {
        [playerDry, playerClean, cleanupMix, eq, compressor, warmth, reverb, trackMixer]
    }

    func attach(to engine: AVAudioEngine) {
        nodes.forEach { engine.attach($0) }
    }

    /// Wires the chain internally. The caller connects `trackMixer` onward.
    func connect(in engine: AVAudioEngine) {
        engine.connect(playerDry, to: cleanupMix, fromBus: 0, toBus: 0, format: EngineFormat.mono)
        engine.connect(playerClean, to: cleanupMix, fromBus: 0, toBus: 1, format: EngineFormat.mono)
        engine.connect(cleanupMix, to: eq, format: EngineFormat.stereo)
        engine.connect(eq, to: compressor, format: EngineFormat.stereo)
        engine.connect(compressor, to: warmth, format: EngineFormat.stereo)
        engine.connect(warmth, to: reverb, format: EngineFormat.stereo)
        engine.connect(reverb, to: trackMixer, format: EngineFormat.stereo)
    }

    // MARK: Files

    /// Opens (or closes) the take and its Cleanup render. Call after every splice.
    func load(audioURL: URL?, cleanedURL: URL?) {
        file = audioURL.flatMap { try? AVAudioFile(forReading: $0, commonFormat: .pcmFormatFloat32, interleaved: false) }
        cleanFile = cleanedURL.flatMap { try? AVAudioFile(forReading: $0, commonFormat: .pcmFormatFloat32, interleaved: false) }
    }

    var lengthFrames: AVAudioFramePosition { file?.length ?? 0 }

    /// Schedules the take from `startFrame` on both players. Returns false if
    /// there is nothing to play from that point.
    @discardableResult
    func schedule(from startFrame: AVAudioFramePosition) -> Bool {
        playerDry.stop()
        playerClean.stop()
        guard let file, startFrame < file.length else { return false }
        let count = AVAudioFrameCount(file.length - startFrame)
        playerDry.scheduleSegment(file, startingFrame: startFrame, frameCount: count, at: nil)
        if let cleanFile, startFrame < cleanFile.length {
            let cleanCount = AVAudioFrameCount(cleanFile.length - startFrame)
            playerClean.scheduleSegment(cleanFile, startingFrame: startFrame, frameCount: cleanCount, at: nil)
        }
        return true
    }

    func play(at time: AVAudioTime?) {
        playerDry.play(at: time)
        if cleanFile != nil {
            playerClean.play(at: time)
        }
    }

    func stop() {
        playerDry.stop()
        playerClean.stop()
    }

    // MARK: Parameters

    /// Pushes a track's stored slider values (or Developer Mode overrides) into
    /// the DSP nodes. `audible` folds in mute and solo.
    func apply(_ track: Track, audible: Bool, warmthEnabled: Bool) {
        // Cleanup blend. Without a render, the original plays at full level.
        let blend = MacroCurves.cleanupBlend(cleanFile == nil ? 0 : track.cleanup)
        playerDry.volume = Float(blend.dry)
        playerClean.volume = Float(blend.wet)

        // EQ
        let bands = track.resolvedEQ
        for (i, params) in bands.prefix(eq.bands.count).enumerated() {
            let band = eq.bands[i]
            switch params.kind {
            case .lowShelf: band.filterType = .lowShelf
            case .parametric: band.filterType = .parametric
            case .highShelf: band.filterType = .highShelf
            }
            band.frequency = Float(params.frequency)
            band.gain = Float(params.gainDB)
            band.bandwidth = Float(params.bandwidthOctaves)
            band.bypass = false
        }
        eq.globalGain = 0

        // Compressor
        let c = track.resolvedCompressor
        setCompressor(kDynamicsProcessorParam_Threshold, c.thresholdDB)
        setCompressor(kDynamicsProcessorParam_HeadRoom, c.headroomDB)
        setCompressor(kDynamicsProcessorParam_AttackTime, c.attackSeconds)
        setCompressor(kDynamicsProcessorParam_ReleaseTime, c.releaseSeconds)
        setCompressor(kDynamicsProcessorParam_OverallGain, c.makeupGainDB)
        setCompressor(kDynamicsProcessorParam_ExpansionRatio, 1)

        // Warmth (post-v1, behind a flag)
        var trimDB = 0.0
        if warmthEnabled && track.warmth > 0 {
            let w = MacroCurves.warmth(track.warmth)
            warmth.bypass = false
            warmth.preGain = Float(w.preGainDB)
            warmth.wetDryMix = Float(w.wetDryMix)
            trimDB = w.outputTrimDB
        } else {
            warmth.bypass = true
        }

        // Space
        let r = track.resolvedReverb
        if appliedReverbPreset != r.preset {
            reverb.loadFactoryPreset(r.preset.avPreset)
            appliedReverbPreset = r.preset
        }
        reverb.wetDryMix = Float(r.wetDryMix)
        reverb.bypass = r.wetDryMix <= 0

        // Volume, mute, solo: silenced tracks keep their fader value.
        let gain = audible ? MacroCurves.volumeGain(track.volume) * MacroCurves.dbToGain(trimDB) : 0
        trackMixer.outputVolume = Float(gain)
    }

    private func setCompressor(_ param: AudioUnitParameterID, _ value: Double) {
        AudioUnitSetParameter(compressor.audioUnit, param, kAudioUnitScope_Global, 0, AudioUnitParameterValue(value), 0)
    }
}

extension ReverbPresetChoice {
    var avPreset: AVAudioUnitReverbPreset {
        switch self {
        case .smallRoom: return .smallRoom
        case .mediumRoom: return .mediumRoom
        case .largeRoom: return .largeRoom
        case .mediumHall: return .mediumHall
        case .largeHall: return .largeHall
        case .plate: return .plate
        case .mediumChamber: return .mediumChamber
        case .largeChamber: return .largeChamber
        case .cathedral: return .cathedral
        }
    }
}

/// Master section: sum of tracks -> master volume -> peak limiter. The limiter
/// guarantees that no macro combination can clip the output or the export.
final class MasterChain {
    let mixer = AVAudioMixerNode()
    let limiter = AVAudioUnitEffect(audioComponentDescription: AudioComponentDescription(
        componentType: kAudioUnitType_Effect,
        componentSubType: kAudioUnitSubType_PeakLimiter,
        componentManufacturer: kAudioUnitManufacturer_Apple,
        componentFlags: 0,
        componentFlagsMask: 0
    ))

    func attach(to engine: AVAudioEngine) {
        engine.attach(mixer)
        engine.attach(limiter)
    }

    /// Connects every track chain into the master and the master into the
    /// engine's main mixer.
    func connect(tracks: [TrackChain], in engine: AVAudioEngine) {
        for chain in tracks {
            engine.connect(chain.trackMixer, to: mixer, fromBus: 0, toBus: chain.index, format: EngineFormat.stereo)
        }
        engine.connect(mixer, to: limiter, format: EngineFormat.stereo)
        engine.connect(limiter, to: engine.mainMixerNode, fromBus: 0, toBus: 0, format: EngineFormat.stereo)
        // Ceiling just under full scale.
        AudioUnitSetParameter(limiter.audioUnit, kLimiterParam_PreGain, kAudioUnitScope_Global, 0, 0, 0)
    }

    func apply(masterVolume: Double) {
        mixer.outputVolume = Float(MacroCurves.volumeGain(masterVolume))
    }
}
