# Product Specification — Voxly v1

## 1. Product Vision

Voxly is a local dictation application for macOS that transforms speech into text and inserts it into the active field of any compatible application. The user holds down a global shortcut, speaks, releases the shortcut, and receives the transcribed text — optionally refined by local instructions — without sending audio or content to remote AI services.

The focus of v1 is to offer a private, fast alternative to tools like Wispr Flow and Spokenly for people who write in Portuguese and English in work, communication, and development apps.

## 2. Target Audience & Needs

### Primary Audience

People with Apple Silicon Macs who frequently write in text fields across multiple applications and want to dictate privately, without depending on an internet connection or an AI account.

### Addressed Needs

- Dictating without opening a window or switching applications.
- Producing faithful text or text adapted to the context, depending on the chosen mode.
- Defining reusable shortcuts and writing instructions.
- Retrieving recent transcriptions without retaining sensitive audio files.
- Knowing clearly when the app is recording, processing, or failing to insert text.

## 3. v1 Scope

### Included

- Native menubar application for recent macOS on Apple Silicon (M1 or later).
- Global activation via press-and-hold; Right Command is the default shortcut and other shortcuts can be configured.
- Audio capture, local transcription, and discarding of audio immediately after transcription.
- Optimized recognition for Portuguese and English, with language selection per mode.
- Saved modes with shortcut, language, instructions, model, and output action.
- Automatic insertion into the previously focused field, with copying to clipboard as a contingency.
- Local text history, with search and deletion.
- Onboarding and diagnostic state for Microphone and Accessibility permissions.
- Local download, verification, and management of transcription and post-processing models.

### Out of Scope

- Windows, macOS Intel, iOS, and Android.
- Cloud sync, accounts, collaboration, or content telemetry.
- Audio retention, playback, or export.
- Activation by toggle, double tap, voice, mouse, or gesture.
- External models, API keys, or remote processing.
- Application automation, voice commands, and script execution.

## 4. Main Flow

1. The user places the cursor in a text field of a compatible application.
2. Holds down the shortcut of the active mode; Voxly records the current app and focus and starts capture.
3. The floating capsule near the cursor shows the audio level and the `Recording` state.
4. Upon releasing the shortcut, Voxly ends capture and shows `Transcribing`.
5. The local engine generates the raw text; audio is removed from memory and any temporary file.
6. If the mode has instructions, the local LLM produces the final text under preservation rules; the capsule shows `Refining`.
7. Voxly restores original focus and inserts the result. If it cannot insert, it copies the result and informs the user.
8. The history receives the final text, raw text, mode, language, and date, but never the audio.

## 5. Functional Requirements

### 5.1 Capture & Shortcuts

- Voxly must monitor global shortcuts even when it is not in the foreground.
- The default shortcut must be the Right Command key in press-and-hold mode.
- While the shortcut is pressed down, the state must be `Recording`; releasing it ends the capture.
- Escape must cancel the ongoing recording or processing and not insert any text.
- The user must be able to assign a unique shortcut to each saved mode.
- Voxly must prevent duplicate shortcuts and warn when a shortcut cannot be registered with the system.

### 5.2 Local Transcription

- Transcription must use `whisper.cpp` with Metal acceleration and a balanced local model.
- Each mode must define Portuguese, English, or auto-detection between the two languages.
- The app must keep the raw text for audit in the history, separate from the optimized result.
- If transcription fails, no text should be inserted and the capsule must display a recoverable error.

### 5.3 Local Post-Processing

- A mode without instructions must use the raw text as the final result.
- A mode with instructions must run a local instruct model via `llama.cpp` with Metal acceleration.
- Every request to the LLM must include strict rules: preserve facts, names, numbers, language, and intent; do not invent, summarize, or exclude information unless the mode's instructions explicitly dictate it.
- The LLM result must be treated as failed if it is empty; in this case, Voxly must use the raw text and inform the user that refinement was not applied.

### 5.4 Modes

Each mode must contain:

