# Voxly — backlog

Updated on 2026-08-27.

Entries are grouped into priority sections, and the order inside each section is the intended execution order. Moving an entry between sections is how work gets reprioritised. Dependencies are named in the entries themselves, so an entry can be read on its own.

Section order is not a strict gate: documentation-only entries and small items can ride along with whatever is being worked on. The dependency chains that do matter are: honest insertion reporting → clipboard restore → undo → the Accessibility path; async `LocalProcess.run` → the main-actor fixes; 16 kHz capture → streaming; the `Services.swift` split → tests → the silencer simplification; release build plus bundled engine helpers plus onboarding plus version stamping → first external release → Sparkle updates.

## P0 — Losing text, losing audio, broken defaults

Small, independent, and each one either loses user data or ships a default that cannot work.

### The packaged app is a debug build

`scripts/package-app.sh` runs `swift build --package-path "$root"` with no configuration flag and then copies `.build/debug/Voxly` into the bundle. Everything installed to `/Applications`, by every user, is unoptimized Swift with bounds checks and no inlining.

This matters most in exactly the code that can least afford it: the per-sample loops in `processInput`, the level-meter reduction in the capture tap, and WAV conversion.

Intended fix: `swift build -c release --package-path "$root"` and copy from `.build/release/Voxly`. Highest ratio of effect to effort in the repository, and it changes the baseline for every latency measurement taken afterwards, so it goes first.

### Remove Escape-to-cancel instead of fixing it

`receive()` in `DictationCoordinator` treats any `keyDown` matching `AppConfig.current.cancelKeyCode` (53 = Escape) as a cancel request and calls `cancel()`. That path is broken: `cancel()` only bumps `latestDictationID`, so a dictation already transcribing or refining still reaches `inserter.insert(final + " ", into:)` and pastes its text seconds after the user was told "Dictation canceled". It also drops the WAV returned by `stopAndRemove()` without deleting it, because setting `backend = nil` makes the following `discard()` a no-op.

Decision: drop the feature rather than repair it. The escape hatch is not worth the state it needs — a dictation that should not have started can be released and ignored.

Scope:

- Remove the Escape branch from `receive()`.
- Remove the `cancelKeyCode` config key: property, `decodeIfPresent`, `encode`, `CodingKeys` case, and its `_help` entry. Unknown keys are ignored on load, so existing `config.json` files keep working untouched.
- Remove the "Pressing **Escape** during an active dictation immediately cancels recording" tip from `README.md`, and the cancellation requirement from `PRODUCT_SPEC.md` §5.5, so neither promises behaviour the app no longer has.
- Keep the teardown path. `applicationWillTerminate` calls `cancel()` to stop capture before the volume restore runs, and that ordering is load-bearing for Bluetooth HFP. Either keep the method and stop routing key events to it, or rename it to something termination-specific so its remaining caller is obvious.

Consequence to accept: once this ships there is no way to abort a dictation in flight. Releasing the shortcut transcribes and inserts; only holds shorter than `minTapSeconds` are discarded. The chord entry below is what makes that acceptable, so the two should ship together.

### Any chord using the shortcut modifier starts a full dictation

`receive()` begins recording on `flagsChanged` as soon as a mode's modifier is present, and while recording it ignores every other key. So pressing ⌘C, ⌘V, ⌘S or ⌘Tab with the right-hand Command key starts a dictation: `silencer.prepare()` mutes system output, the fade runs, and on a Bluetooth headset the A2DP→HFP switch is triggered — several seconds of silence and a degraded audio profile, for a stray copy.

`minTapSeconds` does not help. It is checked in `finish()`, after the fact, and only suppresses transcription. The mute, the fade and the profile switch have already happened.

This is the most likely reason for someone to stop using the app: it punishes ordinary keyboard use.

Intended fix, cheapest first:

- Abort the dictation silently on any `keyDown` received while recording. A chord is not a dictation. Stop capture, restore audio, no capsule, no error. This supersedes the Escape branch removed by the entry above, and is the reason removing Escape is acceptable — the common case stops needing a manual escape hatch.
- Defer `silencer.prepare()` and the fade until `minTapSeconds` has elapsed, so short taps are completely inaudible and cost nothing.
- Longer term, allow real chords (⌃⌥, or Fn plus a key) as shortcut options, so a user can pick something they never press by accident.

### Quitting mid-recording leaves the WAV in the temp directory

`AudioRecorder.stopAndRemove()` sets `backend = nil` before returning the file URL, so the `discard()` that follows it in the teardown path has no backend to call and does nothing. Quitting Voxly while a dictation is recording therefore leaves `voxly-<uuid>.wav` in the system temp directory, holding the user's voice until macOS decides to clean it up on its own schedule.

This is the residual half of the cancel-path leak. Removing Escape-to-cancel removes the user-facing route into it, but `applicationWillTerminate` still calls the same method, so the leak survives that change.

Intended fix: delete the URL `stopAndRemove()` returns when the audio is not going to be processed, rather than relying on `discard()`. Either have the teardown path remove the returned file explicitly, or give the recorder a single "stop and delete" entry point so no caller can hold a URL it is expected to clean up. The Bluetooth-safe ordering in `applicationWillTerminate` — capture stops before the volume restore — must not change.

### Failed dictations keep their audio on disk forever

Every error path in `process()` sets `shouldRemoveAudio = false` and calls `preserveAudioForDebug(audio)`, which moves the WAV into `~/Library/Application Support/Voxly/FailedAudio/`. Nothing ever deletes those files, nothing surfaces them in the UI, and neither `README.md` nor `PRODUCT_SPEC.md` mentions the directory.

Observable effects: a user whose whisper server is down for a while accumulates one recording of their own voice per attempt, indefinitely, in a folder they have no reason to look in. This directly contradicts the README's "Audio buffers are deleted immediately after processing" and §8 of the spec, which is the product's central privacy claim.

Intended fix:

- Add a config key `keepFailedAudioForDebug`, default `false`. When false, failures delete the WAV like every other path — `shouldRemoveAudio` stays true and `preserveAudioForDebug` is not called.
- When true, cap the directory: prune at launch to the most recent N files, or drop anything older than a few days. Log what was pruned, so a debugging session can tell "no file" from "file already collected".
- Surface it in Diagnostics: a row showing whether preservation is on, the number of files and total size, with "Reveal in Finder" and "Delete all" — the same treatment `HistoryView` already gives text.
- Document the key in the `_help` block, and say plainly in the README that audio is preserved only when this is explicitly turned on.

### The log records what the user dictated

`voxly.log` writes an 80-character preview of every transcription result, and mode instructions along with it. The file is unbounded and unrotated, so over time it becomes a growing plaintext record of what the user has been dictating, sitting in Application Support with no indication that it exists.

That is a privacy problem independent of the log's write performance, and it undercuts the same claim the preserved-audio directory does.

