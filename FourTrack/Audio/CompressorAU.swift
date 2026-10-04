import AVFoundation
import AudioToolbox
import FourTrackCore

/// Wraps `CompressorDSP` as an in-process Audio Unit so it sits in the
/// AVAudioEngine graph like Apple's effects, in live playback and in the
/// offline export alike. Parameters are set with `AudioUnitSetParameter`
/// using the addresses below.
final class CompressorAU: AUAudioUnit {
    enum Param: AUParameterAddress, CaseIterable {
        case threshold, ratio, knee, attack, release, makeup
    }

    static let componentDescription = AudioComponentDescription(
        componentType: kAudioUnitType_Effect,
        componentSubType: fourCC("ftcp"),
        componentManufacturer: fourCC("FTrk"),
        componentFlags: 0,
        componentFlagsMask: 0
    )

    /// Registers the unit once per process. Returns false if the system can't
    /// find it afterwards, in which case callers fall back to Apple's DynamicsProcessor.
    static let isRegistered: Bool = {
        AUAudioUnit.registerSubclass(CompressorAU.self, as: componentDescription, name: "Four-Track: Compressor", version: 1)
        var desc = componentDescription
        return AudioComponentFindNext(nil, &desc) != nil
    }()

    private let dsp = CompressorDSP(params: MacroCurves.compressor(Track.defaultCompressor))
    private var inputBus: AUAudioUnitBus
    private var outputBus: AUAudioUnitBus
    private var _inputBusses: AUAudioUnitBusArray!
    private var _outputBusses: AUAudioUnitBusArray!
    private var _parameterTree: AUParameterTree!

    override init(componentDescription: AudioComponentDescription, options: AudioComponentInstantiationOptions = []) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: CAFFormat.defaultSampleRate, channels: 2)!
        let input = try AUAudioUnitBus(format: format)
        let output = try AUAudioUnitBus(format: format)
        input.maximumChannelCount = 2
        output.maximumChannelCount = 2
        inputBus = input
        outputBus = output
        try super.init(componentDescription: componentDescription, options: options)
        _inputBusses = AUAudioUnitBusArray(audioUnit: self, busType: .input, busses: [inputBus])
        _outputBusses = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [outputBus])

        func param(_ p: Param, _ name: String, _ range: ClosedRange<Double>, _ unit: AudioUnitParameterUnit) -> AUParameter {
            AUParameterTree.createParameter(
                withIdentifier: name.lowercased(), name: name, address: p.rawValue,
                min: AUValue(range.lowerBound), max: AUValue(range.upperBound), unit: unit, unitName: nil,
                flags: [.flag_IsReadable, .flag_IsWritable], valueStrings: nil, dependentParameters: nil)
        }
        _parameterTree = AUParameterTree.createTree(withChildren: [
            param(.threshold, "Threshold", CompressorParams.thresholdRange, .decibels),
            param(.ratio, "Ratio", CompressorParams.ratioRange, .ratio),
            param(.knee, "Knee", CompressorParams.kneeRange, .decibels),
            param(.attack, "Attack", CompressorParams.attackRange, .seconds),
            param(.release, "Release", CompressorParams.releaseRange, .seconds),
            param(.makeup, "Makeup", CompressorParams.makeupRange, .decibels),
        ])
        let dsp = self.dsp
        _parameterTree.implementorValueObserver = { param, value in
            let v = Double(value)
            switch Param(rawValue: param.address) {
            case .threshold: dsp.params.thresholdDB = v
            case .ratio: dsp.params.ratio = v
            case .knee: dsp.params.kneeDB = v
            case .attack: dsp.params.attackSeconds = v
            case .release: dsp.params.releaseSeconds = v
            case .makeup: dsp.params.makeupGainDB = v
            case nil: break
            }
        }
        _parameterTree.implementorValueProvider = { param in
            let p = dsp.params
            switch Param(rawValue: param.address) {
            case .threshold: return AUValue(p.thresholdDB)
            case .ratio: return AUValue(p.ratio)
            case .knee: return AUValue(p.kneeDB)
            case .attack: return AUValue(p.attackSeconds)
            case .release: return AUValue(p.releaseSeconds)
            case .makeup: return AUValue(p.makeupGainDB)
            case nil: return 0
            }
        }
        maximumFramesToRender = 4_096
    }

    override var inputBusses: AUAudioUnitBusArray { _inputBusses }
    override var outputBusses: AUAudioUnitBusArray { _outputBusses }
    override var parameterTree: AUParameterTree? {
        get { _parameterTree }
        set { /* fixed tree */ }
    }
    override var canProcessInPlace: Bool { true }

    override func allocateRenderResources() throws {
        try super.allocateRenderResources()
        guard outputBus.format.channelCount == inputBus.format.channelCount else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(kAudioUnitErr_FailedInitialization))
        }
        dsp.reset(sampleRate: outputBus.format.sampleRate)
    }


    override var internalRenderBlock: AUInternalRenderBlock {
        let dsp = self.dsp
        return { _, timestamp, frameCount, _, outputData, _, pullInputBlock in
            guard let pullInputBlock else { return kAudioUnitErr_NoConnection }
            // In-place processing: pull the input straight into the output
            // buffer list (upstream fills our buffers, or hands us its own when
            // mData is nil), then compress those samples where they are.
            let outList = UnsafeMutableAudioBufferListPointer(outputData)
            for i in 0..<outList.count {
                outList[i].mDataByteSize = frameCount * UInt32(MemoryLayout<Float>.size)
            }
            var pullFlags = AudioUnitRenderActionFlags()
            let status = pullInputBlock(&pullFlags, timestamp, frameCount, 0, outputData)
            guard status == noErr else { return status }
            guard let left = outList.first?.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            let right = outList.count > 1 ? outList[1].mData?.assumingMemoryBound(to: Float.self) : nil
            dsp.process(left, right, frames: Int(frameCount))
            return noErr
        }
    }
}

private func fourCC(_ s: String) -> OSType {
    s.utf8.prefix(4).reduce(0) { ($0 << 8) | OSType($1) }
}
