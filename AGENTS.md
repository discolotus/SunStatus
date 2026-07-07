# Codex Worktree Setup
1. Confirm macOS 14+ with Xcode/Swift 6 installed: `swift --version`.
2. Resolve the Swift package from the repo root: `swift package resolve`.
3. Build the app target: `swift build`.
4. Run the test suite before edits: `swift test`.
5. Launch locally when needed: `swift run SunStatus`.

# Map Screenshot Verification
- MapKit tiles may not appear in `screencapture -l` or other windowed screen captures even when the live window is rendering correctly. If a window capture shows a dark/blank map canvas but the arc overlay is visible, verify with a live app-state screenshot or full visible UI check before treating it as a map rendering regression.