Intended fix: stop logging transcription and refinement content by default. Log lengths, durations and outcomes, which is what the log is actually used for when diagnosing latency, and put the text previews behind an explicit debug flag in `config.json`, documented in the `_help` block as recording dictated content. Size and rotation are the separate log-writing entry in P2.

### Text insertion is clipboard-only, and reports success it cannot verify

`TextInserter` has three separate problems, all in the same ten lines:

- `captureTarget()` stores `AXUIElementCreateSystemWide()`, a process-wide constant. It records nothing about the element that had focus, so "restore the original focus" is only `target.app?.activate()`, at app granularity. The `focused` field of `Target` carries no information.
- `insert()` always goes through the clipboard and a synthesized ⌘V. The Accessibility path described in §5.5 of the spec, and advertised in the README as "injects transcribed text into the focused text field using macOS Accessibility APIs, with automatic fallback to clipboard paste", does not exist.
- It returns `.inserted` whenever the two `CGEvent`s could be *constructed*. Construction essentially never fails, so `.copied` is unreachable, the `insertion` field in history is meaningless, and the capsule says "Text inserted" even when the paste went nowhere.

Observable effects: pasting into a password field or any app with Secure Event Input enabled silently swallows the ⌘V, and Voxly still reports success. The user then discovers the text is gone, and history claims it was inserted. Combined with the unconditional clipboard restore, the result is also erased from the clipboard 0.65s later, so there is nothing left to recover.

Intended fix, in two independent steps:

1. Make the reporting honest first, since it is small and self-contained. Check `IsSecureEventInputEnabled()` before synthesizing the keystroke and return `.copied` when it is on, leaving the text on the clipboard. This alone turns the worst failure into a recoverable one.
2. Then build the real Accessibility path. At capture time, read `kAXFocusedUIElementAttribute` from the frontmost app's `AXUIElement` and store that in `Target.focused`. At insert time, try `AXUIElementSetAttributeValue(focused, kAXSelectedTextAttribute, text)` and fall back to ⌘V only when it fails. Where it works this removes the clipboard round-trip entirely, along with the restore race, the `Thread.sleep` on the main actor, and the window in which the dictated text is readable by every other process on the machine.

Step 1 belongs here in P0. Step 2 is P3 work — it is a bigger change and it lands with the batch that makes the app usable by someone else. Until it does, the README and the spec overstate what the app does; fix the claims or fix the code, not neither.

### The clipboard restore can destroy the dictated text

`insert()` schedules an unconditional restore of the previous clipboard `clipboardRestoreDelaySeconds` (0.65) after posting ⌘V. Three consequences:

- If the paste failed — secure input field, unresponsive app, focus moved — the result is wiped from the clipboard too, so the dictation is unrecoverable. §5.5 of the spec explicitly requires leaving the text on the clipboard when insertion does not succeed.
- Only `.string` is preserved. `prior` is read as a string, so a user who had an image, a file promise, or rich text on the clipboard gets it replaced with either plain text or nothing.
- If the user copies something during the 0.65s window, Voxly clobbers it with the older contents.

Intended fix:

- Restore only after a confirmed paste. Depends on insertion reporting the truth first, so it ships after step 1 of the entry above.
- Capture and replay all pasteboard types rather than just `.string`, or skip the restore entirely when the prior contents were not plain text — losing the restore is better than corrupting the clipboard.
- Record `pasteboard.changeCount` after writing the dictated text and compare before restoring. If it changed, another process wrote to the clipboard and Voxly must leave it alone.

### Default and newly created modes collide on the same shortcut

Two related problems with the same effect.

All four entries in `DictationMode.defaults` omit `shortcutKeyCode`, so they all take the memberwise default of 54 (⌘ Right), and `VoxlyStore.init` uses `DictationMode.defaults` as-is without assigning shortcuts. `receive()` resolves a pressed key with `store.modes.first(where:)`, which always matches "Faithful transcription". On a fresh install "Clean text", "Professional email" and "Code/technical notes" are unreachable — no key combination invokes them. The shortcut table in `README.md` that maps ⌥ Right to "Clean text" has never described real behaviour.

The "New mode" button has the same bug: it appends `DictationMode(name: "New mode", ...)` with the default keyCode 54, which the first mode already owns. `ShortcutRecorder` checks `store.shortcutKeyTaken` when the user records a new key, but nothing checks at creation, so the new mode is born unreachable. §5.1 of the spec requires Voxly to prevent duplicate shortcuts.

Intended fix:

- Give each default mode an explicit distinct `shortcutKeyCode`, matching what the README already promises.
- Assign the first free modifier key when creating a mode; if none is free, disable the "New mode" button with an explanation rather than creating a dead mode. There are 9 modifier key codes and modes are capped at 4, so a free key always exists in practice.
- Show a conflict badge in the mode list for any mode whose shortcut is shadowed, so an imported or hand-edited state is visible rather than silent.

### Transcription-only installs cannot record at all

`ModelLocator.isInstalled` requires four files: `whisper-cli`, the whisper model, `llama-cli` and `instruct.gguf`. `PermissionManager.refresh` maps it to `status.models`, and `begin()` refuses to record when that is false. So a user who installed only the transcription half gets "Install local models before dictating" and cannot dictate, even though the README labels both llama artifacts "(Optional)".

`LocalRefiner.refine` has the same shape one level down: it throws when `llama-cli` is not executable *before* attempting the HTTP request, so a user running only `llama-server` — the primary path — gets no refinement.

`isInstalled` also checks only the CLI binaries, never `whisper-server` or `llama-server`, so readiness is computed from the fallback path rather than the one actually used.

Intended fix:

- Split readiness into `transcriptionReady` and `refinementReady`, each satisfied by either the server or the CLI plus its model.
- Gate recording on `transcriptionReady` alone.
- When `refinementReady` is false, run refinement modes as raw transcription with a visible note, reusing the existing "Refinement failed; raw text kept" path rather than failing the dictation.
- Check for `llama-cli` only inside the CLI fallback, after the HTTP attempt.
- Report the two states separately in Diagnostics so "why can't I dictate" and "why isn't it cleaning my text" are distinguishable.

### Holding both keys of a modifier pair never ends the dictation

While recording, `finish()` is triggered by `!modifierFlags.contains(flag)`, where `flag` comes from `shortcutModifiers`. `.command` is set by *either* Command key, and the same is true for `.shift`, `.option` and `.control`.

Observable effect: a user holding both Command keys — or who presses left Command while dictating with right Command — keeps recording until both are released. The dictation appears stuck, and since it never calls `finish()`, releasing only the shortcut key does nothing.

Intended fix: track the pressed state of the specific key code rather than reading the aggregate flag set. `flagsChanged` reports `keyCode`, so a small per-key ledger updated on each event gives an exact answer for which physical key is down. Finish when that key's own entry goes up.

## P1 — Cheap wins and language parity

Bounded changes with visible effect, including the three items that make Portuguese work as well as English — a stated quality requirement, not a localization one.

### Refinement is silently truncated at 256 tokens