| Field | Description |
| --- | --- |
| Name | Label displayed in the interface and history. |
| Shortcut | Unique global combination used to start recording. |
| Language | Portuguese, English, or automatic between both. |
| Instructions | Post-processing text; can be empty. |
| Model profile | Balanced local profile of v1. |
| Output | Automatically insert, with clipboard copy as contingency. |

The initial modes are:

| Mode | Default Instruction |
| --- | --- |
| Faithful transcription | Preserve speech, adjusting only obvious punctuation and capitalization. |
| Clean text | Remove filler words and organize the text without changing meaning or facts. |
| Professional email | Convert into a clear and professional email, preserving content, names, and requests. |
| Code/technical notes | Organize as a technical note, preserving terms, identifiers, numbers, and dictated code blocks. |

### 5.5 Text Insertion

- Before recording, the app must register the focused element or application.
- After processing, it must attempt to insert the text via Accessibility APIs into the original destination.
- When direct insertion is not possible, it must preserve the previous clipboard, copy the result, attempt to paste, and restore the previous clipboard when safe.
- If it cannot insert or paste, it must leave the result on the clipboard and present a clear message that the user needs to paste manually.
- No result should be inserted after cancellation, transcription error, or release without useful audio.

### 5.6 History & Privacy

- History must be local and enabled by default.
- Each entry must store raw text, final text, mode, language, timestamp, and insertion result.
- The history screen must allow text searching and individual or complete deletion.
- Audio and temporary audio files must be deleted after transcription, including when it fails or is cancelled.
- The app must not send audio, transcription, instructions, or history to external services once the models have been installed.

### 5.7 Models & Onboarding

- First-time use must explain that Voxly processes content locally and request Microphone and Accessibility permissions.
- The app must download and verify the necessary local models before enabling the first transcription.
- The interface must display download progress, required space, completion, and failure.
- If permissions or models are unavailable, the menubar and main screen must show the blocking status and instructions to resolve it.

## 6. Experience & Interface

### Visual Language

The product should feel like a quiet desktop tool: aluminum graphite and black for surfaces, green for active capture, amber for processing, white for final text, and macOS selection blue. The interface must not adopt a metrics dashboard, generic cards, or side navigation as its primary structure.

### Surfaces

- The menubar icon offers access to the status, active mode, history, settings, and diagnostics.
- The speech capsule is the main visual signature: compact, floating, and temporary; it accompanies the recording without stealing focus.
- The settings window prioritizes editing modes and history, with direct controls and minimal visual noise.

### Capsule States

| State | Feedback |
| --- | --- |
| Ready | Discrete icon and active mode in the menubar. |
| Recording | Green indicator and audio level meter. |
| Transcribing | Amber indicator with indeterminate progress. |
| Refining | Amber indicator and applied mode name. |
| Inserted | Brief confirmation with green check. |
| Copied | Brief notice to paste manually. |
| Error | Short message, recovery action, and no automatic insertion. |

## 7. Non-Functional Requirements

- The app must function offline after the models are installed.
- The app must remain responsive during capture and processing, keeping the interface and shortcut available.
- Models must use Metal acceleration and the default profile must balance accuracy, memory, and response time.
- All persistent data must reside in the app's private storage on the Mac.
- Distribution must be signed and notarized; it will not be published on the Mac App Store because it relies on global keyboard access and Accessibility.

## 8. Acceptance Criteria

- The Right Command key starts recording only while held down, and its release terminates the flow.
- Text is never inserted before the shortcut is released.
- A mode applies only its own instructions, and the `Faithful transcription` mode does not perform rewriting post-processing.
- The result is inserted into the initially focused field or copied to the clipboard with an explicit warning.
- Audio does not remain in history, cache, or temporary files after completion, cancellation, or failure.
- History can be searched and deleted locally.
- Offline, an installation with models already downloaded remains capable of recording, transcribing, optimizing, and inserting text.
- Permission, model, transcription, and insertion errors are visible and do not cause silent loss of the result.

## 9. v1 Success Metrics

- The entire dictation flow is completed without additional interaction beyond pressing, speaking, and releasing in most cases.
- Users can configure and use at least one custom mode after onboarding.
- Insertion failures preserve the result on the clipboard instead of discarding it.
- No audio persists after the dictation cycle.
