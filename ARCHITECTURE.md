# Architecture

A line-by-line walkthrough of how ARKitPractice tracks your eyes and shows which direction you're looking.

---

## The big picture

The app has three files, and each has one job:

| File | Job |
|---|---|
| `ARKitPracticeApp.swift` | Starts the app and shows the first screen |
| `EyeTracker.swift` | Talks to the camera and ARKit, and works out where you're looking |
| `ContentView.swift` | Shows the arrow, the message and the debug bars |

This is what happens every frame, about 60 times per second:

```
Camera sees your face
   ↓
ARKit measures your face → ARFaceAnchor (with blend shapes)
   ↓
EyeTracker.session(_:didUpdate:) reads the eye values
   ↓
EyeTracker.update(...) picks a direction
   ↓
direction changes → @Observable tells SwiftUI
   ↓
ContentView redraws with the new arrow and text
```

### Key ARKit ideas

- **`ARSession`** runs the camera and does the tracking. It doesn't need a camera preview on screen.
- **`ARFaceTrackingConfiguration`** tells the session to use the front TrueDepth camera and track a face.
- Every frame, ARKit hands over an **`ARFaceAnchor`**, which describes the face it sees.
- The anchor has **blend shapes**: about 50 values from 0.0 to 1.0, one per facial movement. Eight describe the eyes:
  - `eyeLookUpLeft`, `eyeLookUpRight`
  - `eyeLookDownLeft`, `eyeLookDownRight`
  - `eyeLookInLeft`, `eyeLookInRight` (eye turned toward the nose)
  - `eyeLookOutLeft`, `eyeLookOutRight` (eye turned toward the ear)
- When a value goes past a threshold (0.4), the app decides you're looking that way.

---

# Part 1: `ARKitPracticeApp.swift`

