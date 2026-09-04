# Voxly — main window redesign

Written on 2026-08-28. Scope: the `Voxly` main window (`ContentView.swift`) — its layout, density, palette, and hit targets. The floating capsule and the menubar popover are out of scope except where they share the palette.

This report diagnoses three complaints about the current window — it wastes vertical space, the dark palette is too dark, and clicks only register on the text itself — measures each one against the current code, and specifies a replacement design that follows macOS conventions. Every recommendation names the code it replaces.

## 1. What the window is today

`ContentView` is a hand-built three-pane layout inside a single `HStack`:

| Pane | Width | Source |
| --- | --- | --- |
| Navigation sidebar (Modes / History / Diagnostics) | 190 pt fixed | `ContentView.body`, `.frame(width: 190)` |
| Mode list | 300 pt fixed | `ModesView`, `.frame(width: 300)` |
| Mode editor | remainder | `ModeEditor` |

The window is `.frame(minWidth: 820, minHeight: 560)` with `.defaultSize(width: 860, height: 620)` and `.windowResizability(.contentSize)`. Colour comes from a single `VoxlyColor` enum of eight hardcoded values, and `.preferredColorScheme(.dark)` pins the appearance regardless of the system setting.

Nothing here uses `NavigationSplitView`, `List`, `Form`, `Table`, `.toolbar`, or `.navigationTitle`. Every affordance — selection, sidebar rows, field labels, cards, the title bar — is drawn by hand. That is the root cause of all three complaints: the window reimplements controls that macOS already provides, and loses their behaviour in the process.

## 2. Complaint one — vertical space

### Measurement

The editor column stacks a micro-label above every control (`Field`), which costs a label line plus 7 pt of spacing per field, and uses 22 pt between blocks and 30 pt of outer padding. Measured from the code:

| Block | Height | Where |
| --- | --- | --- |
| Outer padding (top + bottom) | 60 | `ModeEditor`, `.padding(30)` |
| "Edit mode" title | 22 | duplicates the pane's purpose |
| Name — label + 7 + field (17 + 20 padding) | 56 | `Field` |
| Shortcut + Language row | 56 | `Field` + `ShortcutRecorder` |
| Local instructions — label + editor (145 + 16) | 180 | `.frame(minHeight: 145)` |
| Vocabulary — label + editor (72 + 16) + help caption | 135 | `.frame(minHeight: 72)` |
| Output card | 62 | `.padding(12)` on a two-line row |
| Save row | 28 | |
| Inter-block spacing (6 × 22) | 132 | `VStack(spacing: 22)` |
| **Total** | **≈ 731** | |

The content area is `620 − ~28` (title bar) `− ~55` (the hand-built `Header`) `≈ 537 pt`. The editor needs 731 pt, so roughly 195 pt — 27% of the form — is below the fold, and the two `TextEditor`s scroll internally on top of that. The screenshot shows exactly this: scrollbars inside both text areas in a window that is not full.

Three separate things burn the height:

- **Stacked labels.** `Field` puts an uppercased 10 pt label above the control. That is a web and iOS pattern. macOS forms put the label to the left of the control (`LabeledContent`, or a `Form` with `.formStyle(.grouped)`), which turns a 56 pt block into a 28 pt row. Three fields × 28 pt saved = 84 pt.
- **A hand-built title bar.** `Header` renders "Voxly" plus `store.lastMessage` in 55 pt of chrome, directly under the real title bar, and repeats the brand already shown by `BrandMark` in the sidebar. The window says "Voxly" three times.
- **Card padding used as spacing.** The Output row wraps a two-line label in a 12 pt-padded rounded rectangle for a control that is a single toggle. In a grouped `Form` it is one 28 pt row.

### Target

| Block | Proposed height |
| --- | --- |
| Outer padding | 40 |
| Group "Mode": Name / Shortcut / Language / Output | 4 × 28 + 2 group chrome = 136 |
| Group "Instructions": editor | 20 header + 110 = 130 |
| Group "Vocabulary": editor + footnote | 20 header + 64 + 28 = 112 |
| Footer (validation + Save) | 32 |
| Group spacing (3 × 16) | 48 |
| **Total** | **≈ 498** |

498 pt fits a 540 pt content area with no scrolling, and both text editors grow when the window is resized rather than scrolling inside a fixed box. `.windowResizability(.contentSize)` must become `.contentMinSize` for that to work — today the modifier ties the window's resize range to the content's ideal size, so the user cannot trade window height for editor height.

## 3. Complaint two — the palette is too dark

### Measurement

The four surface tokens, converted to hex and to WCAG relative luminance:

