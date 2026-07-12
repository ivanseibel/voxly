# Voxly Agent Context

## Project Overview
Voxly is a local macOS MVP for dictation:
- User holds Right Command to talk, releases to stop.
- Audio is transcribed locally via a persistent local Whisper server.
- Optional text refinement is handled locally via a persistent local Llama server.
- The transcribed (and optionally refined) text is inserted into the active text field.

## Key Architecture & Source Files
The codebase is structured as a Swift Package with source files under [Sources/VoxlyApp](file:///Users/ivanseibel/dev/personal/voxly/Sources/VoxlyApp):
- [VoxlyApp.swift](file:///Users/ivanseibel/dev/personal/voxly/Sources/VoxlyApp/VoxlyApp.swift): Menubar, windows, and floating capsule interface.
- [ContentView.swift](file:///Users/ivanseibel/dev/personal/voxly/Sources/VoxlyApp/ContentView.swift): Modos (modes), Histórico (history), Diagnóstico (diagnostic) UI.
- [DictationCoordinator.swift](file:///Users/ivanseibel/dev/personal/voxly/Sources/VoxlyApp/DictationCoordinator.swift): Audio recording, dictation states, and workflow coordinator.
- [ModelServers.swift](file:///Users/ivanseibel/dev/personal/voxly/Sources/VoxlyApp/ModelServers.swift): Local servers lifecycle management (Whisper on port `18080`, Llama on port `18081`).
- [Services.swift](file:///Users/ivanseibel/dev/personal/voxly/Sources/VoxlyApp/Services.swift): Audio capture, clipboard copy, cursor insertion, engine/CLI fallbacks.
- [Stores.swift](file:///Users/ivanseibel/dev/personal/voxly/Sources/VoxlyApp/Stores.swift) & [Models.swift](file:///Users/ivanseibel/dev/personal/voxly/Sources/VoxlyApp/Models.swift): Data models, active modes, local storage (UserDefaults).

## Local Engines Configuration
Natively-built arm64/Metal binaries and models reside in:
`~/Library/Application Support/Voxly/Models/` (symlinked as `whisper-cli`, `whisper-server`, `llama-cli`, `llama-server`, `ggml-small.bin`, `instruct.gguf`).

## Developer Reference
- **Build / Package**: Run `zsh scripts/package-app.sh`. This codesigns the app using the `Voxly Local Development` identity. Do not alter this signing mechanism as it maintains Accessibility permissions.
- **Run**: `swift run Voxly` (development) or `open build/Voxly.app`.
- **Handoff Document**: Always consult [BACKLOG.md](file:///Users/ivanseibel/dev/personal/voxly/BACKLOG.md) for current backlog items, bugs (e.g., text cleaning/refinement issues, restoration of the active mode between sessions), and test instructions.