`ModelServerManager.chat` sends `max_tokens: AppConfig.current.refineMaxTokens`, which defaults to 256, and `ChatResponse` decodes only `choices[].message`. The `finish_reason` the server returns is discarded, so a generation that stopped because it hit the limit is indistinguishable from one that finished.

Observable effect: a dictation longer than roughly two paragraphs, run through any refinement mode, is cut mid-sentence and inserted as if complete. The capsule reports success and history stores the truncated text as the final result. The user has no signal that anything was lost, and the raw text — which was complete — is only visible if they go looking for it, and today history has no UI to show it.

`llamaContextSize` (2048) has the same failure shape from the prompt side: a long transcription plus the mode's instructions can exceed the window, and the server truncates the input rather than refusing it.

Intended fix:

- Decode `finish_reason` on `ChatChoice` and throw when it is `"length"`. `LocalRefiner.refine`'s caller already catches refinement failures and keeps the raw text with a "Refinement failed; raw text kept" message, so a complete unrefined transcription is delivered instead of a truncated refined one. That machinery exists and is the right behaviour here.
- Scale `max_tokens` from the input length instead of using a fixed 256 — refinement rewrites text, so the output length tracks the input. Roughly `max(refineMaxTokens, estimatedInputTokens * 1.5)` would cover the modes that expand text, with `refineMaxTokens` becoming a floor rather than a ceiling.
- Consider raising `llamaContextSize`, or rejecting refinement up front when the estimated prompt does not fit, so the prompt side fails loudly too.

### Whether a mode refines is decided by comparing its name to a string literal

`DictationMode.usesRefinement` is `name != "Faithful transcription" && !instructions.trimmed.isEmpty`. A mode's behaviour therefore depends on its title, and the title is a free-text field the user is invited to edit.

Observable effects:

- Renaming "Faithful transcription" to anything else silently turns refinement on, using the instructions "Preserve speech; adjust only obvious punctuation and capitalization." — text that ships with the mode and was never meant to reach the model.
- Creating a mode named "Faithful transcription" silently exempts it from refinement no matter what its instructions say.
- The default mode ships *with* instructions visible in the editor that never execute. To anyone reading the UI, that is indistinguishable from refinement being broken.
- Clearing the instructions of a refinement mode silently converts it to raw transcription, with no indication in the editor that the mode changed kind.

Intended fix:

- Add a stored `usesRefinement: Bool` property with a matching `CodingKeys` case, encode/decode, and memberwise-init parameter, replacing the computed property.
- Migrate with `decodeIfPresent` falling back to the *current* expression, not to `!instructions.isEmpty` — otherwise an existing user whose stored mode is named "Faithful transcription" would find refinement switched on after the update.
- Add a toggle to `ModeEditor` next to the instructions field, and disable or hide the instructions editor when it is off, so the relationship between the two is visible instead of implied.
- Set it to `false` on the "Faithful transcription" default and `true` on the other three, so `DictationMode.defaults` states its intent directly.

### Remove the two dead mode settings

`DictationMode` carries two properties that nothing reads:

- `automaticInsert` has a switch in `ModeEditor` labelled "Insert automatically; clipboard as fallback", and is persisted, but no code path consults it. Toggling it changes nothing.
- `modelProfile` defaults to `"Balanced (local)"`, is persisted, and is never read or displayed anywhere.

Decision: remove both rather than wire them up. Neither is needed.

Scope:

- Delete both properties, their `CodingKeys` cases, their encode/decode lines, and their memberwise-init parameters.
- Delete the Output/`automaticInsert` toggle row from `ModeEditor`.
- `decodeIfPresent` is not involved on the way out: removing a `CodingKeys` case makes the stored keys unknown, and unknown keys are ignored, so existing persisted modes decode cleanly with no migration step.

Note for later: if per-mode model selection is ever built, it should introduce a field with a real type — an enum of available models — rather than reviving this free-text string.

### Whisper decoding parameters are mistuned

`whisperBeamSize` and `whisperBestOf` both default to 5, with `whisperTemperature` at 0. With beam search at temperature 0, `best_of` adds nothing — it selects among temperature-sampled candidates, and there is no sampling happening. Meanwhile `beam_size: 5` costs roughly two to three times the decode time of greedy, and the default model is `ggml-small.bin`, which is the real accuracy bottleneck for Portuguese.

Intended fix: benchmark `ggml-large-v3-turbo-q5_0.bin` at `beam_size` 1–2 against `small` at `beam_size` 5, on real Portuguese dictations, measuring both wall clock and error rate. On Apple Silicon with Metal the turbo model is usually both faster and substantially more accurate, which would let the beam width come down. Drop `whisperBestOf` from the config, or document that it only applies when temperature is above 0.

### Restrict automatic language detection to the two supported languages

`DictationLanguage.automatic` maps to Whisper's `auto`, which detects across all 99 languages. Short Portuguese utterances are routinely detected as Spanish or Galician, and the transcription comes back mangled with no signal that anything went wrong.

Intended fix: detect on the first pass, and if the detected language is neither `pt` nor `en`, re-run pinned to whichever of the two `NLLanguageRecognizer` prefers on the raw text. The alternative — transcribing short clips twice, once per language, and choosing by `avg_logprob` — is exact but doubles the cost, so it is only worth considering for clips under a couple of seconds.

Part of keeping Portuguese at parity with English.

### Portuguese assistant-response detection

`looksLikeAssistantResponse` guards against the refinement model answering the dictation instead of cleaning it up, but it matches only English openings — `sure`, `certainly`, `here is`. In Portuguese the guard does not exist, so a model that starts explaining gets its answer inserted as if it were the user's text.

Intended fix: add the Portuguese equivalents — `Claro`, `Com certeza`, `Aqui está`, `Segue`, `Vou` — and make the list per language rather than one flat array, so adding a language later means adding a list, not editing a regex.

### `changesLanguage` false positive on a pinned mode

`sourceLanguage(for:configuredLanguage:)` returns the configured language without inspecting the text. In a mode pinned to Portuguese, a user who dictates one English sentence has the refinement discarded as a "language change" and silently gets the raw text back, with the failure looking identical to the model being unavailable.

Intended fix: when a language is pinned, compare the refined output against the detected language of the raw text rather than the configured one. The guard should catch the model translating, which is a real failure, and ignore the user switching languages, which is not.

### The recording level meter never moves

`store.audioLevel` is published from the capture callbacks at roughly 24–40 Hz, but the capsule only re-renders when `onCapsule` fires, and `onCapsule` fires only on state transitions. `CapsulePanelController.set` also builds a brand new `NSHostingView(rootView: CapsuleView(state:level:))` on every call, and `CapsuleView` takes `level` as a plain `Float`.

Observable effect: during recording the meter holds whatever value it had when recording began, which is 0. The bar is empty for the entire dictation. §6 of the spec makes the level meter the capsule's defining feature, and the user gets no feedback that the microphone is actually picking anything up — which is exactly the thing they need to trust before speaking.