| Token | Value | Hex | Relative luminance |
| --- | --- | --- | --- |
| `inset` (text fields) | `black.opacity(0.24)` over `base` | `#0B0C0D` | 0.0035 |
| `base` (content) | `Color(red: 0.055, green: 0.06, blue: 0.065)` | `#0E0F11` | 0.0048 |
| `canvas` (sidebars) | `Color(red: 0.075, green: 0.08, blue: 0.085)` | `#131416` | 0.0071 |
| `raised` (cards) | `Color(red: 0.10, green: 0.105, blue: 0.11)` | `#1A1B1C` | 0.0107 |

Contrast ratios between adjacent surfaces:

| Pair | Ratio |
| --- | --- |
| `canvas` : `base` | 1.04 : 1 |
| `raised` : `base` | 1.11 : 1 |
| `base` : `inset` | 1.02 : 1 |

For comparison, macOS dark mode's own step from `windowBackgroundColor` (`#323232`) to `textBackgroundColor` (`#1E1E1E`) is 1.30 : 1.

So the problem is not text legibility — `muted` (`white.opacity(0.48)`) over `base` measures 5.00 : 1 and passes AA. The problem is that the app has four surface levels that are within 11% of each other and of black. The panes, the cards, and the text fields are all effectively the same colour, so none of the depth the design intends is visible; the only thing separating regions is a hairline at `white.opacity(0.10)`. The window reads as one flat black field with outlines drawn on it, which is why "the dark is too dark" and why the text fields do not read as controls.

Note that dark mode text fields being *darker* than the window is correct on macOS — `textBackgroundColor` is darker than `windowBackgroundColor`. The mistake is not the direction of the step, it is that `base` is already so close to black that there is no room below it for the step to be seen.

### Target

Replace the hardcoded enum with the system's semantic colours plus one brand accent. This is the recommendation with the highest ratio of effect to effort: it fixes the surface hierarchy, gets Increase Contrast and Reduce Transparency support for free, and gives a light appearance at no cost if that is ever wanted.

| Current | Replacement | Effective dark value |
| --- | --- | --- |
| `VoxlyColor.base` | `Color(nsColor: .windowBackgroundColor)` | `#323232` |
| `VoxlyColor.canvas` | sidebar vibrancy from `NavigationSplitView` (or `.ultraThinMaterial`) | material |
| `VoxlyColor.raised` | `Color(nsColor: .controlBackgroundColor)` | `#1E1E1E` |
| `VoxlyColor.inset` | `Color(nsColor: .textBackgroundColor)`, or let `Form` supply row backgrounds | `#1E1E1E` |
| `VoxlyColor.line` / `softLine` | `Color(nsColor: .separatorColor)` | system |
| `VoxlyColor.ink` | `.primary` | `labelColor` |
| `VoxlyColor.muted` | `.secondary` | `secondaryLabelColor` |

Keep exactly one brand colour, the green already used by `BrandMark` and the ready indicator, and stop using green as a button tint (`Button("Save mode").tint(.green)`). On macOS the default button takes the user's accent colour; overriding it with green makes Voxly's primary action look like a status pill and collides with the green "Ready" dot 400 pt away. Use `.buttonStyle(.borderedProminent)` with no tint and `.keyboardShortcut(.defaultAction)`.

Keep `.preferredColorScheme(.dark)` on the capsule only. The capsule is a HUD floating over other apps, where near-black and a fixed appearance are the right call and §6 of the spec asks for it. The settings window is not a HUD, and forcing dark there is a separate decision from having a dark identity. This absorbs the former P5 backlog entry on the hardcoded palette.

## 4. Complaint three — clicks must land on the text

### Cause

This one is a concrete bug, not a matter of taste. `NavButton` draws its selection background with:

```swift
.background(selected ? Color.white.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 7))
```

Two things follow. First, `.background` never contributes to hit testing — the button's interactive region is its label's content shape, not the shape drawn behind it. Second, `Color.clear` is not hit-tested at all, so on an unselected row there is nothing under the padding or under the `Spacer()` to receive the click. The result is that only the glyph boxes of the `Text` views are clickable: the sidebar rows, and every mode row in `ModesView`, respond only when the pointer is on the letters. The selected row appears to work better purely because the 10% white fill happens to sit where the text already is.

The same omission affects the icon-only buttons. `Button { deleteMode(mode) } label: { Image(systemName: "trash") }` with `.buttonStyle(.plain)` gives a hit area the size of the glyph — roughly 13 × 13 pt — well under any usable target, and with no `accessibilityLabel`, so VoiceOver announces it as an unlabelled button. `HistoryRow`'s delete button has the same two problems.

### Fix

