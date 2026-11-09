//
//  EyeTracker.swift
//  ARKitPractice
//
//  Created by Brandon Jones on 11/9/2026.
//

import SwiftUI
import ARKit
//import Observation


// The five possible directions, plus "not tracking".
// `String` raw values give us easy text to show on screen.
enum GazeDirection: String {
    case center = "Looking Center"
    case up = "Looking Up"
    case down = "Looking Down"
    case left = "Looking Left"
    case right = "Looking Right"
    case noFace = "No Face Detected"


    // An SF Symbol for each direction, purely for fun in the UI.
    var symbol: String {
        switch self {
        case .center: "eye"
        case .up: "arrow.up"
        case .down: "arrow.down"
        case .left: "arrow.left"
        case .right: "arrow.right"
        case .noFace: "eye.slash"
        }
    }
}

// @Obervable lets SwiftUI atomomatically refresh whenever one of these properies changes.
// NSObject is required because ARSessionDelegate is an Objective-C protocol.
@Observable
final class EyeTracker: NSObject, ARSessionDelegate {

    // MARK: - Values the UI reads

    // The current direction the eyes are looking.
    var direction: GazeDirection = .noFace

    // Raw 0...1 values, handy for seeing what ARKit is reporting.
    var lookUp: Float = 0
    var lookDown: Float = 0
    var lookLeft: Float = 0
    var lookRight: Float = 0

    // MARK: - Private

    // The session that runs the camera and face tracking.
    private let session = ARSession()

    // How strong a blend-shape value must be before we count it.
    // Lower = more sensitive.

    // TODO: Tune this after testing on your device.
    private let threshold: Float = 0.4

    // ARKit only supports face tracking on TrueDepth (Face ID) devices.
    // Check this begore trying to start, so we dom't crash on other hardware.
    static var isSupported: Bool {
        ARFaceTrackingConfiguration.isSupported
    }

    // MARK: - Start/ Stop

    func start() {
        guard Self.isSupported else { return }

        // Tell the session to send its updates to this object.
        session.delegate = self

        // Create the face-tracking configuration and run it.
        // resetTracking + removeExisitingAnchors gives us a clean start each time.

        let configuration = ARFaceTrackingConfiguration()
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    func stop() {
        // Pausing turns the camera off and saves battery.
        session.pause()
    }

    // MARK: - ARSessionDelegate

    // ARKit calls this every time an anchor (here, your face) updates, roughly 60 times per second.

    // `nonisolated` is needed because this project runs everything on the MainActor by default, but ARKit's delegate method aren't tied to it.
    nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {

        // Find the face anchor amoung the updated anchors.
        guard let face = anchors.compactMap({$0 as? ARFaceAnchor}).first else { return }

// If ARKit lost track of the face (it turned away, or it's too dark), report "no fac" and stop here
        guard face.isTracked else {
            Task { @MainActor in self.direction = .noFace}
            return
        }

        // Small helper that reads one blend shape as Float (0 if missing).
        let shapes = face.blendShapes
        func value(_ key: ARFaceAnchor.BlendShapeLocation) ->Float {
            shapes[key]?.floatValue ?? 0
        }

        // Comine both eyes into one value per direction by averaging the,
        // Up abd down are simple: both eyes move the same way.
        let up = (value(.eyeLookUpLeft) + value(.eyeLookUpRight)) / 2
        let down = (value(.eyeLookDownLeft) + value(.eyeLookDownRight)) / 2

        // Left and right are trickier. The front camera sees you like a mirror,
        // so ARKit's "Left"/"Right" blend shapes come out flipped compared to
        // YOUR left and right. Tested on device: looking to YOUR left raises
        //   - eyeLookInLeft  (ARKit's "left" eye turns in)
        //   - eyeLookOutRight (ARKit's "right" eye turns out)
        let left = (value(.eyeLookInLeft) + value(.eyeLookOutRight)) / 2
        let right = (value(.eyeLookOutLeft) + value(.eyeLookInRight)) / 2

        // Hop to the main actor to update properties the UI is watching.
        // We pass only plain Floats across, never the ARFaceAnchor itself.
        Task { @MainActor in
            self.update(up: up, down: down, left: left, right: right)

        }

    }

    // MARK: - Direction logic

    private func update(up: Float, down: Float, left: Float, right: Float) {
        // Dave the raw values so the UI can show them.
        lookUp = up
        lookDown = down
        lookLeft = left
        lookRight = right

        // Pair each direction with its strength, then pick the strongest.
        let candidates: [(GazeDirection, Float)] = [
            (.up, up), (.down, down), (.left, left), (.right, right)
        ]
        // `max` returns an optional because an empty array has no max.
        // Our array is never empty, but `guard let` handles it safely anyway.
        guard let strongest = candidates.max(by: { $0.1 < $1.1 }) else {
            direction = .center
            return
        }

        // Only commit to a direction if it's past the threshold.
        // Otherwise the eyes are roughly centered.
        direction = strongest.1 > threshold ? strongest.0 : .center

    }
}
