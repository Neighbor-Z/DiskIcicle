import SwiftUI

#if os(macOS)
import AppKit

// MARK: - FlippedView with trackpad scroll support

class FlippedView: NSView {
    override var isFlipped: Bool { return true }

    /// Called by PanZoomGestureView to wire up the coordinator.
    weak var scrollCoordinator: PanZoomGestureView.Coordinator?

    // Accumulated scroll delta since the last pan call.
    // We accumulate so that we pass a single coherent translation per event,
    // matching the same contract as NSPanGestureRecognizer.
    private var accumulatedDelta: CGPoint = .zero

    // Timer that fires when scroll events stop arriving (after ~150 ms).
    // At that point we commit the pan and call onPanEnded.
    private var scrollEndTimer: Timer?

    override func scrollWheel(with event: NSEvent) {
        // Ignore mouse-wheel (non-trackpad) events so they don't conflict.
        // hasPreciseScrollingDeltas == true for trackpads; false for a mouse wheel.
        guard event.hasPreciseScrollingDeltas else {
            super.scrollWheel(with: event)
            return
        }

        // Ignore the event if the magnification gesture is running —
        // pinch-to-zoom also produces scroll events and we don't want to pan at the same time.
        // (NSMagnificationGestureRecognizer handles that path.)
        if event.phase == .mayBegin || event.momentumPhase == .mayBegin {
            return
        }

        let dx = event.scrollingDeltaX
        let dy = event.scrollingDeltaY

        if dx == 0 && dy == 0 { return }

        accumulatedDelta.x += dx
        accumulatedDelta.y += dy

        scrollCoordinator?.parent.onPan(CGPoint(x: accumulatedDelta.x, y: accumulatedDelta.y))

        // (Re)start the idle timer.
        scheduleScrollEndTimer()
    }

    override func rightMouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        scrollCoordinator?.parent.onSecondaryTap(location)
        super.rightMouseDown(with: event)
    }

    private func scheduleScrollEndTimer() {
        scrollEndTimer?.invalidate()
        scrollEndTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.accumulatedDelta = .zero
            self.scrollCoordinator?.parent.onPanEnded()
        }
    }
}

// MARK: - PanZoomGestureView

struct PanZoomGestureView: NSViewRepresentable {
    var onPan: (CGPoint) -> Void
    var onPanEnded: () -> Void
    var onPinch: (CGFloat, CGPoint) -> Void
    var onPinchEnded: () -> Void
    var onTap: (CGPoint) -> Void
    var onSecondaryTap: (CGPoint) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSView {
        let view = FlippedView()

        // Wire the coordinator so scrollWheel can reach the callbacks.
        view.scrollCoordinator = context.coordinator

        let pan = NSPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pan)

        let mag = NSMagnificationGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleMagnification(_:)))
        mag.delegate = context.coordinator
        view.addGestureRecognizer(mag)

        let click = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleClick(_:)))
        click.numberOfClicksRequired = 1
        click.delegate = context.coordinator
        view.addGestureRecognizer(click)

        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.parent = self
        // Keep the weak reference up to date whenever the view is reused.
        if let flipped = nsView as? FlippedView {
            flipped.scrollCoordinator = context.coordinator
        }
    }

    final class Coordinator: NSObject, NSGestureRecognizerDelegate {
        var parent: PanZoomGestureView

        init(_ parent: PanZoomGestureView) {
            self.parent = parent
        }

        // MARK: Mouse-drag pan (existing behaviour)

        @objc func handlePan(_ gesture: NSPanGestureRecognizer) {
            guard let view = gesture.view else { return }
            let translation = gesture.translation(in: view)
            switch gesture.state {
            case .changed:
                parent.onPan(CGPoint(x: translation.x, y: translation.y))
            case .ended, .cancelled, .failed:
                parent.onPanEnded()
            default:
                break
            }
        }

        // MARK: Pinch-to-zoom

        @objc func handleMagnification(_ gesture: NSMagnificationGestureRecognizer) {
            guard let view = gesture.view else { return }
            let location = gesture.location(in: view)
            let scale = 1.0 + gesture.magnification
            switch gesture.state {
            case .changed:
                parent.onPinch(scale, location)
            case .ended, .cancelled, .failed:
                parent.onPinchEnded()
            default:
                break
            }
        }

        // MARK: Click / tap

        @objc func handleClick(_ gesture: NSClickGestureRecognizer) {
            guard let view = gesture.view else { return }
            let location = gesture.location(in: view)
            parent.onTap(location)
        }

        func gestureRecognizer(_ gestureRecognizer: NSGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: NSGestureRecognizer) -> Bool {
            return true
        }
    }
}
#else
import UIKit

struct PanZoomGestureView: UIViewRepresentable {
    var onPan: (CGPoint) -> Void
    var onPanEnded: () -> Void
    var onPinch: (CGFloat, CGPoint) -> Void
    var onPinchEnded: () -> Void
    var onTap: (CGPoint) -> Void
    var onSecondaryTap: (CGPoint) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pan)

        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        pinch.delegate = context.coordinator
        view.addGestureRecognizer(pinch)

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.numberOfTapsRequired = 1
        tap.numberOfTouchesRequired = 1
        tap.delegate = context.coordinator
        tap.require(toFail: pan)
        view.addGestureRecognizer(tap)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // Critical: Update the coordinator's parent to the latest struct instance
        // so that the closures (onPan, onPinch, etc.) capture the latest state.
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: PanZoomGestureView

        init(_ parent: PanZoomGestureView) {
            self.parent = parent
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            let translation = gesture.translation(in: gesture.view)
            switch gesture.state {
            case .changed:
                parent.onPan(translation)
            case .ended, .cancelled, .failed:
                parent.onPanEnded()
            default:
                break
            }
        }

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            let location = gesture.location(in: gesture.view)
            switch gesture.state {
            case .changed:
                parent.onPinch(gesture.scale, location)
            case .ended, .cancelled, .failed:
                parent.onPinchEnded()
            default:
                break
            }
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            let location = gesture.location(in: gesture.view)
            parent.onTap(location)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            if gestureRecognizer is UIPinchGestureRecognizer || otherGestureRecognizer is UIPinchGestureRecognizer {
                return true
            }
            return false
        }
    }
}
#endif
