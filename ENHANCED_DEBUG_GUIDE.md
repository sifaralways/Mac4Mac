# Advanced Crash Debugging Guide

## Enhanced Fix Implementation

I've implemented a comprehensive multi-layered fix:

### Layer 1: Complete Timer Suspension
- **Timer invalidation**: Timer is completely stopped during animations
- **Reference counting**: Multiple pause requests tracked with pauseCount
- **Thread safety**: NSLock protects pause/resume operations

### Layer 2: Aggressive Process Management  
- **Task termination**: All pending AppleScript processes killed during pause
- **Async execution**: No blocking waitUntilExit() calls anywhere
- **Debouncing**: Minimum 0.8s between track checks

### Layer 3: Comprehensive Lifecycle Management
- **Window events**: Close, resize, minimize, restore all trigger pause
- **App events**: Hide, unhide, resign active, become active
- **System events**: Global window notifications for emergency pause

### Layer 4: Extended Animation Windows
- **Longer delays**: 1.0s for window close, 0.5s for app state changes
- **Multiple resume attempts**: Handles overlapping pause/resume cycles

## If Crash Still Persists

### 1. **Get Fresh Crash Log**
Check if the crash is still at the same location:
```bash
ls -la ~/Library/Logs/DiagnosticReports/ | grep MAC4MAC | head -1
```

### 2. **Enable Debug Logging**
The enhanced version logs all pause/resume operations:
- "Track change monitoring paused (count: X)"
- "Emergency pause track monitoring"
- "Window animation complete - resuming"

### 3. **Test Scenarios**
Try these specific test cases:
- Open log reader → immediately close (rapid action)
- Open log reader → wait 5s → close slowly
- Open → resize window → close
- Open → minimize → restore → close
- Open → switch apps → return → close

### 4. **Alternative Crash Sources**
If crash persists, it might be:

#### A. Different Timer Source
Search for other Timer usage in the codebase:
```bash
grep -r "Timer\|DispatchSourceTimer" --include="*.swift" .
```

#### B. Different AppleScript Location
Search for other AppleScript executions:
```bash
grep -r "osascript\|AppleScript\|Process()" --include="*.swift" .
```

#### C. SwiftUI State Updates
The crash might be from SwiftUI state updates during window closure:
```bash
grep -r "@State\|@Published\|@ObservedObject" MAC4MAC/LogReaderView.swift
```

### 5. **Nuclear Option: Complete Disable**
If crash still happens, temporarily disable TrackChangeMonitor entirely:

```swift
// In AppDelegate.swift - comment out:
// trackChangeMonitor.startMonitoring()

// Test if crash still occurs - this will isolate the root cause
```

## Next Steps Based on Results

### If Crash Stops with Disabled Monitor
- Issue confirmed in TrackChangeMonitor
- Implement even more aggressive pausing
- Consider moving to background thread entirely

### If Crash Continues
- Issue is elsewhere (LogReaderView, SwiftUI, other timers)
- Focus debugging on those components
- Crash may be unrelated to TrackChangeMonitor

### If Crash Changes Location
- Partial fix working
- New crash location will indicate remaining issue
- Iterative fixing approach needed

## Monitoring Implementation Status

The current fix provides:
✅ Complete timer invalidation during animations  
✅ Process termination and cleanup  
✅ Thread-safe pause/resume with reference counting  
✅ Comprehensive window and app lifecycle hooks  
✅ Emergency system-wide window monitoring  
✅ Extended animation delay windows  
✅ Async-only AppleScript execution  
✅ Debounced execution protection  

This should eliminate the crash if TrackChangeMonitor was the root cause.
