# Voxly — code, flow and product review

Reviewed on 2026-08-26 against commit `99bb743`. Scope: all of `Sources/VoxlyApp`, the packaging scripts, `PRODUCT_SPEC.md` and `README.md`. Reconciled on 2026-08-27 after the walkthrough.

This was an opportunity report, and it has now been reviewed item by item. Every item has a disposition, and the accepted work lives in [BACKLOG.md](BACKLOG.md), grouped into priority sections — that file is the plan, this one is the analysis behind it. Still no code changed by either document.

Read it this way: unless an item carries a **Verdict** note, it was accepted as written and is tracked in the backlog. A **Verdict** note means the decision changed, narrowed or extended what the item proposed — including two outright rejections — and where they disagree, the backlog follows the verdict. The priority shortlist in section 9 has been replaced by a map into the backlog's sections.

## Contents

- [Overall assessment](#overall-assessment)
- [1. Correctness bugs users will feel](#1-correctness-bugs-users-will-feel)
- [2. Latency and performance](#2-latency-and-performance)
- [3. Usability and UX](#3-usability-and-ux)
- [4. Product and feature opportunities](#4-product-and-feature-opportunities)
- [5. Architecture, maintainability, tests](#5-architecture-maintainability-tests)
- [6. Privacy and security](#6-privacy-and-security)
- [7. Packaging and distribution](#7-packaging-and-distribution)
- [8. Documentation drift](#8-documentation-drift)
- [9. Where the accepted work lives](#9-where-the-accepted-work-lives)

## Overall assessment

The core idea is sound and the hard parts are genuinely hard: a persistent whisper/llama server pair, push-to-talk on a bare modifier, and a Bluetooth-aware output silencer. The audio-restore state machine in `RecordingOutputSilencer` is the most carefully reasoned code in the project, and its comments explain real, measured failures. That quality should be the bar for the rest.

The weak spots cluster in three places:

1. **The last 10% of the flow.** Text insertion is much less capable than the spec and README claim, and cancellation does not actually cancel — the latter resolved by dropping cancellation rather than repairing it (1.1).
2. **The press-to-record latency path.** The keypress handler does synchronous `osascript` spawns and blocking `Thread.sleep` retries on the main actor.
3. **The gap between spec and reality.** Onboarding, model download, Accessibility insertion and per-mode output settings are specified but not built, and the README documents a config key that does not exist.

## 1. Correctness bugs users will feel

### 1.1 Escape does not stop text from being inserted

`cancel()` at [DictationCoordinator.swift:89-95](Sources/VoxlyApp/DictationCoordinator.swift#L89-L95) only bumps `latestDictationID`. The in-flight `process()` keeps running and still calls `inserter.insert(...)` at [DictationCoordinator.swift:131](Sources/VoxlyApp/DictationCoordinator.swift#L131), because the `ownsSharedUI` check happens *after* insertion — that ordering is deliberate, so a superseded dictation can still deliver its text to its own target.

Net effect: pressing Escape during `Transcribing` or `Refining` shows "Dictation canceled", and then seconds later the text is pasted into whatever the user is now doing. Spec §5.5 says no result may be inserted after cancellation.

**Fix direction:** separate the two concepts. Keep `latestDictationID` for "superseded", and add an explicit cancelled-ID set (or a per-dictation `Task` the coordinator can cancel) that suppresses insertion *and* the history entry. Cancelling should also cancel the outstanding `URLSession` request so the local server is freed.

**Verdict:** the feature is removed instead of fixed. Escape-to-cancel is not worth the state it needs, and the accepted replacement is aborting on any `keyDown` while recording (1.12), which covers the case that actually happens. The `cancelKeyCode` config key goes too, and the teardown path that `applicationWillTerminate` depends on stays. Consequence accepted: no way to abort a dictation in flight.

### 1.2 Cancelling leaks the recorded WAV to `/tmp` forever

`cancel()` calls `_ = recorder.stopAndRemove()` and then `recorder.discard()`. But `stopAndRemove()` sets `backend = nil` at [Services.swift:1194-1204](Sources/VoxlyApp/Services.swift#L1194-L1204), so `discard()` — which is just `backend?.discard()` — is a no-op. The URL returned by `stopAndRemove()` is dropped and the file is never deleted.

Contradicts spec §5.6 and the README's "audio buffers are deleted immediately after processing".

**Fix direction:** `if let audio = recorder.stopAndRemove() { try? FileManager.default.removeItem(at: audio) }`. A launch-time sweep of `voxly-*.wav` in the temp directory is worth adding too, for files already leaked.

**Verdict:** accepted, and it outlives 1.1. Removing Escape removes the user-facing route into this leak, but `applicationWillTerminate` calls the same method, so quitting mid-recording still leaves the file behind. Tracked as its own backlog entry rather than as part of the Escape removal.

### 1.3 Failed dictations keep the audio on disk, permanently

`preserveAudioForDebug` at [DictationCoordinator.swift:153-160](Sources/VoxlyApp/DictationCoordinator.swift#L153-L160) moves the WAV into `~/Library/Application Support/Voxly/FailedAudio/` on every error path. Nothing ever deletes it, nothing surfaces it in the UI, and neither the README nor the spec mentions it. For a product whose headline claim is that no audio persists, this is the most surprising behaviour in the codebase.

**Fix direction:** put it behind a config key (`keepFailedAudioForDebug`, default false), cap it (N files or M days, pruned at launch), and surface it in Diagnostics with "Reveal" and "Delete all" — the same treatment history already gets.

### 1.4 There is no Accessibility insertion — only ⌘V

Three separate problems in `TextInserter` at [Services.swift:1490-1506](Sources/VoxlyApp/Services.swift#L1490-L1506):

- `captureTarget()` returns `AXUIElementCreateSystemWide()`, a process-wide constant. It records nothing about the focused element, so "restore original focus" is only `NSRunningApplication.activate()`, at app granularity.
- `insert()` always goes through the clipboard and a synthesized ⌘V. The Accessibility path described in spec §5.5 and advertised in the README ("injects transcribed text using macOS Accessibility APIs, with automatic fallback to clipboard paste") does not exist.
- It returns `.inserted` whenever the two `CGEvent`s could be *constructed*. Construction essentially never fails, so `.copied` is unreachable and the `insertion` field in history is meaningless. The user is told "Text inserted" even when the paste went nowhere.

**Fix direction, two options that compose:**

Real AX path first — read `kAXFocusedUIElementAttribute` from the target app's `AXUIElement` at capture time, and on insert try `AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute, text)`, falling back to ⌘V only when that fails. This also removes the clipboard round-trip entirely for the apps where it works.

At minimum, verify the paste — check `IsSecureEventInputEnabled()` and report `.copied` honestly when the target is a secure input field, since password fields silently swallow synthetic ⌘V today.

### 1.5 The clipboard restore can destroy the result

`insert()` schedules an unconditional clipboard restore 0.65s later, at [Services.swift:1502](Sources/VoxlyApp/Services.swift#L1502). Three consequences:

- If the paste failed, the result is wiped from the clipboard too. Spec §5.5 explicitly requires leaving it there.
- Only `.string` is preserved. A user who had an image, a file promise or rich text on the clipboard loses it.
- If the user copies something during the 0.65s window, Voxly clobbers it.

**Fix direction:** restore only after a confirmed paste; preserve all pasteboard types, or skip the restore when the prior contents weren't plain text; and compare `pasteboard.changeCount` before restoring, so a user copy inside the window wins.

### 1.6 Refinement is silently truncated at 256 tokens

`refineMaxTokens` defaults to 256 at [Config.swift:22](Sources/VoxlyApp/Config.swift#L22), and `ChatResponse` at [ModelServers.swift:145](Sources/VoxlyApp/ModelServers.swift#L145) does not decode `finish_reason`. A 60-second dictation refined by "Clean text" gets cut mid-sentence and inserted as if complete. `llamaContextSize` of 2048 has the same failure shape from the other end.

**Fix direction:** decode `finish_reason` and treat `"length"` as a refinement failure, falling back to raw text — which the code already does well on other error paths. Scale `max_tokens` from the input length.

### 1.7 A mode's refinement is keyed on its name

`usesRefinement` at [Models.swift:41](Sources/VoxlyApp/Models.swift#L41) is `name != "Faithful transcription" && !instructions.isEmpty`. So renaming the default mode silently turns refinement on, using instructions the user can see but that were never meant to run; any new mode named "Faithful transcription" is silently exempted; and the default mode ships *with* instructions text that never executes, which reads as a bug in the editor.

**Fix direction:** an explicit `usesRefinement: Bool` field with a toggle in the mode editor, defaulting to `!instructions.isEmpty` on migration.

**Verdict:** accepted, with the migration default corrected. Falling back to `!instructions.isEmpty` would switch refinement *on* for an existing user whose stored mode is still named "Faithful transcription", since that mode ships with instructions. The fallback has to be the current expression, name comparison included, so behaviour is unchanged across the update.

### 1.8 Two dead settings in the mode editor

`automaticInsert` has a switch in the UI at [ContentView.swift:93](Sources/VoxlyApp/ContentView.swift#L93) and is persisted, but is never read anywhere. Turning it off changes nothing. `modelProfile` is persisted and never read or shown at all.

**Fix direction:** either wire `automaticInsert` (off means copy to clipboard and report `.copied`, which is a legitimately useful mode) or remove the switch. Drop `modelProfile`, or replace it with the per-mode model selection described in 4.4.

**Verdict:** both are removed, neither is wired. `automaticInsert` is not a feature worth having, so the switch goes with the property. Removing a `CodingKeys` case makes the stored keys unknown, and unknown keys are ignored, so no migration is needed. If per-mode model selection (4.4) ever ships, it introduces an enum of real models rather than reviving the free-text string.

### 1.9 The recording level meter never moves

`store.audioLevel` is published at roughly 24–40 Hz, but the capsule is a fresh `NSHostingView` built only when `onCapsule` fires — see [VoxlyApp.swift:23](Sources/VoxlyApp/VoxlyApp.swift#L23) and [VoxlyApp.swift:108-128](Sources/VoxlyApp/VoxlyApp.swift#L108-L128). That happens on state transitions only. `CapsuleView` takes a plain `Float`, so during recording the meter stays frozen at the value captured when recording began, which is 0.

Spec §6 makes the level meter the capsule's defining feature. Today it is an empty bar for the whole recording.

**Fix direction:** hold one long-lived `NSHostingView` whose root view observes `store` as an `@ObservedObject`, and drop the `state`/`level` parameters. Rebuilding a hosting view per transition is also pure waste.

### 1.10 A new mode is created with a shortcut that is already taken

"New mode" at [ContentView.swift:55](Sources/VoxlyApp/ContentView.swift#L55) appends a `DictationMode` with the default `shortcutKeyCode = 54` (Right Command), which the first default mode already owns. `ShortcutRecorder` guards against collisions, but creation does not. `receive()` then resolves the conflict with `store.modes.first(where:)` at [DictationCoordinator.swift:49](Sources/VoxlyApp/DictationCoordinator.swift#L49), so one of the two modes becomes unreachable with no warning anywhere. Spec §5.1 requires Voxly to prevent duplicate shortcuts.

**Fix direction:** assign the first free modifier key at creation; if none is free, disable the button with an explanation. Surface a conflict badge in the mode list rather than relying on the recorder alone.

**Verdict:** accepted, and the scope is larger than this item states. All four entries in `DictationMode.defaults` omit `shortcutKeyCode`, so they all take the memberwise default of 54, and `VoxlyStore.init` assigns nothing. On a fresh install three of the four default modes are unreachable by any key, and the shortcut table in the README has never described real behaviour. The backlog entry covers the defaults and the "New mode" button together.

### 1.11 Refinement is blocked when only the CLI is missing

`LocalRefiner.refine` at [Services.swift:1326-1329](Sources/VoxlyApp/Services.swift#L1326-L1329) throws if `llama-cli` is not executable — *before* it ever tries the HTTP server, which is the primary path. A user who installed only `llama-server` gets no refinement at all.

Same class of problem in `ModelLocator.isInstalled` at [Services.swift:65-70](Sources/VoxlyApp/Services.swift#L65-L70): it requires `llama-cli` **and** `instruct.gguf`, and `begin()` refuses to record when `status.models` is false. So a user who only wants plain transcription cannot dictate at all — even though the README labels both llama artifacts "(Optional)".

**Fix direction:** split readiness into `transcriptionReady` and `refinementReady`. Gate recording on the first. Degrade refinement modes to raw text with a visible note when the second is false. Check for the CLI only on the CLI fallback path.

### 1.12 Holding a bare modifier for a normal shortcut starts a dictation

`receive()` at [DictationCoordinator.swift:37-54](Sources/VoxlyApp/DictationCoordinator.swift#L37-L54) starts recording on `flagsChanged` as soon as the mode's modifier is present, and while recording it ignores every `keyDown` except Escape. So pressing ⌘C, ⌘V, ⌘S or ⌘Tab **with the right-hand Command key** starts a full dictation: system output is muted, the fade-down runs, and on a Bluetooth headset the HFP↔A2DP switch is triggered — several seconds of silence and a degraded profile, for a stray copy.

`minTapSeconds` (0.3) only suppresses the transcription. It does not suppress the muting, the fade, or the error capsule.

This is the most significant usability problem in the product, and the one most likely to make someone stop using it.

**Fix direction, cheapest first:**

1. On any `keyDown` while recording, abort the dictation silently and restore audio. A chord is not a dictation. Cheap, high value.
2. Defer the mute and fade until `minTapSeconds` has elapsed, so short taps are completely inaudible.
3. Longer term, support real chords (⌃⌥, or Fn+key) as shortcut options, so users can pick something they never press by accident.

**Verdict:** accepted, and the "non-Escape" qualifier this item originally carried is gone with the Escape feature (1.1). Any `keyDown` aborts. These two ship together: this is what makes losing the manual cancel acceptable.

### 1.13 Release detection breaks when both modifiers of a pair are held

While recording, `finish()` triggers on `!modifierFlags.contains(flag)` at [DictationCoordinator.swift:44](Sources/VoxlyApp/DictationCoordinator.swift#L44). `.command` is set by *either* Command key, so a user holding both never finishes until both are released.

**Fix direction:** track the specific keyCode's press state with a per-key down/up ledger, rather than reading the aggregate flag set.

## 2. Latency and performance

Ordered by expected user-perceived impact.

### 2.1 The shipped app is a debug build

`scripts/package-app.sh` runs `swift build` with no `-c release` and copies `.build/debug/Voxly`. Everything installed to `/Applications` is unoptimized Swift. For code doing per-sample audio loops — `processInput` at [Services.swift:1022-1073](Sources/VoxlyApp/Services.swift#L1022-L1073) — the difference is not subtle.

**Fix direction:** `swift build -c release --package-path "$root"`, and copy from `.build/release/`. Highest value-per-character change in the repo.

### 2.2 The keypress path blocks the main actor on `osascript`

`begin()` → `recorder.start()` → `silencer.prepare()` is all synchronous on `@MainActor`, from [DictationCoordinator.swift:62](Sources/VoxlyApp/DictationCoordinator.swift#L62). `prepare()` at [Services.swift:376-413](Sources/VoxlyApp/Services.swift#L376-L413) spawns **two** `osascript` processes before capture starts (`OutputVolume.state()`, then `setMuted(true)`), each with a 6-second timeout. That sits between the user pressing the key and the microphone opening — the first words are lost if it's slow, and the whole UI is frozen while it happens.

The irony: `OutputHardware` already reads mute and volume from CoreAudio in microseconds at [Services.swift:142-177](Sources/VoxlyApp/Services.swift#L142-L177), with a comment explaining exactly why AppleScript was removed from the watchdog. The same argument applies to the write path.

**Fix direction:** add `OutputHardware.setMute` and `setVolumeScalar` via `AudioObjectSetPropertyData`, and make CoreAudio the primary path for snapshot, mute and restore — keeping AppleScript only as a fallback for devices that don't expose the properties. This removes the process spawns, the 6s timeout, and an entire class of stuck-osascript failure the comments document. Fades could then run in-process on a timer instead of inside a single `osascript` loop with `delay`, also freeing the 400–600 ms the fade currently occupies on the silencer queue.

### 2.3 Capture retries `Thread.sleep` on the main actor

`AVEngineBackend.attemptStart` at [Services.swift:874-921](Sources/VoxlyApp/Services.swift#L874-L921) sleeps `retrySleepInvalidFormatSeconds` (0.3) or `retrySleepStartFailureSeconds` (0.4) between up to `engineStartRetries` (7) attempts — on the main actor, via `begin()`. A Bluetooth device that needs the full retry budget freezes the entire app for two to three seconds.

**Fix direction:** make `AudioRecorder.start()` async and move the retry loop off the main actor (`Task.detached` plus `Task.sleep`), showing a "Preparing microphone" capsule state while the device negotiates.

### 2.4 Audio is captured at device format, not Whisper's format

`AVEngineBackend` writes the raw input format at [Services.swift:889](Sources/VoxlyApp/Services.swift#L889) — typically 48 kHz stereo Float32. One minute of that is about 23 MB, which is then read fully into memory via `Data(contentsOf:)` at [ModelServers.swift:121](Sources/VoxlyApp/ModelServers.swift#L121), copied again into a multipart body, POSTed over loopback, and resampled by whisper anyway.

16 kHz mono Int16 — exactly what Whisper wants — is about 1.9 MB for the same minute.

**Fix direction:** install the tap with an `AVAudioConverter`, or an explicit 16 kHz mono `AVAudioFormat`, and write that. Roughly 12× less I/O, less memory churn, and a measurably shorter gap between release and first token. Stream the multipart body from disk with `URLSession.uploadTask(with:fromFile:)` instead of building it in memory.

### 2.5 The Bluetooth IOProc does file I/O inside the realtime callback

`processInput` at [Services.swift:1022-1073](Sources/VoxlyApp/Services.swift#L1022-L1073) runs in the device's realtime render thread and, per callback, allocates an `[Int16]`, allocates a `Data` and calls `FileHandle.write` (a syscall), then dispatches a closure to the main queue for the level meter.

All three are realtime-unsafe. Under load — which is exactly the whisper-plus-llama scenario — this invites dropouts in the recording, and the level-meter dispatch floods the main queue at the callback rate.

**Fix direction:** write into a preallocated lock-free ring buffer in the callback, drain it on a dedicated serial queue, and throttle the level callback to about 30 Hz by accumulating peak and publishing on a timer. The same throttle is worth applying to `AVEngineBackend`.

### 2.6 The first dictation after launch never uses the servers

`ModelServerManager.launchOwned` at [ModelServers.swift:32-38](Sources/VoxlyApp/ModelServers.swift#L32-L38) spawns the process and returns immediately. Nothing waits for `/health`. A dictation in the first several seconds gets an HTTP failure and falls back to the CLI — which loads the model from scratch — or fails outright. The user sees a slow or broken first dictation with no explanation, which is the worst possible first impression.

**Fix direction:** poll `/health` after launch, publish a `serversReady` flag, show a "Warming up" state in the menubar and Diagnostics, and either queue or politely refuse dictations until ready.

### 2.7 Server startup blocks the main actor on `lsof` and `ps`

`reclaim` at [ModelServers.swift:43-66](Sources/VoxlyApp/ModelServers.swift#L43-L66) runs `lsof` and one `ps` per PID through the synchronous `LocalProcess.run`, with a 3s timeout each, from inside a `Task { @MainActor in ... }`. Worst case that is several seconds of frozen UI at launch.

**Fix direction:** run all of `ModelServerManager.start()` off the main actor; it touches no UI. Consider replacing `lsof` plus `ps` with a PID file written at launch — cheaper, and unambiguous about ownership.

### 2.8 `LocalProcess.run` can deadlock, and busy-waits

[Services.swift:1466-1487](Sources/VoxlyApp/Services.swift#L1466-L1487) reads both pipes *after* `waitUntilExit()`. A child that writes more than the pipe buffer (about 64 KB) blocks forever, and so does Voxly. `whisper-cli` and `llama-cli` are run with quiet flags today, but the fallback paths are exactly where verbose error output shows up. The `timeout` path also busy-waits with `usleep(20_000)` on the calling thread.

**Fix direction:** read both pipes concurrently, and use `process.terminationHandler` with a continuation instead of the polling loop. Making the whole function `async` would remove most of the blocking-on-main problems above at the source.

### 2.9 History is a single JSON blob in `UserDefaults`, re-encoded per dictation

`@Published var history { didSet { saveHistory() } }` at [Stores.swift:7](Sources/VoxlyApp/Stores.swift#L7) re-encodes the entire array on the main actor on every insert, and there is no cap. `UserDefaults` is not meant for growing blobs; after a few thousand dictations this is a visible hitch on every dictation and a bloated preferences file.

**Fix direction:** move history to a JSONL or SQLite file in the app's support directory, write incrementally off the main actor, and cap it with a config key plus a "keep last N / N days" control. Modes can stay in `UserDefaults` — they're tiny.

### 2.10 Decoding parameters are probably mistuned

`whisperBeamSize: 5` with `whisperBestOf: 5` and `whisperTemperature: 0` at [Config.swift:24-27](Sources/VoxlyApp/Config.swift#L24-L27): with beam search at temperature 0, `best_of` adds no accuracy — it's a temperature-sampling knob — while `beam_size 5` costs roughly two to three times the decode time of greedy. Meanwhile the default model is `ggml-small.bin`, which is the real accuracy bottleneck for Portuguese.

**Fix direction:** benchmark `large-v3-turbo-q5_0` at `beam_size 1-2` against `small` at `beam_size 5`, on real Portuguese dictations. On Apple Silicon with Metal the turbo model is usually both faster *and* substantially more accurate, which would let the beam width come down.

### 2.11 Log writing is wasteful and unbounded

`VoxlyLog.log` at [Services.swift:8-25](Sources/VoxlyApp/Services.swift#L8-L25) allocates an `ISO8601DateFormatter` per call and opens, seeks and closes the file per line. It's called from the watchdog path and from per-dictation hot paths. The log file also never rotates.

**Fix direction:** a static formatter, one long-lived `FileHandle` behind a serial queue, and size-based rotation (say 2 MB, keeping one previous file).

## 3. Usability and UX

### 3.1 There is no onboarding, and no model download

Spec §5.7 requires a first-run explanation, permission requests, and an in-app download with progress, size, completion and failure states. Reality: the app opens its main window, Diagnostics shows three red rows, and "Local models" opens a Finder window on an empty folder. The user is expected to build whisper.cpp and llama.cpp themselves and symlink four artifacts with exact names.

This is the largest gap between spec and build, and it caps the product at "works for its author".

**Fix direction:** a first-run flow that explains the local-only model, requests Microphone and Accessibility inline, and downloads the Whisper and instruct models from a pinned URL with SHA-256 verification and a progress bar. The engine binaries are the harder half — either vendor prebuilt arm64 binaries in the bundle, or link whisper.cpp and llama.cpp as SwiftPM dependencies and drop the server/CLI split entirely.

### 3.2 Permission status goes stale

`refreshStatus()` runs at `start()` and when the user clicks "Check permissions". Accessibility is granted in System Settings, outside the app — so the normal flow is: click Allow, grant it, come back, and find Voxly still saying it's missing until you happen to find the button. `begin()` then refuses to record.

**Fix direction:** poll `AXIsProcessTrusted()` on a low-frequency timer while any permission is missing, and on `NSApplication.didBecomeActiveNotification`. Same for the microphone.

### 3.3 The menubar icon never reflects state

The icon is static — [VoxlyApp.swift:71-78](Sources/VoxlyApp/VoxlyApp.swift#L71-L78). Spec §6 puts status in the menubar as the `Ready` state's feedback. Today the only state indicator is the capsule, which isn't visible when idle.

**Fix direction:** tint or swap the icon for recording (green), processing (amber) and error (red), and show the active mode name in the popover.

### 3.4 The capsule is bottom-centre, not near the cursor, and can't be clicked

Spec §6 describes a capsule that "accompanies the recording". The implementation pins it to `visibleFrame.minY + 24`, horizontally centred — [VoxlyApp.swift:116-126](Sources/VoxlyApp/VoxlyApp.swift#L116-L126) — and sets `ignoresMouseEvents = true`.

Bottom-centre is a defensible choice, since it never occludes the text field. Two things are still missing: it doesn't follow the active screen's cursor position as specced, and there's no way to stop or cancel with the mouse.

**Fix direction:** keep the position, but make the capsule interactive — click to stop early, ⌥-click or a small ✕ to cancel. That also gives keyboard-averse users a path, and it's the natural home for the "undo last insertion" affordance in 4.5.

**Verdict:** rejected. The capsule's behaviour is intentional and does not change: fixed at bottom centre of the screen containing the pointer, and non-interactive. Bottom centre never occludes the field being dictated into, which is worth more than following the cursor, and there is to be no click, stop or cancel affordance there. The documentation is what is wrong, so the spec changes instead — §4 step 3 and §6 Surfaces — and it states explicitly that the capsule is non-interactive so this does not get re-proposed. Undo (4.5) needs a different home.

### 3.5 The mode editor loses unsaved edits silently

`ModesView` keeps a `draft`; selecting another mode overwrites it at [ContentView.swift:49](Sources/VoxlyApp/ContentView.swift#L49) with no indication that anything was lost. Switching sidebar sections does the same. There's also no ⌘S, and `error` doubles as the success channel (`error = "Saved"` at [ContentView.swift:68](Sources/VoxlyApp/ContentView.swift#L68)), so "Saved" stays on screen indefinitely and is styled by a string comparison.

**Fix direction:** either autosave on field change — simplest, and matches how macOS settings behave — or show a dirty indicator and confirm on navigation away. Split `error` into `validationError` and a transient `savedAt` timestamp.

### 3.6 History is read-only

`HistoryView` can search and delete, but not copy, re-insert or expand. The raw text is stored but never shown, so the "keep raw text for audit" requirement in spec §5.2 has no UI at all. For a dictation tool, "the paste went to the wrong window, let me grab that text again" is a constant need.

**Fix direction:** per-row Copy for final and raw text, "Insert again", expand-to-full-text, and grouping by day. A disclosure showing raw versus final side by side is also the fastest way for a user to judge whether a mode's instructions are helping.

### 3.7 No way to pause Voxly, and no launch-at-login

If a mode's modifier conflicts with an app the user is in, the only remedy is quitting Voxly or editing the mode. And a menubar utility that must be launched by hand after every reboot won't stick.

**Fix direction:** a "Pause dictation" toggle in the popover, with the icon showing paused state, and `SMAppService.mainApp.register()` behind a "Launch at login" checkbox.

### 3.8 The app takes a Dock icon and opens a window at launch

`Info.plist` has no `LSUIElement`, and the `WindowGroup` means a settings window opens on every launch. For a push-to-talk menubar tool that's noise in ⌘-Tab and an unwanted window at login.

**Fix direction:** set `LSUIElement`, and open the main window only via the popover's "Open Voxly", which already uses `openWindow` and already activates the app.

### 3.9 Dark mode is forced

`.preferredColorScheme(.dark)` at [ContentView.swift:25](Sources/VoxlyApp/ContentView.swift#L25), plus a hardcoded palette in `VoxlyColor`. The spec's visual language does call for graphite and black, so this may well be deliberate — but it ignores the system setting, and the hardcoded colours also mean the capsule can't adapt to increase-contrast or reduce-transparency accessibility settings.

**Fix direction:** if the dark identity is intentional, keep it, but move the palette to an asset catalog with light variants and honour `accessibilityDisplayShouldIncreaseContrast`.

### 3.10 Config requires editing JSON and restarting

`AppConfig.current` is a `let` loaded once — [Config.swift:171](Sources/VoxlyApp/Config.swift#L171). Every knob, including model file, mute behaviour and thread counts, needs a text editor and a relaunch. The self-documenting `_help` block is a nice touch, but the knobs users actually want belong in the UI.

**Fix direction:** a real Settings section for the six or so user-facing keys (model file, `whisperPrompt`, mute-during-dictation, min tap, history cap), leaving the rest in JSON as escape hatches. Reload on change where the value allows it.

### 3.11 A tiny thing with an outsized effect: the trailing space

`inserter.insert(final + " ", into:)` at [DictationCoordinator.swift:131](Sources/VoxlyApp/DictationCoordinator.swift#L131) appends a space unconditionally. Good for chat, wrong for the "Code/technical notes" mode, wrong at the end of a paragraph, and it accumulates across consecutive dictations.

**Fix direction:** make it a per-mode option, or infer it from the character before the cursor once the AX path in 1.4 makes that readable.

**Verdict:** partially accepted, and the framing of this item is wrong. Chat is the primary use case — prompts for coding agents and messages to colleagues — not an equal alternative to code and technical notes. The trailing space is therefore correct by default, including across consecutive dictations that build up one message, and the default stays on. The per-mode toggle is for the minority of modes that produce standalone text, and it is low priority. The primary-versus-secondary use case is not derivable from the code, so it is being written into the spec.

### 3.12 Interface language versus audience

`Info.plist` declares `pt_BR` as the development region and the microphone usage string is in Portuguese, while the entire UI is English. The stated primary audience writes in Portuguese and English. Either way, the current mix is the one combination nobody asked for: a Brazilian user gets a Portuguese permission prompt and an English app.

**Fix direction:** pick one. If English is the product language, change `CFBundleDevelopmentRegion` and the usage string to match. If Portuguese matters, localize properly with `Localizable.strings` for pt-BR and en.

**Verdict:** English is the product language, because the project is meant to be global. The interface is not localized, and that decision goes into the spec so it is not revisited by accident. `CFBundleDevelopmentRegion` becomes `en` and the microphone string is rewritten in English — without hardcoding "Command direito", which is wrong for any mode whose shortcut the user changed. Portuguese stays a quality requirement rather than a localization one: transcription and refinement must work as well in Portuguese as in English, which is what 4.6 and 4.7 are for.

## 4. Product and feature opportunities

Ideas, not gaps. Ordered by my estimate of value to effort.

### 4.1 Per-app mode selection

`captureTarget()` already knows the frontmost application. Automatically choosing "Professional email" in Mail, "Code/technical notes" in the terminal or IDE, and "Clean text" in Slack would remove the whole "which key do I hold?" decision — the main cognitive cost of the multi-mode design.

Cheap to build: an optional bundle-ID list per mode, checked in `begin()` before falling back to the pressed shortcut's mode. This is the kind of thing that makes a local tool feel better than the cloud competition.

**Verdict:** accepted as an opt-in, not as a behaviour change. A config flag, default off, decides whether the frontmost app or the pressed shortcut selects the mode; with the flag off nothing changes for anyone. Whichever path runs, the chosen mode has to be visible in the capsule, or app-based selection is invisible and untrustworthy.

### 4.2 Streaming or chunked transcription

Today nothing starts until the key is released, so a 45-second dictation means waiting for the whole file. Whisper can transcribe 5–10s chunks as they arrive, showing partial text in the capsule and cutting perceived latency to near zero for long dictations.

Non-trivial — chunk boundaries and prompt continuity — but it's the single biggest possible improvement to how the product feels.

### 4.3 Text replacements and spoken commands

A user dictionary (`"nova linha"` → newline, `"ponto"` → `.`, `kubernetes` → `Kubernetes`) applied after transcription. The vocabulary field biases recognition; replacements fix the systematic misses that bias can't. Cheap, and every competitor has it.

### 4.4 Per-mode model selection

`modelProfile` already exists as dead weight. A "fast" (small, greedy) versus "accurate" (large-v3-turbo, beam) choice per mode would let "Faithful transcription" be instant and "Professional email" be careful. Requires two whisper servers or a reload, so measure first.

**Verdict:** accepted as a measurement, not as a build. Three approaches, each with something specific to measure: two resident servers (resident memory and Metal contention), restarting the server per switch (`whisper-server` cannot swap models at runtime, so measure the large model's load time), or varying only the decoding parameters per mode, which is nearly free since they are already sent per request and is the fallback if the other two measure badly. `modelProfile` itself is removed by 1.8; whatever ships uses an enum.

### 4.5 Undo last insertion

Pasting into the wrong field is the most common failure mode of any dictation tool. A five-second window where a shortcut, or a click on the capsule, deletes the inserted characters — the length is known — would take most of the sting out of 1.4 and 1.5.

### 4.6 Restrict automatic language detection to the two supported languages

`DictationLanguage.automatic` maps to Whisper's `auto` at [Models.swift:9](Sources/VoxlyApp/Models.swift#L9), which detects across all 99 languages. Portuguese is routinely detected as Spanish or Galician on short utterances, and the result is a mangled transcription with no signal that anything went wrong. Spec §5.2 asks for auto-detection *between the two*.

**Fix direction:** detect on the first pass, and if the detected language is neither `pt` nor `en`, re-run pinned to whichever `NLLanguageRecognizer` prefers on the raw text. Or transcribe short clips twice, pt and en, and pick by `avg_logprob` — expensive but exact.

### 4.7 Portuguese assistant-response detection

`looksLikeAssistantResponse` at [Services.swift:1436-1442](Sources/VoxlyApp/Services.swift#L1436-L1442) matches only English leads: `sure`, `certainly`, `here is`, and so on. The guard it implements is genuinely clever, and it's completely absent for the primary audience's language. `Claro`, `Com certeza`, `Aqui está`, `Segue`, `Vou` are the obvious additions.

### 4.8 `changesLanguage` false positive on a pinned mode

`sourceLanguage(for:configuredLanguage:)` at [Services.swift:1444-1452](Sources/VoxlyApp/Services.swift#L1444-L1452) returns the *configured* language without inspecting the text. So in a mode pinned to Portuguese, a user who dictates one English sentence has their refinement discarded as a "language change" — silently, keeping raw text.

**Fix direction:** when a language is pinned, compare the refined output against the detected language of the *raw text*, not the configured one.

## 5. Architecture, maintainability, tests

### 5.1 `Services.swift` is 1,506 lines of unrelated concerns

Logging, errors, permissions, CoreAudio device queries, AppleScript volume control, the output silencer, two capture backends, WAV writing, transcription, refinement, process spawning and text insertion all live in one file. Every one of those is independently testable; none of them is currently isolated.

**Fix direction:** split along the seams that already exist — `Log.swift`, `Permissions.swift`, `AudioDevices.swift`, `OutputSilencer.swift`, `Capture/{AVEngineBackend,IOProcBackend,WAVWriter}.swift`, `Transcriber.swift`, `Refiner.swift`, `Process.swift`, `TextInserter.swift`. No behaviour change, and it makes 5.3 possible.

### 5.2 The silencer's complexity may exceed its value

`RecordingOutputSilencer` is about 550 lines with 15 pieces of mutable state, two locks, three CoreAudio listeners, a watchdog timer, an adoption protocol and five distinct completion paths. The comments are excellent and every branch is justified by a real bug. But the feature it delivers — muting system output during dictation — is not in the product spec at all, and it currently runs for **every** dictation, including built-in-mic ones where there is no HFP transition and no echo risk.

Two questions worth answering before investing further:

1. Should this be opt-in? A config key `silenceOutputDuringDictation`, or restricting it to the case where input and output are the same Bluetooth device, would let most users skip the entire machine.
2. Would CoreAudio-only control (2.2) collapse enough of the state to make the rest tractable? Much of the complexity exists to work around slow, flaky `osascript` calls.

**Verdict:** question 1 is answered no, and the framing was wrong. Muting output while recording is a core behaviour, on by default, with no config key and no toggle — it is what comparable dictation tools do and what any app capturing audio while something plays is expected to do. The gap this item found is real but it is a documentation gap: the behaviour belongs in the spec, along with the A2DP/HFP constraint that makes the restore delayed, since that delay otherwise reads as a bug.

Narrowing it to "input and output are the same Bluetooth device" is rejected for a second reason: it is backwards. A Bluetooth headset is the case with the least echo risk, because the output is in the user's ears. Built-in mic with speakers playing is the case that most needs muting.

Question 2 is accepted as the plan. CoreAudio (2.2) lands first, then the state that existed only to survive slow `osascript` calls gets re-measured and removed — with the decision table pinned down by tests before anything is rewritten.

### 5.3 The most complex code has the least test coverage

Two test files, 96 lines, covering `mergedPrompt`, `looksLikeAssistantResponse`, `changesLanguage` and one Codable migration. Those are good tests — the migration one in particular documents a real hazard. But there's nothing for the silencer state machine, the coordinator's superseded/cancelled logic, WAV header writing, or shortcut resolution.

Highest-value additions, in order:

1. `DictationCoordinator` state transitions (begin → finish → cancel → supersede), with `AudioRecorder`, `TextInserter` and the transcriber behind protocols. This is where the teardown leak (1.2), the abort-on-keypress path (1.12) and the release detection (1.13) live, and all become trivially testable once the dependencies are injectable.
2. `IOProcBackend`'s WAV header and patch logic against a known-good byte layout. The comment at [Services.swift:1086-1088](Sources/VoxlyApp/Services.swift#L1086-L1088) records exactly the kind of off-by-two a test would have caught instantly.
3. The silencer's decision table — bluetooth × rateLeftBaseline × userOverride × deviceChanged, mapped to the chosen completion path — with CoreAudio behind a protocol.

### 5.4 Redundant `Task.detached` around async work

`process()` wraps `transcriber.transcribe` and `refiner.refine` in `Task.detached` at [DictationCoordinator.swift:110](Sources/VoxlyApp/DictationCoordinator.swift#L110) and [line 124](Sources/VoxlyApp/DictationCoordinator.swift#L124), then immediately awaits `.value`. Both are already `async` and spend their time in `URLSession`, so the detach buys nothing and just adds a hop. It *would* matter for the CLI fallback paths, which are synchronous and blocking — which suggests the detach belongs inside those functions instead.

### 5.5 Config boilerplate is triplicated

Every key in `VoxlyConfig` is written four times — property, `decodeIfPresent`, `encode`, `CodingKeys` — plus a fifth in the `help` dictionary. That's 200 lines for 31 settings, and adding one means five edits with no compiler check that you did all five.

**Fix direction:** synthesized `Codable` plus a `@propertyWrapper` carrying the default and the help string would collapse this to one line per key. Or, since the file is regenerated anyway, decode into a dictionary and read through a defaulting accessor.

### 5.6 Smaller items

- The local event monitor's return value is discarded and never removed — [DictationCoordinator.swift:28](Sources/VoxlyApp/DictationCoordinator.swift#L28).
- `handleRunningEvent()` is empty; the `runningAddress` listener is installed for nothing — [Services.swift:674-676](Sources/VoxlyApp/Services.swift#L674-L676).
- `OutputVolume.level()` and `isMuted()` are no longer used by the hot paths. Worth checking whether they're dead.
- `AGENTS.md` links point at `/Users/ivanseibel/dev/personal/voxly`, which is not this checkout's path.
- Most of `ContentView.swift` is single-line view declarations 200–400 characters wide. It's consistent, so it's a style choice, but it makes diffs unreadable and line-level review nearly impossible.

## 6. Privacy and security

The privacy posture is genuinely good: loopback-only servers, no telemetry, no network calls after install. Three things undercut the claims:

1. **`FailedAudio/` persists recordings indefinitely** (1.3). This directly contradicts the README's "audio buffers are deleted immediately after processing" and spec §8's "no audio persists after the dictation cycle".
2. **Cancelled dictations leak their WAV to `/tmp`** (1.2). Same contradiction.
3. **The clipboard holds the dictated text for 650 ms**, readable by any process on the machine, and isn't cleared when the paste fails (1.5). Worth stating plainly in the README — it's the unavoidable cost of the ⌘V approach, and another argument for the AX path in 1.4.

Two smaller notes:

- The local servers accept unauthenticated requests from any process on the machine. That's normal for loopback tooling, but `llama-server` will happily answer arbitrary prompts and `whisper-server` will transcribe arbitrary audio for whoever asks. Worth a line in the README.
- `voxly.log` records transcription previews (`result: \(result.prefix(80))` at [Services.swift:1381](Sources/VoxlyApp/Services.swift#L1381)) and mode instructions. Unbounded and unrotated, that's a growing plaintext record of what the user dictated. Either drop the content from the log, or put it behind a debug flag.

## 7. Packaging and distribution

1. **Debug build shipped.** See 2.1. Fix this first.
2. **No notarization path.** Spec §7 requires signed *and notarized* distribution; `package-app.sh` ad-hoc-signs with a local development identity. Correct for local iteration, but there's no path to a build another person can run without a Gatekeeper fight. A `--options runtime` plus `notarytool` variant behind an env flag would unblock the first external tester.
3. **`Info.plist` version is hardcoded** to `0.1.0` / `1`, with no bump in the scripts. Every build reports the same version, which makes "which build am I running?" unanswerable and breaks any future update check.
4. **No update mechanism.** For an app distributed outside the App Store, Sparkle or an in-app check against a GitHub release feed is the conventional answer.
5. `xattr -dr com.apple.quarantine` in `build-install.sh` is fine for a local install, but shouldn't survive into anything a third party runs.

**Verdict:** accepted, and the sequence matters more than the list. The project has not been announced and the only users are two developers who build from source, but it should be installable by someone without a toolchain — so the distribution channel is a decision to settle before any of this is built. Two constraints to confirm first: the App Store is likely not viable (child processes, global event monitors, Accessibility), which leaves Developer ID plus notarization and a paid account; and notarization requires the hardened runtime, so whether the engine binaries live inside the bundle or get downloaded at runtime is part of that decision rather than a detail to discover afterwards. Version stamping is the one piece that is unambiguous and can go immediately.

## 8. Documentation drift

| Where | Claim | Reality |
| --- | --- | --- |
| `README.md:144` | Config key `duckVolumeFactor`, default `0.1` | **Key does not exist** in `VoxlyConfig`. The mute-and-fade behaviour replaced it and the table was never updated. Setting it produces no effect and no warning — unknown keys are silently ignored. |
| README | AX-based insertion with clipboard fallback | Clipboard-only (1.4) |
| README | Audio buffers deleted immediately after processing | `FailedAudio/` and the cancel path contradict it (1.2, 1.3) |
| README | `llama-cli` and `instruct.gguf` are "(Optional)" | App refuses to record without them (1.11) |
| `PRODUCT_SPEC.md` §5.7 | Model download, verification, progress, onboarding | Entirely unimplemented (3.1) |
| `PRODUCT_SPEC.md` §5.5 | AX insertion, clipboard preservation | Partially implemented (1.4, 1.5) |
| `PRODUCT_SPEC.md` §6 | Capsule near the cursor, menubar status | Partially implemented (3.3, 3.4) |
| `AGENTS.md` | File links | Point to a path that doesn't exist in this checkout |
| Nowhere | System-output muting | Undocumented, though it's arguably the most surprising behaviour the app has — it silences the user's music on every press of the shortcut modifier |

## 9. Where the accepted work lives

The shortlist this section used to hold has been superseded. Every item above now has a disposition, and the accepted work is grouped into priority sections in [BACKLOG.md](BACKLOG.md), where the order inside each section is the intended execution order. This map exists so an item here can be traced to the section that carries it.

| Backlog section | What it holds | Items from this review |
| --- | --- | --- |
| P0 — Losing text, losing audio, broken defaults | Small and independent; each one either loses user data or ships a default that cannot work | 2.1, 1.1, 1.12, 1.2, 1.3, 6 (log content), 1.4 step 1, 1.5, 1.10, 1.11, 1.13 |
| P1 — Cheap wins and language parity | Bounded changes with visible effect, plus the three Portuguese-parity items | 1.6, 1.7, 1.8, 2.10, 4.6, 4.7, 4.8, 1.9, 8 |
| P2 — Latency spine | Keypress to inserted text; `LocalProcess.run` goes first as the root cause of three others | 2.8, 2.2, 2.7, 2.3, 5.4, 2.4, 2.5, 2.6, 2.9, 2.11 |
| P3 — Usable by a non-developer | The batch that lets someone else install and live with it; the distribution decision leads | 7, 3.1, 7 (versioning), 3.12, 3.8, 3.7, 3.2, 3.3, 3.5, 3.10, 1.4 step 2, 4.5, 6 (privacy docs), 3.4 (docs only) |
| P4 — Foundations | Refactors that make the rest cheaper; the order is a real dependency chain | 5.1, 5.3, 5.2, 5.5, 5.6 |
| P5 — Bets | Features that change what the product is rather than fixing what it claims to be | 4.1, 4.3, 4.2, 4.4, 3.6, 3.11, 3.9 |

Section order is not a strict gate — documentation-only work rides along with whatever is being touched. The chains that do bind: honest insertion reporting (1.4 step 1) → clipboard restore (1.5) → undo (4.5) → the Accessibility path (1.4 step 2); async `LocalProcess.run` (2.8) → the main-actor fixes (2.2, 2.3, 2.7); 16 kHz capture (2.4) → streaming (4.2); the `Services.swift` split (5.1) → tests (5.3) → the silencer simplification (5.2); release build (2.1) plus version stamping plus onboarding (3.1) → distribution (7).
