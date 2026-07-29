# Voxly

Local macOS MVP: hold a configurable shortcut key, speak, release; Voxly transcribes, optionally refines, and attempts to insert the result into the original text field. Temporary audio is removed after processing. Each mode can use a different shortcut key; modes also alter language and instructions.

## Shortcuts

Each mode can use any modifier key as its hold-to-dictate shortcut:

| Key | Display name |
|---|---|
| Right Command | `⌘ Right` |
| Left Command | `⌘ Left` |
| Left Option | `⌥ Left` |
| Right Option | `⌥ Right` |
| Left Control | `⌃ Left` |
| Right Control | `⌃ Right` |
| Left Shift | `⇧ Left` |
| Right Shift | `⇧ Right` |
| Function (Fn) | `Fn` |

**To change:** Open Voxly → Modes → select a mode → click the `Global shortcut` button → press the desired modifier key. Duplicate shortcuts across modes show an inline error. Right Command is the default for new modes.

**Add / delete modes:** Click `+ New mode` in the Modes view (max 4 modes). Click the trash icon on a mode row to delete it (minimum 1 mode must remain).

Dictation starts when a mode's shortcut is held and stops when released. The mode matching the pressed shortcut is used for transcription and refinement. Escape cancels an active dictation regardless of current mode.

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
