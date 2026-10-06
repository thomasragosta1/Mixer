import Foundation
import MediaPlayer

/// The lock screen / Control Center player: shows the open project and lets
/// play, pause, skip 15 s and the progress bar drive the transport while the
/// phone is locked (the app keeps playing in the background).
@MainActor
final class NowPlaying {
    struct Handlers {
        var play: () -> Bool
        var pause: () -> Bool
        var toggle: () -> Bool
        var skip: (Double) -> Bool
        var seek: (Double) -> Bool
    }

    private var registered: [(MPRemoteCommand, Any)] = []

    func activate(_ handlers: Handlers) {
        deactivate()
        let center = MPRemoteCommandCenter.shared()
        func on(_ command: MPRemoteCommand, _ action: @escaping (MPRemoteCommandEvent) -> Bool) {
            command.isEnabled = true
            let token = command.addTarget { event in
                MainActor.assumeIsolated { action(event) ? .success : .commandFailed }
            }
            registered.append((command, token))
        }
        on(center.playCommand) { _ in handlers.play() }
        on(center.pauseCommand) { _ in handlers.pause() }
        on(center.togglePlayPauseCommand) { _ in handlers.toggle() }
        center.skipBackwardCommand.preferredIntervals = [15]
        center.skipForwardCommand.preferredIntervals = [15]
        on(center.skipBackwardCommand) { _ in handlers.skip(-15) }
        on(center.skipForwardCommand) { _ in handlers.skip(15) }
        on(center.changePlaybackPositionCommand) { event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return false }
            return handlers.seek(e.positionTime)
        }
        center.nextTrackCommand.isEnabled = false
        center.previousTrackCommand.isEnabled = false
    }

    /// Call whenever the transport, position or length changes. While playing,
    /// the system advances the time itself from `elapsed` and the rate.
    func update(title: String, duration: Double, elapsed: Double, playing: Bool, recording: Bool) {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: recording ? "Recording" : "Four-Track",
            MPMediaItemPropertyPlaybackDuration: max(duration, elapsed),
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: playing || recording ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
    }

    func deactivate() {
        for (command, token) in registered {
            command.removeTarget(token)
        }
        registered.removeAll()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
}
