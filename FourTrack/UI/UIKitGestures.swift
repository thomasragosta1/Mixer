import SwiftUI
import UIKit

/// A pan that only starts when the finger moves sideways, so an up-or-down
/// drag that starts on it still scrolls the list it sits in. (On iOS 18 and
/// later, SwiftUI's own drag and magnify gestures inside a ScrollView stop
/// the list from scrolling.)
@available(iOS 18.0, *)
struct HorizontalPan: UIGestureRecognizerRepresentable {
    /// Called with the horizontal distance moved since the pan began.
    var onChange: (CGFloat) -> Void
    var onEnd: () -> Void

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        return pan
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        switch recognizer.state {
        case .began, .changed:
            onChange(recognizer.translation(in: recognizer.view).x)
        case .ended, .cancelled, .failed:
            onEnd()
        default:
            break
        }
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
            let v = pan.velocity(in: pan.view)
            return abs(v.x) > abs(v.y)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            // Taps and press-and-hold on the card keep working alongside it.
            !(other is UIPanGestureRecognizer)
        }
    }
}

/// Two-finger pinch; one finger never triggers it, so scrolling is untouched.
@available(iOS 18.0, *)
struct PinchRecognizer: UIGestureRecognizerRepresentable {
    /// Called with the scale since the pinch began (1 = unchanged).
    var onChange: (CGFloat) -> Void
    var onEnd: () -> Void

    func makeUIGestureRecognizer(context: Context) -> UIPinchGestureRecognizer {
        let pinch = UIPinchGestureRecognizer()
        pinch.delegate = context.coordinator
        return pinch
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPinchGestureRecognizer, context: Context) {
        switch recognizer.state {
        case .began, .changed:
            onChange(recognizer.scale)
        case .ended, .cancelled, .failed:
            onEnd()
        default:
            break
        }
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}

/// Attaches a SwiftUI gesture alongside the others (iOS 17).
struct SimultaneousGestureModifier<G: Gesture>: ViewModifier {
    let gesture: G
    func body(content: Content) -> some View { content.simultaneousGesture(gesture) }
}

/// Attaches a UIKit recognizer (iOS 18+).
@available(iOS 18.0, *)
struct RecognizerModifier<R: UIGestureRecognizerRepresentable>: ViewModifier {
    let recognizer: R
    func body(content: Content) -> some View { content.gesture(recognizer) }
}

/// Press and hold (0.2 s, within 12 pt), then drag: reports how far the finger
/// has moved vertically since the hold landed and where it is in the window.
/// Moving before the hold lands fails it, so the list scrolls instead.
@available(iOS 18.0, *)
struct HoldAndDrag: UIGestureRecognizerRepresentable {
    var onChange: (CGFloat, CGPoint) -> Void
    var onEnd: () -> Void

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let hold = UILongPressGestureRecognizer()
        hold.minimumPressDuration = 0.2
        hold.allowableMovement = 12
        return hold
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        let location = recognizer.location(in: nil)
        switch recognizer.state {
        case .began:
            context.coordinator.start = location
            onChange(0, location)
        case .changed:
            onChange(location.y - context.coordinator.start.y, location)
        case .ended, .cancelled, .failed:
            onEnd()
        default:
            break
        }
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    final class Coordinator {
        var start = CGPoint.zero
    }
}