The tactical fix is one line per style: add `.contentShape(RoundedRectangle(cornerRadius: 7))` inside `makeBody` after the padding, and give icon buttons an explicit `.frame(width: 24, height: 24).contentShape(.rect)` plus an `accessibilityLabel`.

The structural fix is to stop hand-rolling the rows. A native `List` with a `selection` binding gives, for free and correctly: full-row hit areas, hover highlight, the system selection fill that follows the accent colour and the window's active state, keyboard navigation with arrow keys, focus ring, type-select, context menus, and drag reorder. Every one of those is missing today. `ModesView`'s row loop and both custom `NavButton` call sites should become:

```swift
List(selection: $selectedID) {
    ForEach(store.modes) { mode in
        ModeRow(mode: mode).tag(mode.id)
    }
}
.contextMenu(forSelectionType: UUID.self) { ids in
    Button("Delete", role: .destructive) { ... }
}
```

and the per-row trash button should go away in favour of the macOS convention for editable lists — a `+` / `−` bar on the list's bottom edge, as in System Settings ▸ Users & Groups or Login Items — plus the context menu and the Delete key. That also removes the visual noise of a trash can on every row and the `.opacity(0.3)` disabled state that currently hints the row is dimmed rather than the button.

## 5. Proposed structure

Two panes, not three. The mode list does not need to be a permanent column: Modes is one of three sections, and the list holds at most four items (`store.modes.count >= 4` gates creation). A sidebar for the sections plus a detail pane, with the mode list as a compact `List` above the editor or as an `.inspector`, both frees ~120 pt of width and removes a nesting level.

Recommended: `NavigationSplitView` with a sidebar and a detail, and the Modes detail as a list-over-form split.

```
┌──────────────────────────────────────────────────────────────────────┐
│ ● ● ●   Modes                                        [ + ]  [ ⓘ ]    │  ← real title bar + toolbar
├────────────────────┬─────────────────────────────────────────────────┤
│ ▾ Voxly            │  Clean text            Automatic      ⌘ Right   │  ← native List, full-row
│   ◧ Modes          │  Literal               Automatic      ⌥ Right   │     hit area, selection,
│   ◷ History        │  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄  │     keyboard nav
│   ✚ Diagnostics    │  [ + ] [ − ]                                    │  ← macOS editable-list bar
│                    ├─────────────────────────────────────────────────┤
│                    │  Mode                                           │
│                    │    Name          [ Clean text              ]    │  ← LabeledContent rows,
│                    │    Shortcut      [ ⌘ Right          Record ]    │     label left of control
│                    │    Language      [ Automatic            ⌄  ]    │
│                    │    Output        Insert, clipboard fallback ( )│
│                    │                                                 │
│                    │  Instructions                                   │
│                    │    ┌───────────────────────────────────────┐    │  ← grows with the window
│                    │    │ Rewrite more concisely…                │    │
│                    │    └───────────────────────────────────────┘    │
│                    │                                                 │
│                    │  Vocabulary                                     │
│                    │    ┌───────────────────────────────────────┐    │
│                    │    │ ticket, Jira, Voxly, sprint…           │    │
│                    │    └───────────────────────────────────────┘    │
│                    │    Names and jargon this mode should get right.  │
│ ● Ready            │                                                 │
│   All local        │                                    [ Save ]     │
└────────────────────┴─────────────────────────────────────────────────┘
```

Specifics:

- **Title and status move to the chrome.** Delete `Header`. Use `.navigationTitle(section.rawValue)` so the window's real title bar carries the section name, and put `store.lastMessage` in a `.toolbar` item — or, better, drop it from this window entirely, since the capsule already reports the last result and the sidebar footer already reports readiness. Reclaims ~55 pt.
- **The editor becomes a `Form`.** `Form { Section("Mode") { LabeledContent … } }` with `.formStyle(.grouped)` supplies row backgrounds, separators, label alignment, and section headers, replacing `Field`, the four `RoundedRectangle` overlays, and the Output card. Delete `Field` and the manual `.background(VoxlyColor.inset, in:)` / `.overlay(…stroke…)` pairs — there are six copies of that idiom in the file.
- **Uppercase labels go.** macOS form labels are sentence case, right-aligned, and to the left of the control. `Text(label.uppercased()).tracking(0.8)` is not a macOS idiom.
- **Text editors get flexible height.** `.frame(minHeight: 110)` for instructions and `minHeight: 64` for vocabulary, both without a fixed maximum, so window height translates into editor height.
- **`+` moves to the toolbar and the list's bottom bar**, disabled at four modes with a `.help("Voxly supports up to four modes")` tooltip explaining why, instead of the current bare `.opacity(0.3)`.
- **Rename `ContentView.Section`.** The enum shadows `SwiftUI.Section` inside `ContentView`'s scope, which blocks using `Section` in a `Form` there. Rename to `Pane`.

