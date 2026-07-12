# Voxly

Local macOS MVP: hold right Command, speak, release; Voxly transcribes, optionally refines, and attempts to insert the result into the original text field. Temporary audio is removed after processing. One fixed global shortcut; modes alter language/instructions.

## Status

Dictation, cursor insertion, history, permissions, local models, and arm64/Metal acceleration are working. Performance has improved significantly after replacing Homebrew x86 binaries with native arm64/Metal builds and persistent servers.

The current state and technical history are documented in [HANDOFF.md](HANDOFF.md). Open tasks are tracked in [BACKLOG.md](BACKLOG.md).

## Run

```sh
swift run Voxly
```

## Local Engines

Place executables and models in `~/Library/Application Support/Voxly/Models/`:

```text
whisper-cli        # whisper.cpp compiled with Metal
ggml-small.bin     # Whisper model
```

`llama-cli` and `instruct.gguf` are optional: they enable cleaning/email/notes refinement. Without them, Voxly preserves raw text. Afterwards, enable Microphone and Accessibility permissions in Diagnostics. No content is sent by Voxly.

The app starts persistent local servers for Whisper and Llama when native binaries are installed. This avoids reloading models for every dictation. The servers only listen on `127.0.0.1` on ports `18080` and `18081`.

## Resuming Work

Read [HANDOFF.md](HANDOFF.md) first. Refer to [BACKLOG.md](BACKLOG.md) to check for open tasks.
