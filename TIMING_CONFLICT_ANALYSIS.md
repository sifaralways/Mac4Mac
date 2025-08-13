# TrackChangeMonitor vs LogReader Crash Analysis

## The Fatal Timing Sequence

### Step 1: User Action
```
User clicks close button on LogReaderView window
```

### Step 2: Core Animation Starts (Main Thread)
```
NSWindow begins closing animation
→ -[_NSWindowTransformAnimation] created
→ Core Animation transaction begins
→ Main thread starts animation frame processing
```

### Step 3: Timer Fires During Animation (Main Thread)
```
TrackChangeMonitor Timer fires (1-second interval)
→ checkForTrackChange() called on main thread
→ Creates NSTask for AppleScript
→ task.waitUntilExit() BLOCKS main thread
```

### Step 4: Animation Tries to Continue (BLOCKED)
```
Core Animation tries to continue transaction
→ Main thread is BLOCKED by waitUntilExit()
→ Animation frames cannot process
→ Transaction commit fails
```

### Step 5: Memory Cleanup Conflict (CRASH)
```
System tries to clean up animation objects
→ -[_NSWindowTransformAnimation dealloc] called
→ AutoreleasePoolPage::releaseUntil attempts cleanup
→ objc_release called on corrupted memory
→ EXC_BAD_ACCESS at 0x0000639b96eb9a80
```

## Why This Specific Combination Crashes

### 1. **Shared Resource: Main Thread**
- **TrackChangeMonitor**: Executes Timer callbacks on main thread
- **LogReader Window**: Core Animation runs on main thread
- **Conflict**: Both need exclusive main thread access

### 2. **Blocking vs Non-Blocking Operations**
- **Core Animation**: Expects non-blocking main thread operations
- **NSTask.waitUntilExit()**: Blocking synchronous operation
- **Result**: Animation pipeline stalls and corrupts

### 3. **Memory Management Timing**
- **Animation Objects**: Have strict lifecycle during transitions
- **Blocked Thread**: Prevents proper cleanup sequence
- **Autorelease Pool**: Cannot drain properly when thread blocked

## Code Evidence from Crash Log

```
Thread 0 crashed with ARM Thread State (64-bit):
objc_release + 16
↓
-[_NSWindowTransformAnimation dealloc] + 512
↓  
AutoreleasePoolPage::releaseUntil + 204
↓
CA::Context::commit_transaction + 9320
↓
-[NSConcreteTask waitUntilExit] + 340  ← BLOCKING POINT
↓
TrackChangeMonitor.checkForTrackChange() + 356 (line 76)
↓
Timer callback from startMonitoring()
```

## Why Other Windows Don't Crash

### Main App Window
- **No complex animations**: Simple menu bar app
- **No competing timers**: TrackChangeMonitor runs independently
- **Static UI**: No Core Animation transactions

### Other System Windows  
- **Different processes**: Don't share our main thread
- **System managed**: macOS handles their animation lifecycle

## The LogReader Difference

### Complex SwiftUI View
```swift
// LogReaderView has complex UI updates
@State private var logEntries: [LogEntry] = []
@State private var isAutoScrollEnabled = true
```

### Window Transition Animations
```swift
// macOS applies sophisticated animations when closing SwiftUI windows
// These require uninterrupted main thread access for smooth transitions
```

### Real-time Updates
```swift
// LogReaderView may be updating content while closing
// Creates additional animation complexity
```

## Solution Effectiveness

### Before Fix
```
Main Thread: [Timer] → [AppleScript] → [BLOCKED] → [Animation Fails] → [CRASH]
```

### After Fix  
```
Main Thread: [Timer] → [Async Dispatch] → [Animation Continues] → [Success]
Background:   [AppleScript] → [Completion Handler] → [Main Thread Update]
```

## Key Insight

The crash wasn't caused by LogReaderView code itself, but by the **timing collision** between:
- TrackChangeMonitor's blocking operations
- LogReaderView's closing animation requirements  
- Shared main thread resource contention

This explains why:
- Crash only happens when closing LogReaderView (not other actions)
- Crash is timing-dependent (doesn't happen every time)
- Crash involves Core Animation infrastructure (not app code)
- Fix requires Timer/task lifecycle management (not LogReader changes)
