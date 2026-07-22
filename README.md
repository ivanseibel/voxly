# Voxly

Local macOS MVP: hold right Command, speak, release; Voxly transcribes, optionally refines, and attempts to insert the result into the original text field. Temporary audio is removed after processing. One fixed global shortcut; modes alter language/instructions.

## Quick Command (Build + Install)

Copy and paste:

```sh
zsh scripts/build-install.sh
```

Copy and paste (install in custom folder):

```sh
VOXLY_INSTALL_DIR="$HOME/Applications" zsh scripts/build-install.sh
```

Copy and paste (build/install only, do not auto-open):

```sh
VOXLY_OPEN_AFTER_INSTALL=0 zsh scripts/build-install.sh
```

## Status

Dictation, cursor insertion, history, permissions, local models, and arm64/Metal acceleration are working. Performance has improved significantly after replacing Homebrew x86 binaries with native arm64/Metal builds and persistent servers.

Open tasks and current project notes are tracked in [BACKLOG.md](BACKLOG.md).

## Run

```sh
swift run Voxly
```

## Build And Install

```sh
zsh scripts/build-install.sh
```

Optional environment variables:

- `VOXLY_INSTALL_DIR`: custom install folder (default: `/Applications`).
- `VOXLY_OPEN_AFTER_INSTALL`: set to `0` to skip auto-open after install.

## Local Engines

Place executables and models in `~/Library/Application Support/Voxly/Models/`:

```text
whisper-cli        # whisper.cpp compiled with Metal
ggml-small.bin     # Whisper model
```

`llama-cli` and `instruct.gguf` are optional: they enable cleaning/email/notes refinement. Without them, Voxly preserves raw text. Afterwards, enable Microphone and Accessibility permissions in Diagnostics. No content is sent by Voxly.

The app starts persistent local servers for Whisper and Llama when native binaries are installed. This avoids reloading models for every dictation. The servers only listen on `127.0.0.1` on ports `18080` and `18081`.

## Resuming Work

Refer to [BACKLOG.md](BACKLOG.md) to check for open tasks and current notes.
