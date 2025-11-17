# Daemon Debugging Status

## Issue
The daemon builds successfully but shows help instead of running when invoked with `--config` flag.

## Symptoms
- `validate()` method is called successfully (DEBUG output confirms)
- `run()` method appears to never be called
- ArgumentParser shows help/overview instead of executing

## Changes Made

### 1. main.swift - More Explicit Entry Point
Changed from bare top-level await to wrapped @main struct:

```swift
@main
struct Main {
    static func main() async {
        await AIShellDaemonCLI.main()
    }
}
```

**Why:** Bare top-level `await` might not properly initialize ArgumentParser's command structure. The @main wrapper provides a more explicit entry point.

### 2. CLI.swift - Comprehensive Debug Output
Added DEBUG statements throughout the run() method to track execution:

- Entry point confirmation
- Thread information
- Configuration loading (with try/catch to catch errors)
- DaemonService creation
- daemon.run() invocation
- Error handling

**Why:** This will help us determine:
1. If `run()` is being called at all
2. Where execution might be failing
3. If there are silent errors being caught

### 3. test-daemon.sh - Automated Testing Script
Created comprehensive test script that:
- Cleans and rebuilds from scratch
- Locates binary automatically
- Tests --help and --version flags
- Creates test configuration if needed
- Runs daemon with --config and captures all output

## Testing Instructions

Run the test script on your Mac:

```bash
./test-daemon.sh
```

## What to Look For

### Scenario A: run() is now being called
You'll see:
```
DEBUG: run() called!
DEBUG: Thread: <NSThread: 0x...>
🚀 AI Shell Assistant Daemon
Version: 1.0.0
DEBUG: About to load configuration from: Optional("/path/to/config.json")
...
```

If this happens, the entry point fix worked! Any subsequent issues will be clear from the DEBUG output.

### Scenario B: run() still isn't being called
You'll see:
```
DEBUG: validate() called
DEBUG: config = Optional("/path/to/config.json")
DEBUG: socket = nil
DEBUG: verbose = false
OVERVIEW: AI-powered shell assistant daemon
[help text]
```

If this happens, there's a deeper issue with ArgumentParser command structure that we need to investigate further.

### Scenario C: New error messages
If you see new errors, that's progress! It means we're getting past the ArgumentParser issue and hitting the actual execution.

## Possible Root Causes

1. **ArgumentParser initialization** - The bare top-level await might not properly initialize the command
2. **AsyncParsableCommand requirements** - Some requirement of AsyncParsableCommand might not be met
3. **Configuration validation** - If Configuration.load() fails in run(), it might cause ArgumentParser to show help
4. **Command structure** - Something about the command definition might be triggering help mode

## Next Steps After Testing

1. Share the complete output from `./test-daemon.sh`
2. Look specifically for:
   - Does "DEBUG: run() called!" appear?
   - Are there any errors between validate() and run()?
   - Does the daemon start or still show help?
3. Based on the output, we'll either:
   - Fix the next issue in the execution chain, OR
   - Investigate ArgumentParser command structure more deeply