```swift
@main
struct ARKitPracticeApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

- **`@main`** marks where the app starts. iOS runs this first.
- **`App`** is the protocol every SwiftUI app conforms to.
- **`WindowGroup`** is the app's window. Whatever is inside it is the first screen.
- **`ContentView()`** is the screen.

---

# Part 2: `EyeTracker.swift`

## 2.1 Imports

```swift
import SwiftUI
import ARKit
```

- **ARKit** provides `ARSession`, `ARFaceAnchor` and the blend shapes.
- **SwiftUI** is here because `@Observable` comes with it. (`import Observation` alone would also work.)

## 2.2 The `GazeDirection` enum

```swift
enum GazeDirection: String {
    case center = "Looking Center"
    case up = "Looking Up"
    case down = "Looking Down"
    case left = "Looking Left"
    case right = "Looking Right"
    case noFace = "No Face Detected"
```

- An **enum** is a fixed list of choices. The direction can only ever be one of these six.
- **`: String`** gives each case a **raw value**, the text after the `=`. `GazeDirection.up.rawValue` is `"Looking Up"`. That's how `ContentView` gets its message: `Text(tracker.direction.rawValue)`.

```swift
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
```

- This is a **computed property**. It doesn't store anything; it works out an answer each time it's asked.
- **`switch self`** means "look at which case I am."
- Each string is an **SF Symbol** name (Apple's built-in icons). `Image(systemName: "arrow.up")` draws an up arrow.
- Swift forces a `switch` to cover **every** case. If a new case like `.upLeft` is added, Xcode errors until it gets a symbol.

**This enum is a model:** plain data with no behavior.

## 2.3 The class declaration

```swift
@Observable
final class EyeTracker: NSObject, ARSessionDelegate {
```

- **`@Observable`** makes SwiftUI watch this object. When a property a view reads changes, SwiftUI redraws that view automatically.
- **`final`** means nothing can subclass this.
- **`class`** (not `struct`) because we want **one shared object** that lives for a while and changes over time. ARKit also needs a class to call back to.
- **`NSObject`** is the Objective-C base class. ARKit is an Objective-C framework, and its delegate protocol requires it.
- **`ARSessionDelegate`** is a promise: "I can receive updates from an `ARSession`." That's why ARKit is allowed to call `session(_:didUpdate:)` on us.

### What is a delegate?

A delegate is the pattern of "**you do the work, and tell me when something happens.**" The `ARSession` runs the camera and measures the face. Whenever it has news, it calls a method on its delegate, which is `EyeTracker`.

## 2.4 Values the UI reads

```swift
var direction: GazeDirection = .noFace

var lookUp: Float = 0
var lookDown: Float = 0
var lookLeft: Float = 0
var lookRight: Float = 0
```

- These are the **outputs** of `EyeTracker`. `ContentView` reads them.
- They start at `.noFace` and `0` because nothing is known until the camera starts.
- **`Float`** is a decimal number. ARKit gives blend shapes as 0.0 to 1.0.
- Because the class is `@Observable`, changing any of these redraws the screen.

## 2.5 The private section

```swift
private let session = ARSession()
private let threshold: Float = 0.4
```

- **`private`** means only code inside `EyeTracker` can use these. `ContentView` sees only the results, not the machinery.
- **`ARSession`** is the engine that runs the camera and tracking.
- **`threshold`** is the minimum strength to count as "looking that way." At 0.4, the eyes must be about 40% of the way toward a direction.

## 2.6 Checking for support

```swift
static var isSupported: Bool {
    ARFaceTrackingConfiguration.isSupported
}
```

- **`static`** means it belongs to the **type**, not an instance. It's called as `EyeTracker.isSupported` without creating a tracker.
- It's `true` only on Face ID devices. `ContentView` uses it to show "Face Tracking Unavailable."

## 2.7 `start()`

```swift
func start() {
    guard Self.isSupported else { return }
    session.delegate = self
    let configuration = ARFaceTrackingConfiguration()
    session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
}
```

1. **`guard ... else { return }`** means "if this isn't true, leave now." On an unsupported device, the method stops here.
2. **`session.delegate = self`** tells the session, "send your news to me." Without it, `session(_:didUpdate:)` is never called.
3. **`ARFaceTrackingConfiguration()`** is the settings that say "use the front TrueDepth camera and track a face."
4. **`session.run(...)`** turns the camera on and starts tracking.
   - `.resetTracking` starts fresh.
   - `.removeExistingAnchors` clears old face data.

## 2.8 `stop()`

```swift
func stop() {
    session.pause()
}
```

This turns the camera off, which saves battery and turns off the green camera light.

## 2.9 The delegate method (the heart of the app)

```swift
nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
```

- ARKit calls this **about 60 times a second** while a face is visible.
- **`anchors`** is a list of things ARKit is tracking. In face tracking, it's the face.
- **`nonisolated`**: this project runs all code on the **MainActor** (the main thread, where UI lives) by default, but ARKit's delegate methods aren't tied to the main thread. `nonisolated` lets the method run anywhere. The tradeoff is that it can't directly change our properties, so it uses `Task { @MainActor in ... }` to hop back.

### Step A: Find the face

```swift
guard let face = anchors.compactMap({ $0 as? ARFaceAnchor }).first else { return }
```

- **`$0`** means "each item in the list."
- **`as? ARFaceAnchor`** tries to treat the item as a face anchor, giving `nil` if it isn't one.
- **`compactMap`** runs that on every item and **drops the `nil`s**.
- **`.first`** takes the first one, or `nil` if there's none.
- **`guard let ... else { return }`**: no face means leave.

### Step B: Is the face actually being tracked?

```swift
guard face.isTracked else {
    Task { @MainActor in self.direction = .noFace }
    return
}
```

- ARKit can still have a face anchor after it has **lost sight** of the face (turned away, camera covered, too dark). `isTracked` says whether the data is current.
- If not tracked, set `.noFace` and leave.
- **`Task { @MainActor in ... }`** runs that small piece of code on the main thread, because UI-watched properties must change there.

### Step C: The helper function

```swift
let shapes = face.blendShapes
func value(_ key: ARFaceAnchor.BlendShapeLocation) -> Float {
    shapes[key]?.floatValue ?? 0
}
```

- **`blendShapes`** is a **dictionary**: a lookup from "which facial movement" to "how much (0 to 1)."
- A function **inside** a function is allowed. It's a helper used only here.
- **`shapes[key]`** might be missing, so it's optional.
- **`?.floatValue`** converts it to `Float` if it exists.
- **`?? 0`** (nil-coalescing) uses 0 if anything was missing, with no force unwrap.

### Step D: Up and down

```swift
let up = (value(.eyeLookUpLeft) + value(.eyeLookUpRight)) / 2
let down = (value(.eyeLookDownLeft) + value(.eyeLookDownRight)) / 2
```

- Each eye has its own value, so we **average** them.
- Averaging smooths noise: if one eye reads oddly for a frame, the other balances it.
- Up and down are easy because **both eyes move the same way**.

### Step E: Left and right (the tricky one)

```swift
let left = (value(.eyeLookInLeft) + value(.eyeLookOutRight)) / 2
let right = (value(.eyeLookOutLeft) + value(.eyeLookInRight)) / 2
```

Looking sideways, **the eyes move in opposite ways relative to the nose**:

```
Looking to one side:
   👁️ one eye turns OUT (toward its ear)
   👁️ the other eye turns IN (toward the nose)
```

So "looking left" combines one eye's **In** value with the other eye's **Out** value.

**Why it looks flipped:** ARKit's "Left" and "Right" names are mirrored compared to your own body, like looking in a mirror. The first version assumed they matched your body and came out backwards on a real device, so the formulas were swapped. **Always test on real hardware.**

### Step F: Send results to the main thread

```swift
Task { @MainActor in
    self.update(up: up, down: down, left: left, right: right)
}
```

- Hop to the main thread to update UI properties.
- Only **four plain numbers** are sent, not the `face` object. Plain numbers are safe to pass between threads; complex ARKit objects might not be.

## 2.10 `update(...)`: choosing a direction

```swift
private func update(up: Float, down: Float, left: Float, right: Float) {
    lookUp = up
    lookDown = down
    lookLeft = left
    lookRight = right
```

This saves the raw numbers so the debug bars can show them.

```swift
    let candidates: [(GazeDirection, Float)] = [
        (.up, up), (.down, down), (.left, left), (.right, right)
    ]
```

- An **array of tuples**. A tuple is a small bundle: `(direction, strength)`.
- `.0` is the direction and `.1` is the strength.

```swift
    guard let strongest = candidates.max(by: { $0.1 < $1.1 }) else {
        direction = .center
        return
    }
```

- **`max(by:)`** finds the biggest item using your rule for "bigger."
- **`{ $0.1 < $1.1 }`** compares two items by strength.
- `max` returns an **optional** (an empty array has no max), so `guard let` handles it safely instead of `!`.

```swift
    direction = strongest.1 > threshold ? strongest.0 : .center
}
```

- **Ternary operator**: `condition ? ifTrue : ifFalse`.
- In plain English: if the strongest direction is above 0.4, use it; otherwise say center.

**Example:** with up = 0.1, down = 0.05, left = 0.7 and right = 0.02, the strongest is `(.left, 0.7)`. Since 0.7 > 0.4, the direction is **`.left`**.

---

# Part 3: `ContentView.swift`

## 3.1 Owning the tracker

```swift
@State private var tracker = EyeTracker()
```

- **`@State`** tells SwiftUI to **keep this object alive** for as long as the view exists.
- SwiftUI rebuilds views often. Without `@State`, a new `EyeTracker` could be created on every redraw, restarting the camera constantly.

## 3.2 Layout

```swift
VStack(spacing: 32) {
```

**`VStack`** stacks things **vertically**, with 32 points between them.

## 3.3 The unsupported-device check

```swift
if !EyeTracker.isSupported {
    ContentUnavailableView("Face Tracking Unavailable", systemImage: "faceid",
                           description: Text("This device has no TrueDepth camera."))
} else {
```

- **`!`** here means "not" (different from a force unwrap).
- **`ContentUnavailableView`** is Apple's ready-made "nothing to show here" screen.
- The Simulator shows this.

## 3.4 The arrow

```swift
Image(systemName: tracker.direction.symbol)
    .font(.largeTitle)
    .contentTransition(.symbolEffect(.replace))
```

- Reads `tracker.direction.symbol`, such as `"arrow.left"`.
- **`.font`** sets the icon size (SF Symbols scale like text).
- **`.contentTransition(.symbolEffect(.replace))`** animates the symbol change instead of snapping.

## 3.5 The message

```swift
Text(tracker.direction.rawValue)
    .font(.largeTitle)
    .fontWeight(.bold)
```

Shows `"Looking Left"` and so on, the enum's raw value.

## 3.6 Debug bars

```swift
VStack(alignment: .leading, spacing: 16) {
    debugRow("Up", tracker.lookUp)
    debugRow("Down", tracker.lookDown)
    debugRow("Left", tracker.lookLeft)
    debugRow("Right", tracker.lookRight)
}
```

`debugRow` is a function that returns a view, which avoids copy-pasting the same row four times.

## 3.7 Modifiers on the whole screen

```swift
.padding()
.animation(.easeInOut(duration: 0.2), value: tracker.direction)
.onAppear { tracker.start() }
.onDisappear { tracker.stop() }
```

- **`.padding()`** adds space around the edges.
- **`.animation(..., value: tracker.direction)`** animates changes **only when `direction` changes**, over 0.2 seconds.
- **`.onAppear`** turns the camera on when the screen appears.
- **`.onDisappear`** turns it off when the screen goes away.

## 3.8 The `debugRow` helper

```swift
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
```

- **`-> some View`** means "returns some kind of view," and Swift works out the exact type.
- **`HStack`** lays things out **horizontally**: label, bar, number.
- **`.frame(width: 60)`** gives the label a fixed width so the bars line up.
- **`ProgressView(value:)`** is a 0 to 1 bar. It needs a `Double`, hence `Double(value)`.
- **`.fractionLength(2)`** shows 2 decimal places, such as `0.73`.
- **`.monospacedDigit()`** makes every digit the same width so numbers don't jiggle.

---

# Part 4: Model, view model and view

| Piece | Role | Why |
|---|---|---|
| `GazeDirection` | **Model** | Plain data. It doesn't know about ARKit or the UI. |
| `EyeTracker` | **View model** (or service) | Turns raw camera data into simple values the screen can show. |
| `ContentView` | **View** | Only displays things. It does no math. |

This separation means the UI could be swapped completely without changing `EyeTracker`, or ARKit could be replaced with CoreML later without changing `ContentView`.

---

# Part 5: Swift concepts used

| Concept | Where | Meaning |
|---|---|---|
| `enum` with raw values | `GazeDirection` | Fixed set of choices, each with attached text |
| Computed property | `symbol` | Calculated on demand, not stored |
| `switch` | `symbol` | Pick code based on a value; must cover every case |
| `@Observable` | `EyeTracker` | SwiftUI redraws when properties change |
| `@State` | `ContentView` | Keep an object alive across redraws |
| Delegate | `ARSessionDelegate` | "Call me when something happens" |
| `static` | `isSupported` | Belongs to the type, not an instance |
| `private` | `session`, `threshold` | Hidden from outside code |
| `guard let` | Several places | Unwrap safely, or exit early |
| `??` | `value()` helper | Default value if `nil` |
| `compactMap` | Finding the face | Transform and drop `nil`s |
| Tuple | `candidates` | Small bundle of values, accessed with `.0` and `.1` |
| Closure / `$0` | `max(by:)` and `compactMap` | Inline mini-function; `$0` is its first input |
| Ternary `? :` | Final direction | Short if/else |
| `nonisolated` and `Task { @MainActor }` | Delegate method | Run off the main thread, then hop back for UI |

---

# Practice exercises

Change one thing at a time, and predict what happens before running it:

1. Change `threshold` to `0.2`. Is it more or less jumpy?
2. Add `case blink = "Blinking"` and detect it using `.eyeBlinkLeft` and `.eyeBlinkRight`. (Expect these names to be mirrored too.)
3. Comment out `session.delegate = self`. What breaks, and why?