Intended fix: hold one long-lived `NSHostingView` whose root view takes `store` as an `@ObservedObject` and reads `store.capsule` and `store.audioLevel` directly. Drop the `state` and `level` parameters from `set`, leaving it responsible only for visibility and position. Rebuilding the hosting view per transition is wasted work regardless.

### Documentation drift, and a guard against it recurring

`README.md` documents a config key `duckVolumeFactor` with default `0.1` that does not exist in `VoxlyConfig`. The mute-and-fade silencer replaced the ducking behaviour and the table was never updated. Unknown keys are silently ignored on load, so a user who sets it gets no effect and no warning — the documentation invents a setting.

Every other drift the review found is already owned by another entry, which is where the wording should be fixed rather than in a separate documentation pass:

| Claim | Owning entry |
| --- | --- |
| README: Accessibility insertion with clipboard fallback | Text insertion is clipboard-only |
| README: audio deleted immediately after processing | Failed dictations keep their audio; quitting mid-recording leaks the WAV |
| README: `llama-cli` and `instruct.gguf` are "(Optional)" | Transcription-only installs cannot record |
| README: shortcut table mapping keys to modes | Default and newly created modes collide |
| README: Escape cancels a dictation | Remove Escape-to-cancel |
| Spec §5.5: Accessibility insertion, clipboard preserved on failure | Text insertion is clipboard-only; the clipboard restore can destroy the result |
| Spec §5.7: model download, verification, progress | There is no onboarding and no model download |
| Spec §6: capsule near the cursor | Align the spec with the capsule's actual placement |
| Spec §6: menubar status | The menubar icon never reflects state |
| Spec: nothing about system-output muting | Record output muting in the spec |
| Spec §1/§2: audience without a primary use case | The trailing space should be per mode |
| `AGENTS.md` broken links and mixed language | Smaller cleanups |

Intended fix here: delete the `duckVolumeFactor` row, and add a check that keeps the config table honest. A test that parses the key column of the README table and asserts each name decodes into `VoxlyConfig` would have caught this one, is a few lines, and turns a class of drift into a build failure. The same test can assert every key has a `_help` entry, which is the other thing nothing currently verifies.

## P2 — Latency spine

The path from keypress to inserted text. `LocalProcess.run` goes first because it is the root cause of three of the entries that follow.

### `LocalProcess.run` can deadlock, and busy-waits while waiting

Two defects in one function:

- It calls `process.waitUntilExit()` and only then reads both pipes with `readDataToEndOfFile`. A child that writes more than the pipe buffer, about 64 KB, blocks forever waiting for a reader — and so does Voxly. The engines run with quiet flags today, but the CLI fallbacks are exactly where verbose error output appears, so the deadlock is likeliest precisely when something is already wrong.
- The `timeout` path spins with `usleep(20_000)` on the calling thread, burning a thread for up to the full timeout.

Intended fix: read both pipes concurrently while the process runs, and replace the polling loop with `process.terminationHandler` bridged to a continuation. Making the function `async` at the same time removes most of the main-actor blocking described in the entries below at its source.

### The keypress path blocks the main actor on two AppleScript spawns

`begin()` runs on `@MainActor` and calls `recorder.start()`, which calls `silencer.prepare()`, which spawns two `osascript` processes before capture starts — one to read the current volume and mute state, one to mute. Each is allowed `volumeScriptTimeoutSeconds` (6.0). That work sits between the user pressing the shortcut and the microphone opening, with the whole UI frozen.

The irony is that `OutputHardware` already reads mute and volume through CoreAudio in microseconds, and its comments explain why AppleScript was removed from the watchdog path. The same argument applies to the write path.

Intended fix:

- Add `setMute` and `setVolumeScalar` to `OutputHardware` using `AudioObjectSetPropertyData`, and make CoreAudio the primary path for snapshot, mute and restore. Keep AppleScript as a fallback for devices that do not expose the properties.
- Run the fade in-process on a timer instead of inside a single `osascript` loop with `delay`, freeing the 400–600 ms it currently occupies on the silencer queue.
- This also removes an entire class of failure the existing comments document: a stuck `osascript` holding the audio restore back.

This is also the prerequisite for simplifying the silencer, since most of that state exists to defend against these calls being slow.

### Server startup blocks the main actor on `lsof` and `ps`

`reclaim` runs `lsof` and then one `ps` per returned PID through the synchronous `LocalProcess.run`, each with `serverReclaimTimeoutSeconds` (3.0), and it is called from `ModelServerManager.start()` inside a `Task { @MainActor in ... }`. Worst case that is several seconds of frozen UI at launch, before the window even draws.

Intended fix: run `start()` off the main actor — it touches no UI. Consider replacing the `lsof`-plus-`ps` probe with a PID file written at launch, which is both cheaper and unambiguous about which process Voxly actually owns.

### Capture retries sleep on the main actor

`AVEngineBackend.attemptStart` sleeps `retrySleepInvalidFormatSeconds` (0.3) or `retrySleepStartFailureSeconds` (0.4) between up to `engineStartRetries` (7) attempts, using `Thread.sleep`. It is reached synchronously from `begin()` on the main actor.

Observable effect: a Bluetooth device that needs the full retry budget freezes the entire app for two to three seconds, with no capsule, no spinner, and no way to tell whether the keypress registered.

Intended fix: make `AudioRecorder.start()` async, move the retry loop off the main actor with `Task.sleep`, and show a "Preparing microphone" capsule state while the device negotiates. This pairs with making `LocalProcess.run` async, since `prepare()` sits in the same call chain.

### Redundant `Task.detached` around already-async work

`process()` wraps `transcriber.transcribe` and `refiner.refine` in `Task.detached` and immediately awaits `.value`. Both are already `async` and spend their time in `URLSession`, so the detach adds a scheduling hop and buys nothing.

Intended fix: await them directly. The detach does matter for the CLI fallback paths, which are synchronous and blocking, so it belongs inside those functions rather than around the call site — or disappears entirely once `LocalProcess.run` is async.

### Audio is captured at device format instead of Whisper's format

`AVEngineBackend` installs its tap with the input node's own format — typically 48 kHz stereo Float32 — and writes that to disk. One minute is about 23 MB. The file is then read entirely into memory with `Data(contentsOf:)`, copied again into a multipart body, POSTed over loopback, and resampled by whisper anyway.

16 kHz mono Int16, which is what Whisper actually consumes, is about 1.9 MB for the same minute — roughly 12× less I/O and memory churn on every dictation, and a measurably shorter gap between releasing the key and the first token.

Intended fix:

- Convert in the tap, either with an `AVAudioConverter` or by installing the tap with an explicit 16 kHz mono format, and write that.
- Stream the multipart body from disk with `URLSession.uploadTask(with:fromFile:)` instead of building it in memory.
- `IOProcBackend` already writes 16-bit mono; this brings the two backends into agreement, which also simplifies the WAV writing code.

Prerequisite for streaming transcription, which would otherwise have to convert every chunk separately.

### The Bluetooth IOProc does file I/O inside the realtime callback

