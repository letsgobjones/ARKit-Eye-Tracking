//
//  ContentView.swift
//  ARKitPractice
//
//  Created by Brandon Jones on 11/9/2026.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    //    @State keeps one tracker alive for the life of this view.
    @State private var tracker = EyeTracker()
    var body: some View {
        VStack(spacing: 32) {

            // On devices without FaceID, explain why nothing happens.
            if !EyeTracker.isSupported {
                ContentUnavailableView("Face Tracking Unavailable", systemImage: "faceid", description: Text("This device has no TrueDepth camera.")
                )
            } else {
                // Big arrow showing the current direction.
                Image(systemName: tracker.direction.symbol)
                    .font(.largeTitle)
                //Animates smoothly when the sysmol changes
                    .contentTransition(.symbolEffect(.replace))

                // The message you asked for.
                Text(tracker.direction.rawValue)
                    .font(.largeTitle)
                    .fontWeight(.bold)

                // Debug bars: vary useful fortuning the treshold.
                VStack(alignment: .leading, spacing: 16) {
                    debugRow("Up", tracker.lookUp)
                    debugRow("Down", tracker.lookDown)
                    debugRow("Left", tracker.lookLeft)
                    debugRow("Right", tracker.lookRight)

                }
                .padding()

            }
        }
        .padding()
        .animation(.easeInOut(duration: 0.2), value: tracker.direction)
        // Start the camera when the view appears, stop it when it goes way.
        .onAppear {tracker.start()}
        .onDisappear{tracker.stop()}
    }

    // One labeled progress bar for 0...1 value/
    private func debugRow(_ label: String, _ value: Float) -> some View {
        HStack {
            Text(label)
                .frame(width: 60, alignment: .leading)

            ProgressView(value: Double(value))

            Text(value, format: .number.precision(.fractionLength(2)))
                .monospacedDigit()
                .frame(width: 44)
        }
    }
}

#Preview {
    ContentView()
}
