import SwiftUI

/// Press-and-hold gestures nobody can see. Each gets a short tip, shown once
/// ever, the first time the thing it explains is on screen.
enum HoldHint: String, CaseIterable {
    case renameProject
    case dragTrackToBin
    case padSound
    case metronomeHolds

    var text: String {
        switch self {
        case .renameProject: "Press and hold a project to rename it."
        case .dragTrackToBin: "Press and hold a track, then drag it to the bin to delete it."
        case .padSound: "Press and hold a pad to change its sound."
        case .metronomeHolds: "Press and hold the time signature for more choices, or an arrow for 1 BPM steps."
        }
    }
}

/// Which tip is showing. One at a time; each is remembered as seen the moment
/// it appears, so it never comes back.
@Observable
@MainActor
final class Hints {
    static let shared = Hints()

    private(set) var current: HoldHint?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var pending: HoldHint?
    @ObservationIgnored private var lastHidden: Date?
    /// Seconds between one tip going away and the next appearing.
    private static let spacing: TimeInterval = 25

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// UI tests launch with `-hintsDisabled YES` so tips never cover controls.
    private var disabled: Bool { defaults.bool(forKey: "hintsDisabled") }

    private func key(_ hint: HoldHint) -> String { "hintSeen.\(hint.rawValue)" }

    func hasSeen(_ hint: HoldHint) -> Bool { disabled || defaults.bool(forKey: key(hint)) }

    /// Shows the tip after a short beat (so it doesn't land on top of the
    /// screen's own entrance), unless it's been seen or another tip is up.
    /// Tips are spaced out: never two back to back.
    func request(_ hint: HoldHint) {
        guard !hasSeen(hint), current == nil, pending != hint else { return }
        task?.cancel()
        pending = hint
        let sinceLast = lastHidden.map { Date().timeIntervalSince($0) } ?? .infinity
        let delay = max(0.8, Self.spacing - sinceLast)
        task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled, self.current == nil, !self.hasSeen(hint) else { return }
            self.pending = nil
            self.defaults.set(true, forKey: self.key(hint))
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { self.current = hint }
            UIAccessibility.post(notification: .announcement, argument: "Tip: \(hint.text)")
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            self.dismiss()
        }
    }

    /// What the screen wanted to explain went away before its tip appeared.
    func cancelPending() {
        guard current == nil else { return }
        task?.cancel()
        task = nil
        pending = nil
    }

    /// The person did the thing (or tapped the tip): it's done its job.
    func dismiss(_ hint: HoldHint? = nil) {
        if let hint {
            defaults.set(true, forKey: key(hint))
            if pending == hint { cancelPending() }
            guard current == hint else { return }
        }
        task?.cancel()
        task = nil
        if current != nil { lastHidden = Date() }
        withAnimation(.easeOut(duration: 0.2)) { current = nil }
    }

    /// Hides whatever is up when its screen goes away; an unshown pending tip
    /// stays unseen so it can appear next time.
    func screenDisappeared() {
        task?.cancel()
        task = nil
        pending = nil
        if current != nil { lastHidden = Date() }
        current = nil
    }

    /// Settings → Show Tips Again.
    func resetAll() {
        for hint in HoldHint.allCases { defaults.removeObject(forKey: key(hint)) }
    }
}

/// The tip bubble. Tap to dismiss; it also fades on its own.
private struct HintBubble: View {
    let hint: HoldHint

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "hand.tap")
                .foregroundStyle(.tint)
            Text(hint.text)
                .font(.subheadline)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 10, y: 3)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .onTapGesture { Hints.shared.dismiss() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tip: \(hint.text)")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Dismisses the tip")
    }
}

extension View {
    /// Shows any of `hints` that are up as a bubble at the top of this screen.
    func hintBubble(_ hints: Set<HoldHint>) -> some View {
        overlay(alignment: .top) {
            if let hint = Hints.shared.current, hints.contains(hint) {
                HintBubble(hint: hint)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
}