`processInput` runs in the audio device's realtime render thread and, on every callback, allocates an `[Int16]`, allocates a `Data`, calls `FileHandle.write` — a syscall — and dispatches a closure to the main queue for the level meter.

All three are realtime-unsafe. Under the load this app creates by design, with whisper and llama both resident, that invites dropouts in the recording itself, and the level-meter dispatch floods the main queue at callback rate.

Intended fix:

- Write into a preallocated lock-free ring buffer in the callback; do nothing else there.
- Drain the ring on a dedicated serial queue that owns the `FileHandle`.
- Accumulate peak level in the callback and publish it from a timer at about 30 Hz. Apply the same throttle to `AVEngineBackend`, which has the same dispatch-per-buffer pattern.

### The first dictation after launch never reaches the servers

`ModelServerManager.launchOwned` spawns the process and returns immediately. Nothing waits for `/health`. A dictation in the first several seconds after launch therefore gets an HTTP failure and falls back to the CLI, which loads the model from scratch, or fails outright.

Observable effect: the first dictation of a session is slow or broken, with no explanation. For a login-item menubar app that is the impression the product makes most often.

Intended fix: poll `/health` after launch with a bounded budget, publish a `serversReady` flag on the store, show a "Warming up" state in the menubar and in Diagnostics, and either queue the dictation until ready or refuse it with a clear message instead of silently degrading.

### History is a single UserDefaults blob, re-encoded on every dictation

`VoxlyStore.history` has `didSet { saveHistory() }`, and `saveHistory` re-encodes the entire array to JSON and writes it to `UserDefaults` on the main actor. There is no cap on how many entries accumulate.

`UserDefaults` is not intended for a growing blob. After a few thousand dictations, every dictation pays the cost of serializing all previous ones, on the main actor, at the moment the user is waiting for text to appear.

Intended fix: move history to a JSONL or SQLite file in the app support directory, append incrementally off the main actor, and cap it with a config key plus a "keep last N entries" control in the UI. Modes can stay in `UserDefaults` — there are at most four and they are tiny.

### Log writing allocates per call and never rotates

`VoxlyLog.log` allocates an `ISO8601DateFormatter` on every call, then opens, seeks to the end of, writes to and closes the file for each line. It is called from the silencer watchdog and from per-dictation hot paths. The file also grows without bound.

Intended fix: a static formatter, one long-lived `FileHandle` behind a serial queue, and size-based rotation — roughly 2 MB, keeping one previous file. What gets logged is the separate privacy entry in P0; this one is about how it is written and how large it grows.

## P3 — Usable by a non-developer

The batch that turns a personal tool into something another person can install and live with. The distribution decision comes first because it determines how several of the others are built.

### Establish Developer ID distribution for non-developer installs

Today Voxly can only be built from source. `package-app.sh` requires a local `Voxly Local Development` identity, the native engines and models must be placed in Application Support by hand, and `build-install.sh` removes the quarantine attribute after copying the app. A non-developer cannot perform any of those steps safely.

Decision: distribute Voxly directly through GitHub Releases, signed with Developer ID and notarized. The Mac App Store is not a target: the current design relies on child processes, global event monitors and Accessibility insertion, which do not fit the App Store sandbox. Direct distribution requires a paid Apple Developer Program account.

Intended fix:

- Enrol the release owner in the Apple Developer Program, create a Developer ID Application certificate, and create a named keychain profile for `xcrun notarytool`. Keep the certificate, notarization credentials and future Sparkle signing key out of the repository.
- Keep `scripts/package-app.sh` as the local-development path, including its existing identity and Accessibility behaviour. Put external-release signing and notarization in a separate `scripts/package-release.sh` path so ordinary iteration never needs paid-release credentials.
- Publish each externally usable build as a GitHub Release. The entries below define the bundled runtime, release artifact and update feed needed to make that channel usable.

### Bundle version-pinned engine helpers inside the signed app

Today Voxly discovers `whisper-cli`, `whisper-server`, `llama-cli` and `llama-server` only in `~/Library/Application Support/Voxly/Models/`. They are manually built or symlinked there, so the app bundle alone cannot transcribe or refine anything.

Observable effect: downloading a signed app would still leave a new user unable to run Voxly, while downloading executable code after notarization would make Gatekeeper and integrity handling part of first-run setup.

Decision: ship the version-pinned arm64/Metal engine executables inside `Voxly.app/Contents/Library/Helpers`, and sign every bundled Mach-O as part of the Developer ID release. The mutable Whisper and refinement model files remain in Application Support and are downloaded as data during onboarding; Voxly does not download or execute engine binaries at runtime.

Intended fix:

- Define the exact `whisper.cpp` and `llama.cpp` revisions, build settings and expected binary hashes used for a release, then copy the two server binaries and their CLI fallbacks into the bundle.
- Update model and process lookup so a release finds the bundled helpers while development builds can retain the current local layout.
- Include the applicable engine and model licences, notices and versions in the release material. Treat an engine revision change as an app release, not as an opaque background download.

### There is no onboarding and no model download

§5.7 of the spec requires a first-run explanation, inline permission requests, a download with verification, and progress, size, completion and failure states. None of it exists. On first launch the app opens its settings window, Diagnostics shows three red rows, and "Open folder" reveals an empty directory. The user is expected to build whisper.cpp and llama.cpp themselves and place four artifacts with exact names.

This is the largest gap between the spec and the build, and it is what limits the product to its author.

Intended fix:

- A first-run flow that explains local-only processing and requests Microphone and Accessibility inline, with the status updating as they are granted.
- Model download from a pinned URL with SHA-256 verification, a progress bar, required space shown up front, and a resumable or at least clearly recoverable failure state.
- The engine helpers ship in the signed bundle, as decided above; only model data is downloaded at first run. Do not link the engines into SwiftPM or download executable code at runtime for this release channel.

### The bundle version is hardcoded, so every build reports the same one

`Info.plist` pins `CFBundleShortVersionString` to `0.1.0` and `CFBundleVersion` to `1`, and neither script touches them. Every build ever produced identifies itself identically, so "which build are you running?" is unanswerable — already awkward with two users, and fatal once anyone reports a bug against a binary they did not compile.

Intended fix: stamp both values at package time. The short version comes from a single source of truth — a git tag, or a `VERSION` file the tag is cut from — and `CFBundleVersion` from something monotonic such as the commit count. Show the resolved version in Diagnostics so a user can read it back without inspecting the bundle, and log it at launch so `voxly.log` says which build produced it.

Prerequisite for any update mechanism, which cannot compare versions that never change.

### Package a hardened, notarized release build

Today `scripts/package-app.sh` builds the debug executable and ad-hoc-signs only the outer app bundle with a local development identity. There is no hardened runtime, no signing order for nested helper executables, and no notarization submission.

Observable effect: even after a Developer ID certificate exists, a build that includes the engine helpers, future Sparkle frameworks or other nested Mach-O code could fail Gatekeeper or launch with a signature that does not cover its executable parts.

Intended fix:

- Add `scripts/package-release.sh`, dependent on the P0 release build and the version-stamping entry above. It creates a clean release bundle, signs nested helpers and frameworks from the inside out with the Developer ID identity and `--options runtime`, then signs the outer app last.
- Have the release script create the notarization submission accepted by `notarytool`, wait for the result, staple the resulting ticket to the app and final distribution artifact, and fail closed on any rejection. Verify the completed result with `codesign`, `spctl` and `stapler validate` before it can be published.
- Start with only the hardened-runtime entitlement requirements proven necessary by the bundled code. Any exception must be explicit, documented and covered by a release smoke test rather than added speculatively.

### Publish a signed, notarized DMG through GitHub Releases

Today there is no artifact a user can download: the only delivery flow runs `build-install.sh` locally and removes quarantine after copying the app.

Observable effect: an external tester would receive either source code or an unsigned archive, then need a toolchain or unsafe Gatekeeper-bypass instructions before Voxly can launch.

Decision: the public first-install artifact is a signed, notarized DMG containing `Voxly.app` and the standard Applications-folder install path. A ZIP is not the primary download; it is produced separately only as Sparkle's update payload.

Intended fix:

- Build the DMG from the stapled release app, attach it to the matching GitHub Release, and publish a SHA-256 checksum and concise release notes with the stamped version.
- Test a fresh download in a clean macOS account: mount, install, open and grant permissions without `xattr`, a terminal command or a developer toolchain.
- Keep model setup in the app's first-run flow, not in DMG installation instructions, so updating or reinstalling the app does not require rebuilding native engines or manually moving model files.

### Keep direct installs current with Sparkle

Today an app distributed outside the Mac App Store has no update path. A user can remain on a known-broken build indefinitely, and a support request cannot be tied reliably to a newer fixed version.

Decision: use Sparkle rather than a hand-rolled GitHub API check. It is the established signed-update mechanism for direct-distributed macOS apps and handles download, verification, replacement and restart without asking users to install a new DMG for every release.

Intended fix:

- Add Sparkle only after version stamping and hardened release packaging work. Configure its public EdDSA key and an appcast served from a stable GitHub-hosted location; keep the private signing key in release-only credential storage.
- Generate a signed ZIP of the notarized app for each release, publish it as the appcast enclosure, and keep the DMG as the human-facing first-install download.
- Expose the standard update check in the app's existing control surface, test an upgrade from a previous signed build, and verify that Application Support models, history and settings survive the replacement unchanged.

### Bundle metadata says Portuguese while the product is English

`CFBundleDevelopmentRegion` is `pt_BR` and `NSMicrophoneUsageDescription` is written in Portuguese, while the entire interface is English.

Decision: English is the product language, because the project is meant to be global. Portuguese is not an interface requirement — but it must work as well as English for transcription and refinement, which is a quality requirement, not a localization one.

Intended fix:

- Set `CFBundleDevelopmentRegion` to `en`.
- Rewrite `NSMicrophoneUsageDescription` in English. The current string also hardcodes "Command direito", which is wrong for any mode whose shortcut the user changed; phrase it in terms of holding the dictation shortcut.
- Do not localize the interface. Record that decision in the spec so it is not revisited by accident.
- Keep Portuguese parity as an explicit requirement, which is what the language-detection and Portuguese assistant-response entries in P1 are for.

### The app takes a Dock icon and opens a window at launch

`Info.plist` has no `LSUIElement`, and the SwiftUI `WindowGroup` means a settings window opens on every launch. For a push-to-talk menubar tool that is an unwanted entry in ⌘-Tab and an unwanted window at every login.

Intended fix: set `LSUIElement` to `true`, and open the main window only through the popover's "Open Voxly", which already calls `openWindow` and activates the app. Verify that permission prompts still present correctly as an accessory app.

### No way to pause Voxly, and no launch at login

If a mode's modifier conflicts with whatever the user is doing, the only remedies are quitting Voxly or editing the mode. And a menubar utility that has to be launched by hand after every reboot does not survive contact with daily use.

Intended fix: a "Pause dictation" toggle in the popover that stops the event monitors and is reflected in the menubar icon, and `SMAppService.mainApp.register()` behind a "Launch at login" checkbox, with the checkbox reading its state back from the service rather than from a local default.

### Permission status goes stale

`refreshStatus()` runs at `start()` and when the user clicks "Check permissions". Accessibility is granted in System Settings, outside the app, so the normal sequence is: click Allow, grant it, return to Voxly, and find it still reporting the permission as missing until the user happens to find the button. `begin()` refuses to record in the meantime.

Intended fix: poll `AXIsProcessTrusted()` on a low-frequency timer while any permission is missing, and refresh on `NSApplication.didBecomeActiveNotification`. Stop polling once everything is granted. Apply the same treatment to the microphone check.

### The menubar icon never reflects state

The status item's image is set once and never changes. §6 of the spec assigns the `Ready` state's feedback to the menubar — "discrete icon and active mode in the menubar" — and the capsule is not visible when idle, so there is currently no indication anywhere that Voxly is running and armed, or that it is busy.

Intended fix: tint or swap the icon for recording, processing and error states, and show the active or last-used mode name in the popover.

### The mode editor loses unsaved edits silently

`ModesView` holds a `draft`. Selecting a different mode overwrites it, and switching sidebar sections discards it, with no indication that anything was lost. There is no ⌘S. `error` also doubles as the success channel — `save()` sets `error = "Saved"` and the view colours it green by comparing the string — so "Saved" stays on screen indefinitely and success is encoded as an error value.

Intended fix:

- Autosave on field change, which is how macOS settings behave and removes the problem rather than reporting it. Keep validation — an empty name still must not be accepted.
- If an explicit save is preferred instead, show a dirty indicator and confirm before navigating away, and add ⌘S.
- Either way, split the single `error` string into a validation error and a transient confirmation with its own timestamp, so the two cannot be confused by a string comparison.

### Configuration requires editing JSON and restarting

`AppConfig.current` is a `let` loaded once at launch. Every setting — including the whisper model file, the global vocabulary, and minimum tap time — requires opening a text editor and relaunching the app. The self-documenting `_help` block is a good touch for the low-level knobs, but the ones users actually want to change should not live there.

Intended fix: a Settings section for the handful of user-facing keys — model file, `whisperPrompt`, `minTapSeconds`, history cap — leaving the rest in `config.json` as escape hatches. Reload on change for values that allow it, and say plainly in the UI which ones need a restart. Note that output muting is deliberately not among them: it has no toggle, by decision.

### Undo last insertion from the menubar popover

Pasting into the wrong field is the most common failure of any dictation tool, and Voxly currently offers no way back: the clipboard may already have been restored, and the user has to select and delete the text by hand.

Decision: put a short-lived "Undo last insertion" action at the top of the existing menubar popover. The popover is Voxly's persistent control surface and is discoverable without adding a global shortcut. The capsule remains fixed at the bottom centre and non-interactive; a keyboard-only command and a transient notification are not the undo affordance.

Intended fix:

