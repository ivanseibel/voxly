# Voxly — handoff and resume

Updated on 2026-07-12.

## Current Status

The macOS MVP is working for local dictation:

- Holding the Right Command key starts recording; releasing it ends the workflow.
- Whisper transcribes Portuguese and English, with Automatic mode using `-l auto`.
- The result is inserted into the original field via clipboard/paste; the cursor remains at the end of the text.
- History, diagnostics, and the floating status capsule are available.
- Temporary audio is removed after processing.
- The current native binaries use arm64 and Metal on Apple Silicon.
- Models remain loaded in local servers during the session.

The floating capsule was visually validated during a recording: it is centered horizontally on the active monitor and close to the bottom of the visible area, with a 24-point margin.

## Architecture

- SwiftUI/AppKit in `Sources/VoxlyApp/`.
- `DictationCoordinator.swift`: capture, workflow, and states.
- `Services.swift`: audio, insertion, CLI fallback, and local engines.
- `ModelServers.swift`: lifecycle of local servers and HTTP.
- `ContentView.swift`: modes, history, and diagnostics.
- `VoxlyApp.swift`: menubar, window, and floating capsule.
- `Stores.swift` / `Models.swift`: local persistence and data models.

Local servers:

- Whisper: `127.0.0.1:18080/inference`
- Llama: `127.0.0.1:18081/completion`

Native sources:

- `native/whisper.cpp/`
- `native/llama.cpp/`

## Models and Local Installation

Executables and models reside in `~/Library/Application Support/Voxly/Models/`:

```text
whisper-cli
whisper-server
llama-cli
llama-server
ggml-small.bin
instruct.gguf
```

All four executables are arm64/Metal builds. The `instruct.gguf` file is the symlink used by the local instruct model.

## Resume Commands

Open the app:

```sh
open /Users/ivanseibel/dev/personal/voxly/build/Voxly.app
```

Verify servers:

```sh
curl http://127.0.0.1:18080/health
curl http://127.0.0.1:18081/health
```

Rebuild and package:

```sh
zsh scripts/package-app.sh
```

The script uses the stable `Voxly Local Development` identity. Do not replace it with ad-hoc signing, as this causes the Accessibility permission to disappear with each build.

## Logged Performance

- Native arm64/Metal Whisper: approximately 0.90s for 11s of audio after warm-up.
- arm64/Metal Llama: approximately 100 tokens/s.
- Persistent servers: approximately 0.38s for Whisper and 0.31s for Llama in direct calls.
- First-time use may be slower due to model loading and Metal compilation.

## Fix History

- Whisper log capture was fixed to not include stderr in the transcribed text.
- Automatic mode now explicitly sends `-l auto` to Whisper.
- Insertion now returns `.inserted` when CGEvents are successfully created and `.copied` only as a fallback.
- The active mode is restored between sessions via the UUID persisted in `activeModeID`.
- Artificial line breaks in the inserted text have been fixed.
- Local refinement was adjusted to use the `/completion` endpoint with the configured model template, along with a strict prompt to preserve facts and avoid introductory text.
- The local logger `VoxlyLog` writes to `~/Library/Application Support/Voxly/voxly.log` for inference diagnostics.
