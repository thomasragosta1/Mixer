import AVFoundation
import FourTrackCore

/// Owns AVAudioSession configuration, microphone permission, and session-level
/// notifications (interruptions, route changes, media services resets).
@MainActor
final class AudioSessionManager {
    static let shared = AudioSessionManager()

    enum Permission {
        case undetermined, granted, denied
    }

    enum Event {
        case interruptionBegan
        case interruptionEnded(shouldResume: Bool)
        /// The previous output went away (e.g. headphones unplugged).
        case outputDeviceLost
        case routeChanged
        case mediaServicesReset
    }

    var onEvent: ((Event) -> Void)?
    private var observers: [NSObjectProtocol] = []
    private(set) var isConfigured = false

    private var session: AVAudioSession { .sharedInstance() }

    private init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let typeRaw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let optionsRaw = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            MainActor.assumeIsolated {
                guard let typeRaw, let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else { return }
                switch type {
                case .began:
                    self?.onEvent?(.interruptionBegan)
                case .ended:
                    let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw)
                    self?.onEvent?(.interruptionEnded(shouldResume: options.contains(.shouldResume)))
                @unknown default:
                    break
                }
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let reasonRaw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            MainActor.assumeIsolated {
                let reason = reasonRaw.flatMap { AVAudioSession.RouteChangeReason(rawValue: $0) }
                if reason == .oldDeviceUnavailable {
                    self?.onEvent?(.outputDeviceLost)
                } else {
                    self?.onEvent?(.routeChanged)
                }
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isConfigured = false
                self?.onEvent?(.mediaServicesReset)
            }
        })
    }

    /// `.playAndRecord`, mode `.default`, speaker by default, Bluetooth A2DP
    /// allowed; 48 kHz and a ~5 ms IO buffer requested (the system may give
    /// something else; callers read back the actual values).
    func configure() throws {
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP])
        try? session.setPreferredSampleRate(CAFFormat.defaultSampleRate)
        try? session.setPreferredIOBufferDuration(0.005)
        try session.setActive(true)
        // Phone mic is mono; only settable once the session is active.
        try? session.setPreferredInputNumberOfChannels(1)
        isConfigured = true
    }

    func deactivate() {
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        isConfigured = false
    }

    // MARK: Permission

    var permission: Permission {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return .granted
        case .denied: return .denied
        case .undetermined: return .undetermined
        @unknown default: return .undetermined
        }
    }

    /// Asks on first use; returns the resulting state.
    func requestPermission() async -> Bool {
        switch permission {
        case .granted: return true
        case .denied: return false
        case .undetermined: return await AVAudioApplication.requestRecordPermission()
        }
    }

    // MARK: Route

    var currentRoute: AudioRouteKind {
        guard let output = session.currentRoute.outputs.first else { return .other }
        switch output.portType {
        case .builtInSpeaker, .builtInReceiver:
            return .speaker
        case .headphones, .usbAudio, .lineOut:
            return .wired
        case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE:
            return .bluetooth
        default:
            return .other
        }
    }

    var ioBufferDuration: TimeInterval { session.ioBufferDuration }
    var sampleRate: Double { session.sampleRate }
    var inputLatency: TimeInterval { session.inputLatency }
    var outputLatency: TimeInterval { session.outputLatency }
}