- Enable the menubar action for five seconds after a successful insertion, show its remaining availability clearly, and disable or remove it once the window expires. Do not offer it for copied or failed results.
- Retain an immutable undo record containing the inserted text, target and insertion time. Invoking the popover must not activate Voxly or retarget the operation; apply the change to the captured target and return the removed text to the clipboard.
- Before deleting anything, verify that the same target is still eligible and that the text at the expected insertion location still matches Voxly's result. Never send a blind Delete or Command-Z event: if validation fails, make undo unavailable and leave the user's later typing untouched.

This remains a safety net for the clipboard insertion path and restore race; it does not replace honest insertion reporting, clipboard repair or the later Accessibility insertion path.

### Document the privacy costs the implementation actually has

The privacy posture is strong — loopback-only servers, no telemetry, no network calls after install — but the documentation states it in absolutes that the implementation does not meet, which is worse than stating it with the caveats.

Two facts are currently undocumented:

- While insertion goes through the clipboard, the dictated text sits on the system clipboard for `clipboardRestoreDelaySeconds` (0.65 by default) and is readable by any process on the machine during that window. When the paste fails the text is not cleared at all. This is the unavoidable cost of the ⌘V approach and another reason the Accessibility path matters.
- `whisper-server` and `llama-server` accept unauthenticated requests from any local process. They are bound to `127.0.0.1`, so nothing off the machine can reach them, but while Voxly runs, any other program on the same Mac can have audio transcribed or arbitrary prompts answered by them.

Intended fix: state both in `README.md`, and in the privacy section of `PRODUCT_SPEC.md`, as characteristics rather than warnings. Revisit the clipboard line once the Accessibility insertion path lands, since it stops applying to the common case. Audit the rest of the privacy claims in the same pass — the "audio buffers are deleted immediately after processing" sentence is contradicted by two separate code paths that have their own entries in P0.

### Align the spec with the capsule's actual placement

Decision: the capsule's current behaviour is intentional and stays as it is — fixed at bottom centre of the screen containing the pointer, and non-interactive (`ignoresMouseEvents = true`). Bottom centre never occludes the text field being dictated into, which is worth more than proximity to the cursor.

The documentation does not match, so the documentation changes:

- `PRODUCT_SPEC.md` §4 step 3 says "The floating capsule near the cursor shows the audio level". Replace with placement at the bottom centre of the active screen.
- §6 Surfaces says the capsule "accompanies the recording without stealing focus". The second half is accurate — the panel is non-activating. Reword the first half so it does not imply the capsule follows the cursor.
- State explicitly that the capsule is non-interactive, so it is clear that no click, stop or cancel affordance is intended there.

Documentation only, so it can ship with any other change that touches the spec.

## P4 — Foundations

Refactors that make the rest cheaper. Nothing here is user-visible, and the order is a real dependency chain.

### `Services.swift` holds eleven unrelated concerns in one file

Logging, errors, permissions, CoreAudio device queries, AppleScript volume control, the output silencer, two capture backends, WAV writing, transcription, refinement, process spawning and text insertion all live in a single 1,506-line file. Each is independently testable and none is isolated, so nothing in the audio or insertion path can be exercised without the whole app.

Intended fix: split along the seams that already exist, with no behaviour change — `Log.swift`, `Permissions.swift`, `AudioDevices.swift`, `OutputSilencer.swift`, `Capture/{AVEngineBackend,IOProcBackend,WAVWriter}.swift`, `Transcriber.swift`, `Refiner.swift`, `Process.swift`, `TextInserter.swift`.

This is the prerequisite for the test coverage entry, and it makes the silencer simplification reviewable.

### Test coverage is thinnest where the code is hardest

Two test files, 96 lines, covering `mergedPrompt`, `looksLikeAssistantResponse`, `changesLanguage` and one Codable migration. The silencer state machine, the coordinator's superseded and cancelled logic, WAV header writing and shortcut resolution have none.

Sequencing: this comes after the `Services.swift` split, because writing tests against the current shapes means writing them twice. The exception is the silencer decision table, which must be pinned down *before* the silencer is simplified.

Highest-value additions, in order:

1. `DictationCoordinator` state transitions — begin, finish, cancel, supersede — with `AudioRecorder`, `TextInserter` and the transcriber behind protocols. Several of the P0 correctness entries live here and become trivially testable once the dependencies are injectable.
2. `IOProcBackend`'s WAV header and patch logic against a known-good byte layout. The comment recording an off-by-two in the header is exactly the class of bug a byte-level test catches instantly.
3. The silencer's decision table — bluetooth × rateLeftBaseline × userOverride × deviceChanged mapped to the chosen completion path — with CoreAudio behind a protocol.

### Record output muting in the spec, then simplify the silencer

`RecordingOutputSilencer` is about 550 lines with 15 pieces of mutable state, two locks, three CoreAudio listeners, a watchdog timer, an adoption protocol and five completion paths. Every branch is justified by a real bug, but the behaviour it implements appears nowhere in `PRODUCT_SPEC.md`, so the most complex machine in the codebase has no stated requirement behind it.

Decision: muting system output while recording is a core behaviour, on by default, not opt-in. It is what every comparable dictation tool does, and it is the standard behaviour for an app capturing audio while something else is playing on the same device. There is no config key and no toggle.

A narrowing to "only when input and output are the same Bluetooth device" is also rejected, and would be backwards: a Bluetooth headset is the case with the least echo risk, since the output is in the user's ears. Built-in mic with speakers playing is the case that most needs muting.

Intended fix, in this order:

- Add the behaviour to the spec: output is silenced for the duration of capture and restored afterwards, always, and the restore must survive app termination. State the Bluetooth A2DP/HFP constraint that makes the restore delayed rather than immediate, since that delay is otherwise indistinguishable from a bug. This half is documentation only and can ship immediately.
- Then simplify, after the CoreAudio change in P2 has landed. Most of the state exists to work around slow and flaky `osascript` calls; moving volume and mute control to CoreAudio collapses the timing windows those branches defend against. Re-measure how many of the five completion paths are still reachable before rewriting anything.
- Pin the decision table down with tests before touching it, because the branches encode bugs that are expensive to rediscover.

### Config boilerplate is written five times per key

Every key in `VoxlyConfig` appears as a property, a `decodeIfPresent`, an `encode`, a `CodingKeys` case and a `help` entry: 200 lines for 31 settings. Adding one setting means five edits, and the compiler checks none of them, so a key silently fails to load or fails to appear in the generated file.

Intended fix: a property wrapper carrying the default and the help string, with synthesized `Codable`, collapsing each key to one line. Alternative, since the file is regenerated on every launch anyway: decode into a dictionary and read through a defaulting accessor.

Whichever is chosen, the `_help` block and the tolerant defaulting behaviour must survive — a partial or deleted `config.json` still has to start cleanly. Doing this before the settings UI makes that work smaller.

### Smaller cleanups

