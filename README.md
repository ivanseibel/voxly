<div align="center">
  <img src="assets/app-icon.png" alt="Voxly Logo" width="128" height="128">
  <h1>Voxly</h1>
  <p><b>Fast, private, push-to-talk voice dictation and text refinement for macOS.</b></p>

  <p>
    <a href="#overview">Overview</a> •
    <a href="#key-features">Features</a> •
    <a href="#quick-start">Quick Start</a> •
    <a href="#shortcuts--modes">Shortcuts & Modes</a> •
    <a href="#local-engines--architecture">Local Engines</a> •
    <a href="#contributing">Contributing</a>
  </p>
</div>

---

## Overview

**Voxly** is a lightweight, privacy-first macOS application for voice dictation. Hold a global shortcut key, speak, and release — Voxly transcribes your speech and inserts the result directly into your active text field.

Voxly runs entirely on your Mac using hardware-accelerated (arm64 / Metal) local AI engines. **No audio or text ever leaves your machine.**

<div align="center">
  <img src="assets/menu-bar-popover.png" alt="Voxly Menu Bar Popover" width="380">
  <br>
  <sub><i>Menu bar popover showing status, active modes, and quick actions</i></sub>
</div>

---

## ✨ Key Features

- **Push-to-Talk Dictation:** Hold a global modifier key to record, release to transcribe and insert directly into the active app.
- **100% Local & Private:** Transcribes locally via `whisper.cpp` and refines text via `llama.cpp`. Audio buffers are deleted immediately after processing.
- **Persistent High-Performance Servers:** Uses local persistent daemon servers to eliminate model reloading latency for near-instant response.
- **Multiple Dictation Modes:** Configure separate speech modes (e.g., *Faithful transcription*, *Clean text*) with custom global hotkeys, languages, and local instructions.
- **Per-Mode Vocabulary:** Give each mode the names, products, and jargon it should transcribe correctly. The list is stored locally with the mode and applies to the next dictation — no restart, nothing uploaded.
- **Direct Cursor Insertion:** Injects transcribed text into the focused text field using macOS Accessibility APIs, with automatic fallback to clipboard paste (`⌘V`).
- **Permissions Diagnostics:** Built-in setup verification for Microphone, Accessibility permissions, and local engine files.
- **Local History:** Lightweight search for past transcriptions. Audio is never stored.

---

## 🖼 Interface Preview

| Speech Modes | Diagnostics & Status |
| :---: | :---: |
| <img src="assets/main-window-modes.png" alt="Speech Modes View" width="460"> | <img src="assets/main-window-diagnostics.png" alt="Diagnostics View" width="460"> |

| Local History | Menu Bar Popover |
| :---: | :---: |
| <img src="assets/main-window-history.png" alt="Local History View" width="460"> | <img src="assets/menu-bar-popover.png" alt="Menu Bar Popover" width="320"> |

---

## 🚀 Quick Start

### One-Command Build & Install

To compile Voxly and install it to `/Applications`:

```bash
zsh scripts/build-install.sh
```

**Custom Installation Options:**

```bash
# Install to custom folder (e.g. ~/Applications)
VOXLY_INSTALL_DIR="$HOME/Applications" zsh scripts/build-install.sh

# Build & install without auto-opening
VOXLY_OPEN_AFTER_INSTALL=0 zsh scripts/build-install.sh
```

### Run in Development Mode

```bash
swift run Voxly
```

---

## ⌨ Shortcuts & Modes

Assign different global modifier keys to distinct dictation modes:

| Key | Display Name | Action |
| :--- | :--- | :--- |
| **Right Command** | `⌘ Right` | Default mode (*Faithful transcription*) |
| **Right Option** | `⌥ Right` | Refinement mode (*Clean text*) |
| **Left Command** | `⌘ Left` | Configurable mode |
| **Left Option** | `⌥ Left` | Configurable mode |
| **Left Control** | `⌃ Left` | Configurable mode |
| **Right Control** | `⌃ Right` | Configurable mode |
| **Left Shift** | `⇧ Left` | Configurable mode |
| **Right Shift** | `⇧ Right` | Configurable mode |
| **Function (Fn)** | `Fn` | Configurable mode |

> [!TIP]
> Pressing **Escape** during an active dictation immediately cancels recording.

### Vocabulary

Each mode has a **Vocabulary** field: a comma-separated list of proper nouns, product names, and jargon that Whisper should get right — for example `Voxly, Kubernetes, PostgreSQL, whisper.cpp`. It is sent as Whisper's initial prompt, so the model prefers those spellings over similar-sounding words.

- The list is saved with the mode in your local user defaults and takes effect on the next dictation.
- Terms that matter in every mode go in the `whisperPrompt` config key instead; the global list and the mode list are combined.
- Whisper accepts roughly 224 tokens of prompt. Voxly cuts longer lists on a term boundary and logs what it dropped, so keep each list to the words that actually get misheard.

---

## ⚙ Local Engines & Architecture

Voxly requires native binaries and models located in `~/Library/Application Support/Voxly/Models/`:

```text
~/Library/Application Support/Voxly/Models/
├── whisper-cli        # whisper.cpp (arm64 / Metal)
├── ggml-small.bin     # Whisper speech recognition model (see `whisperModelFile`)
├── llama-cli          # (Optional) llama.cpp (arm64 / Metal)
└── instruct.gguf      # (Optional) Llama text refinement model
```

When native binaries are present, Voxly automatically spawns local persistent daemon servers (`whisper-server` on port `18080` and `llama-server` on port `18081`) bound strictly to `127.0.0.1`.

---

## 🛠 Configuration

Runtime settings live in a JSON file that Voxly generates automatically on first launch:

```text
~/Library/Application Support/Voxly/config.json
```

The file is **self-documenting**: a `_help` block at the top describes every option. Missing keys fall back to their defaults, so a partial or deleted file never breaks startup, and newly added options appear automatically after an update. **Edit a value and restart Voxly to apply it.**

Common options include:

| Key | Default | Purpose |
| --- | --- | --- |
| `duckVolumeFactor` | `0.1` | Lowers background audio volume while recording (0.0–1.0). |
| `minTapSeconds` | `0.3` | Minimum hold time; shorter taps are discarded. |
| `whisperPort` / `llamaPort` | `18080` / `18081` | Local server ports (loopback only). |
| `whisperThreads` / `llamaThreads` | `8` | CPU threads per local model. |
| `llamaContextSize` | `2048` | Llama context window (tokens). Prompts plus the refined output must fit inside it; a dictation too long for it is inserted as raw text with the reason shown. |
| `refineMaxTokens` | `256` | Floor for the refinement output budget, not a ceiling. Voxly scales the budget with the length of the dictation and clamps it to the room left in `llamaContextSize`. |
| `whisperModelFile` | `ggml-small.bin` | Whisper model file to load; swap for a larger one to trade latency for accuracy. |
| `whisperPrompt` | `""` | Vocabulary every mode inherits; combined with each mode's own Vocabulary field. |
| `whisperBeamSize` / `whisperBestOf` | `5` / `5` | Beam search width and candidate count for transcription. |

See the `_help` block inside the generated file for the full list of options and descriptions.

---

## 🤝 Contributing

Voxly is an early-stage open-source project under active development. Community contributions, bug reports, and feedback are very welcome!

- Open an [Issue](https://github.com/ivanseibel/voxly/issues) or submit a [Pull Request](https://github.com/ivanseibel/voxly/pulls).
- Check [BACKLOG.md](BACKLOG.md) to see the open tasks and known bugs.

---

## 📄 License

Voxly is available under the [MIT License](LICENSE).