## 6. Density spec

Numbers to apply consistently, chosen to match the macOS system settings metrics rather than invented:

| Element | Value |
| --- | --- |
| Sidebar width | 200 pt, resizable (`.navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)`) |
| Sidebar row height | 28 pt |
| List row height | 28 pt single-line, 36 pt with a subtitle |
| Form row height | 28 pt |
| Section spacing | 16 pt |
| Detail padding | 20 pt |
| Corner radius | 6 pt controls, 8 pt grouped containers |
| Icon-button hit target | 24 × 24 pt minimum |
| Window minimum | 720 × 540, `.contentMinSize` |
| Window default | 820 × 600 |

## 7. Accessibility items found along the way

- Icon-only buttons in `ModesView` and `HistoryRow` have no `accessibilityLabel`.
- `ShortcutRecorder`'s recording state is signalled only by colour (green text, red dot). Add a text change — it already says "Press key…", which is sufficient — and an `accessibilityValue`.
- The mode row's shortcut is rendered as monospaced text. `Text(mode.shortcut)` should carry an `accessibilityLabel` spelling out the modifier ("Command Right"), since "⌘ Right" does not read well.
- `store.status` colour coding (green / orange) is the only signal in `StatusStrip` besides the wording; the wording already differs, so this one is fine as is.
- Once the palette is semantic, honour `accessibilityDisplayShouldReduceTransparency` in the capsule and in any material used in the sidebar.

## 8. Migration plan

Ordered so each step is independently shippable and testable.

1. **Fix the hit areas.** Add `.contentShape` to `NavButton`, size and label the icon buttons. Two small edits, no layout change, and it removes the most concrete of the three complaints on its own.
2. **Rename `ContentView.Section` to `Pane`.** Mechanical; unblocks step 4.
3. **Swap the palette for semantic colours.** Replace the `VoxlyColor` members with the system equivalents, keeping the enum as the indirection point so the change is one file. Move `.preferredColorScheme(.dark)` from `ContentView` to `CapsuleView`. Verify the capsule and the menubar popover still read correctly.
4. **Convert `ModeEditor` to a grouped `Form`.** Delete `Field`. This is where the vertical space comes back.
5. **Delete `Header`; adopt `.navigationTitle` and `.toolbar`.**
6. **Replace the hand-rolled rows with `List(selection:)`** in both `ContentView` and `ModesView`, and move create/delete to a toolbar `+` and a bottom `+`/`−` bar with a context menu and Delete-key support.
7. **Collapse to two panes** with `NavigationSplitView`, and relax the window constraints to `.contentMinSize` with a 720 × 540 minimum.

Steps 1–3 are small and worth doing regardless of whether the structural change lands. Steps 4–7 touch the same file and should land together or in quick succession, because a half-converted `ContentView` carries both idioms at once.

## 9. Non-goals and open questions

- **Light appearance is enabled, not designed.** Semantic colours make a light window functional, but the brand green and the capsule need a light-mode pass before light is offered as a supported look. Until then, `.preferredColorScheme` can stay dark at the app level as a deliberate default rather than as a hardcoded consequence.
- **Autosave is a separate entry.** The backlog already owns the draft-loss problem in "The mode editor loses unsaved edits silently", and the Save button's fate depends on it. This report keeps the Save button in the wireframe so the two changes stay independent; if autosave lands first, the footer becomes a validation line only.
- **The three-pane layout may be worth keeping if modes stop being capped at four.** The cap is what makes a permanent 300 pt list column wasteful. If per-app mode selection (P5) raises the cap into the dozens, revisit.
- **`ShortcutRecorder` keeps its current interaction.** It is a custom control by necessity — there is no system recorder for a bare-modifier shortcut — and its behaviour is not part of this redesign. Only its container changes, from a hand-built `Field` clone to a `LabeledContent` row.

## 10. Verification checklist

- The Modes screen fits in a 720 × 540 window with no scroll in either text editor.
- Clicking anywhere within a sidebar row or mode row selects it, including the empty area to the right of the text.
- Arrow keys move the selection in both lists; Delete removes a mode; Tab reaches every control in the editor; ⌘S saves.
- With Increase Contrast on, separators and control borders strengthen without any code change.
- With the accent colour set to something other than blue, the selection fill and the default button follow it.
- VoiceOver announces every button with a name and every field with its label.
- The capsule and the menubar popover are visually unchanged.