- The local event monitor's return value is discarded and never removed, so the monitor cannot be torn down.
- `handleRunningEvent()` is empty; the `runningAddress` CoreAudio listener is installed and does nothing. Either use it or stop installing it.
- `OutputVolume.level()` has no callers and is dead. `isMuted()` is still used as a fallback when the hardware read fails, so it stays.
- `AGENTS.md` links point at `/Users/ivanseibel/dev/personal/voxly`, which is not this checkout's path, so every link in it is broken. Make them repo-relative. Two of its file descriptions are also part Portuguese while the file is English.
- Most of `ContentView.swift` is single-line view declarations 200–400 characters wide. Consistent, so it is a style choice, but it makes diffs unreadable and line-level review impractical.

## P5 — Bets

Features that change what the product is, rather than fixing what it claims to be. Worth doing once the sections above are done, or when one of them turns out to matter more than expected.

### Per-app mode selection, as an opt-in

Today the mode is always decided by which modifier the user holds, so the user carries the "which key do I hold here?" decision on every dictation. `captureTarget()` already resolves the frontmost application, so Voxly could pick the mode from the app instead.

Decision: this must be configurable, not a behaviour change. Users who like choosing by shortcut keep exactly what they have today.

Intended fix:

- A config flag, default off, that enables app-based mode selection.
- An optional list of bundle IDs per mode, edited in the mode editor.
- With the flag on, `begin()` matches the frontmost bundle ID against those lists; on a match that mode is used, and with no match it falls back to the mode bound to the pressed shortcut. With the flag off, the pressed shortcut decides, as now.
- Open question to settle when building: whether holding a shortcut other than the default should override a matching app rule, or whether the rule always wins while the flag is on. Overriding is more predictable; always-wins is simpler to explain.

Both paths must show which mode was chosen — the capsule already has room for the mode name, and without it app-based selection is invisible and impossible to trust.

### Text replacements and spoken commands

Whisper's initial prompt biases recognition, but it cannot fix the misses that survive it: a term the model consistently spells wrong, or spoken punctuation and line breaks that have no textual equivalent.

Intended fix: a user-editable replacement list applied to the transcript after transcription and before refinement — literal pairs such as `kubernetes` → `Kubernetes`, plus spoken commands such as "nova linha" → newline and "ponto" → `.`. Per mode, so a chat mode and a notes mode can differ, with a global list every mode inherits, mirroring how vocabulary already works.

Case sensitivity and word-boundary matching need to be explicit in the UI, since a naive substring replace on a short term corrupts longer words that contain it.

### Streaming or chunked transcription

Nothing starts until the key is released, so the wait after a 45-second dictation is the full transcription of 45 seconds of audio. Perceived latency grows linearly with how much the user said, which punishes exactly the long dictations the product is best at.

Intended fix: transcribe 5–10 second chunks as they arrive and show the partial text in the capsule, so the visible wait after release is one chunk instead of the whole recording.

The hard parts are chunk boundaries — cutting mid-word costs accuracy — and prompt continuity, since each chunk should be primed with the tail of the previous transcript on top of the mode vocabulary. Refinement still needs the complete text, so the streaming preview and the final inserted text are two different things and the capsule has to make that legible.

Depends on the 16 kHz mono capture change in P2; chunking a device-format stream means converting each chunk separately.

### Per-mode model selection, pending a viability check

`modelProfile` exists on `DictationMode` and is persisted, but nothing reads it — the model is a single global, `whisperModelFile`. A per-mode choice would let a fast mode stay instant while a careful mode uses a larger model. The property itself is removed by the dead-settings entry in P1; this entry is about whether the feature is worth reintroducing with a real type.

This is worth doing only if one of the approaches is actually cheap, so measure before building. The options, and what has to be measured:

- Two whisper servers on two ports, one per profile. Instant switching, but both models stay resident: roughly 500 MB for `ggml-small` plus around 1.5 GB for a quantised large-v3-turbo, alongside the llama model. Measure real resident memory and whether Metal contention slows either server down when both are loaded.
- Restart the whisper server on profile change. No extra memory, but `whisper-server` loads one model per process and cannot swap at runtime, so every switch pays a full model load. Measure that load time for the large model — if it is seconds, switching mid-conversation is unusable.
- Keep one server and vary only the decoding parameters per mode — beam size, best-of, temperature. Nearly free, since those are already sent per request, and it captures part of the speed-versus-accuracy trade-off without a second model. This is the fallback if neither approach above measures well.

Whichever wins, the replacement field is an enum of available models, not a free-text string.

### History is read-only

`HistoryView` can search and delete, and nothing else. `rawText` is stored on every entry and never displayed, so §5.2's requirement to keep the raw text "for audit" has no interface. For a dictation tool, "the paste went into the wrong window, let me get that text back" is a routine need with no answer today.

Intended fix:

- Per-row Copy for the final text, and Copy for the raw text.
- "Insert again", reusing `TextInserter` against the current focus.
- Expand a row to full text, with raw and final shown together — which is also the fastest way for a user to judge whether a mode's instructions are helping or hurting.
- Group by day, since entries are timestamped and currently render as a flat list.

### The trailing space should be per mode

`process()` inserts `final + " "` unconditionally.

The primary use case is dictating into chat: prompts for coding agents, and messages to colleagues. A trailing space is right there, and it is right for successive dictations that build up a message. So the default stays as it is.

It is wrong for the minority of modes that produce standalone text — technical notes, or anything ending a paragraph — where it accumulates invisible trailing whitespace.

Intended fix: a per-mode option, defaulting to on. Not urgent, since the default serves the main use case. Once the Accessibility insertion path can read the character before the cursor, inferring it is a better answer than either a constant or a toggle.

Related: `PRODUCT_SPEC.md` §1 and §2 describe the audience as people writing "in work, communication, and development apps" without ranking them. Chat with agents and colleagues is the primary target and code or technical notes are secondary, which is not derivable from the code and should be stated in the spec so future decisions like this one have something to appeal to.

### Dark mode is forced with a hardcoded palette

`ContentView` applies `.preferredColorScheme(.dark)` and `VoxlyColor` hardcodes every surface. The graphite-and-black visual language is called for by §6 of the spec, so the dark identity is deliberate — but ignoring the system setting is a separate choice from having a dark palette, and hardcoded colours also mean the capsule cannot respond to accessibility settings.

Intended fix: keep the dark identity if that is the intent, but move the palette into an asset catalog so it has light variants and can be adjusted in one place, and honour `accessibilityDisplayShouldIncreaseContrast` and `accessibilityDisplayShouldReduceTransparency` in the capsule.

## How to use this file

This file tracks only open work: bugs still to fix, features still to build, decisions still to make. Finished work is not recorded here — the git history is the record of what was done, and design rationale that stays relevant lives in comments next to the code it explains.

Add an entry as a `###` section inside the priority section it belongs to, describing the current behaviour, the observable effects, and the intended fix. Reprioritising means moving the entry to another section. Remove the entry once it ships.

Write paragraphs as single lines and let the editor wrap them; do not hard-wrap prose.
