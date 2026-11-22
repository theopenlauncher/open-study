# Open Study — Design System

> The single source of truth for how Open Study looks, feels and behaves.
> Every screen, block and control in the app is built from the tokens and rules below.
> If an implementation decision changes, **this file changes first**.

Reference material lives in [`docs/design-reference/`](docs/design-reference):

| File | What we take from it |
| --- | --- |
| `wispr-flow-main-window.webp` | **Primary reference.** Warm cream window chrome, inset off-white content card, the sidebar's typography, spacing, icon weight and soft active pill, the beige stat tile with serif numerals, the near-black primary button, the small uppercase section label ("TODAY"). |
| `notion-page.webp` | **Structural reference only.** The page model: a large page title above a free-flowing column of blocks, a calm reading width, and blocks that feel like part of a document rather than dashboard widgets. We do *not* copy its dark theme or cover imagery. |

Implementation of these tokens lives in `open-study/Design/Theme.swift` and the reusable components in `open-study/Design/Components.swift`. The `AccentColor` asset mirrors `accent` so native controls (toggles, focus rings, selection) pick it up.

**Visual verification.** Debug builds include `Debug/UISnapshotHarness.swift`. Launching the binary with `-uiSnapshots` (add `-uiSnapshotsEmpty` for first-run state, `-uiSnapshotsDark` for dark mode, `-uiSnapshotsQuit` to exit afterwards) uses an in-memory store — real data is never touched — and writes PNGs of every screen to the app container's `tmp/snapshots`. Add `-uiSnapshotsOnboarding` to capture every onboarding step instead, and `-uiSnapshotsStdout` to also print each PNG to stdout as base64 (for tools that can't read the sandboxed container). Use it to review changes against this document.

---

## 1. Design philosophy

**A calm desk, not a cockpit.** Studying is already effortful; the interface should lower the temperature. Open Study should feel like a quiet, well-lit desk: warm paper tones, generous whitespace, one clear thing to do at a time.

Principles, in priority order:

1. **Content first.** Chrome recedes. The user's subjects, notes and cards are the loudest thing on screen. Decoration that doesn't carry information is removed.
2. **Warm neutrals, restrained colour.** The palette is cream, off‑white and ink. Colour is reserved for *meaning*: a subject's identity dot, a due/overdue state, a success or destructive action. Never for decoration.
3. **One surface hierarchy.** Exactly three levels: *canvas* (cream window + sidebar) → *surface* (the inset off‑white workspace card) → *raised* (white cards inside the workspace). No glass, no gradients, no stacked translucency.
4. **Native first.** Real macOS controls, menus, context menus, sheets, keyboard shortcuts and focus rings. We style around AppKit/SwiftUI behaviour rather than fighting it.
5. **Honest data.** Every number on screen is computed from real activity. When there is no data we show a helpful empty state — never sample numbers.
6. **Blank by default.** A new subject is an empty page. The user builds their own workspace; we never pre-fill it.
7. **Consistency over novelty.** Spacing, radii and type come from the scales below — no one-off values.

---

## 2. Colour palette

All colours are defined as dynamic light/dark pairs in `Theme.swift`. Light mode is the primary, designed-first experience; dark mode is a faithful warm inversion (warm charcoal, never pure black).

### 2.1 Neutrals (structure)

| Token | Light | Dark | Usage |
| --- | --- | --- | --- |
| `canvas` | `#F6F4F0` | `#1C1B19` | Window background, sidebar, top strip. Sampled from the Wispr Flow sidebar (`#F6F4F2`), warmed slightly. |
| `surface` | `#FDFCFA` | `#232220` | The inset workspace card that holds every screen. Sampled `#FCFBFC`. |
| `raised` | `#FFFFFF` | `#2A2926` | Cards, widget blocks, popovers and inputs on top of `surface`. |
| `muted` | `#F2EFE8` | `#2D2B28` | Beige tiles (stat tiles, callout neutral, inline code, empty-state icon discs). Sampled from the Wispr stats card `#EEEBE3`. |
| `sidebarHover` | `#EFECE5` | `#262522` | Sidebar row hover. |
| `sidebarActive` | `#E9E5DC` | `#2F2D2A` | Sidebar active pill. Sampled `#EEEBE3`, deepened one step for contrast on `#F6F4F0`. |
| `hover` | `#F4F2ED` | `#2B2A27` | Hover fill for rows/buttons *inside* the workspace. |
| `border` | `#E9E5DD` | `#34322F` | Hairlines: card borders, separators, input borders. |
| `borderStrong` | `#D9D3C8` | `#45423E` | Hover borders on cards, drag targets, dividers that must be visible. |
| `inputBorder` | `#E0DBD1` | `#4A4743` | Text field borders — one step stronger than `border` so fields stay visible on dark sheets. |

### 2.2 Text

| Token | Light | Dark | Usage | Contrast on `surface` |
| --- | --- | --- | --- | --- |
| `textPrimary` | `#1E1C19` | `#EDEBE6` | Titles, body, active nav. Sampled `#26221D`/`#181818`. | 16.4 : 1 |
| `textSecondary` | `#6A655C` | `#A9A39A` | Secondary labels, metadata, inactive nav icons. | 5.6 : 1 (AA) |
| `textTertiary` | `#9A948A` | `#77726A` | Section labels, quiet metadata. Never for essential information. | 3.0 : 1 (large/UI only) |
| `textDisabled` | `#8C867C` | `#8F8A82` | Labels on disabled buttons — clearly inactive, still readable. | ≥ 3 : 1 on `muted`/`raised` |
| `placeholder` | `#A49E94` | `#85807A` | Field placeholders (set via the field's `prompt`). | — |

### 2.3 Ink & accent

| Token | Light | Dark | Usage |
| --- | --- | --- | --- |
| `ink` | `#1E1C19` | `#EDEBE6` | Primary buttons ("Check it out" in the reference), the focus hero card, the timer ring. |
| `onInk` | `#FFFFFF` | `#1C1B19` | Text/icons on `ink`. |
| `accent` | `#4A5BD0` | `#8592F0` | Keyboard focus rings, links, text selection tint, the active state of segmented controls' indicator, progress. Used sparingly — never as a large fill. |
| `accentSoft` | `#ECEEFB` | `#2B2F4A` | Selected-day fill in the calendar, selection backgrounds. |

### 2.4 Semantic

| Token | Light | Dark | Usage |
| --- | --- | --- | --- |
| `success` | `#3E8A5A` | `#6CC08A` | Completed, correct answers, "Good/Easy" ratings. |
| `warning` | `#B7791F` | `#E0A957` | Due today, medium priority, "Hard" rating. |
| `danger` | `#C0443B` | `#E57A70` | Overdue, high priority, exams, destructive buttons, "Again" rating. |
| `badgeBg` / `badgeText` | `#FCE6BF` / `#7A4F12` | `#4A3A1E` / `#F2C987` | Small "New"/status badges — directly from the reference's `New!` pill. |

Semantic colours are used for **text, icons, 1–2pt strokes, dots and 10–14% tints only** — never solid large fills.

### 2.5 Subject colours

Subjects get a muted identity colour, shown as an 8pt dot / icon tint in the sidebar, chips in the calendar and the page icon. These are deliberately desaturated so a sidebar full of subjects stays calm.

| Key | Hex | Key | Hex |
| --- | --- | --- | --- |
| `clay` | `#C2774F` | `lavender` | `#8A7BC2` |
| `sage` | `#6B9871` | `rose` | `#C26A84` |
| `sky` | `#5A8BBB` | `sand` | `#B0954F` |
| `teal` | `#4C9693` | `slate` | `#6E7A87` |

Tints of subject colours use 12% opacity on light, 20% on dark.

### 2.6 Callout tones

`neutral` (muted), `blue` (accent 10%), `green` (success 10%), `yellow` (warning 12%), `red` (danger 10%). The icon takes the full-strength tone colour; text stays `textPrimary`.

---

## 3. Typography

System fonts only — **SF Pro** for UI and reading, **New York** (`.serif` design) for display moments, **SF Mono** for timers' alternatives and code. This mirrors the reference's pairing of a clean grotesque UI with serif display numerals ("8,765 total words") and headline ("Make Flow sound like *you*").

| Style | Font | Size / weight | Line height | Usage |
| --- | --- | --- | --- | --- |
| `displayXL` | New York | 64 light, monospaced digits | 1.0 | Focus-mode timer only. |
| `display` | New York | 32 regular | 1.15 | Page titles (subject name, "Calendar", "Good morning"). |
| `numeral` | New York | 28 regular | 1.1 | Stat numerals in tiles. Paired with a 13pt `textSecondary` unit label on the same baseline ("203 wpm" pattern). |
| `title` | SF Pro | 17 semibold | 1.3 | Card/section titles, sheet titles. |
| `headline` | SF Pro | 13 semibold | 1.35 | Row titles, widget block headers, buttons. |
| `body` | SF Pro | 13 regular | 1.45 | Default UI text. |
| `reading` | SF Pro | 15 regular | 1.55 | Note blocks, callouts, flashcard backs — long-form text. |
| `noteH1/H2/H3` | SF Pro | 26 / 20 / 16 semibold | 1.3 | Headings inside notes and heading blocks. |
| `callout` | SF Pro | 12 regular | 1.4 | Metadata, timestamps, chip text. |
| `label` | SF Pro | 11 semibold, uppercase, +0.6 tracking | 1.2 | Section labels ("TODAY", "SUBJECTS"), exactly like the reference. `textTertiary`. |
| `mono` | SF Mono | 13 regular | 1.5 | Code blocks in notes, CSV previews. |

Rules:
- Numbers that change live (timers, counts) use **monospaced digits**.
- Never more than three type sizes in a single card.
- Bold is for emphasis inside reading text only; UI hierarchy uses size and colour, not bold.
- Sentence case everywhere (“New subject”, not “New Subject”) except `label`.

---

## 4. Sidebar

The sidebar sits directly on `canvas` — it is not a separate panel and has no border of its own. The workspace card's edge *is* the separator, exactly as in the reference.

**Dimensions**
- Width: **232pt** fixed (collapsible). Collapses with a 0.25s ease‑out slide: the sidebar stays in the layout and its slot animates to 0, so it slides out while the workspace card widens in the same motion (with Reduce Motion it fades). Hide it with the close button in the brand row, show it again with the button in the top strip, or toggle with **⌃⌘S**.
- Top strip: **30pt** tall, full window width, `canvas`. Traffic lights sit in it; while the sidebar is hidden, a "Show sidebar" button sits immediately to their right (x = 78pt) and fades out once the sidebar is open. Its right side carries the live timer pill.
- Horizontal padding: 12pt. Rows are inset 12pt from the window edge, so the active pill floats.

**Structure (top → bottom)**
1. **Brand row** — app glyph (SF Symbol `books.vertical.fill`, 17pt, `ink`) + "Open Study" in 19pt semibold, 12pt left inset, 14pt bottom margin. Mirrors the Flow logotype row. A 24pt `sidebar.left` icon button sits at its trailing edge to hide the sidebar ("Hide sidebar (⌃⌘S)").
2. **Global navigation** — Home, Calendar, Tasks, Flashcards, Statistics, Focus.
3. **Subjects** — `label` heading "SUBJECTS" with a `+` icon button aligned right; the subject list; an inline "New subject" row when the list is empty.
4. **Flexible space.**
5. **Footer** — a 1pt `border` separator, then Settings (and the live streak line when there is a streak).

**Rows**
- Height **32pt**, corner radius **8pt**, icon 15pt (`.regular` weight) in a 20pt slot, 10pt gap to the 13.5pt label.
- Default: icon `textSecondary`, label `textPrimary`.
- Hover: `sidebarHover` fill, 0.12s.
- Active: `sidebarActive` fill, icon + label `textPrimary`, label weight medium. No accent colour, no left bar — just the soft pill, as in the reference.
- Subject rows: icon is the subject's SF Symbol tinted with its subject colour; trailing due-count badge (`callout`, `textTertiary`) when cards/tasks are due.
- Badges (e.g. due cards on Flashcards) use the `badgeBg/badgeText` pill, 11pt semibold, radius 6.

**Subject management**
- Create: `+` → popover with name field, symbol grid and colour swatches. Return creates.
- Rename / change icon: context menu → "Edit subject…" (same popover).
- Reorder: drag a subject row; a 2pt `accent` line shows the drop position. Also "Move up/Move down" in the context menu for keyboard users.
- Delete: context menu → confirmation dialog that explains page blocks are deleted but tasks, decks, documents, quizzes and events are kept (detached from the subject).

---

## 5. Main workspace layout

- The workspace is a single **inset card**: `surface` fill, **12pt** radius, 1pt `border`, shadow `black 4%, radius 1, y 0.5` + `black 3%, radius 8, y 2`. Insets from the window: 0 top (sits under the top strip), 8pt right, 8pt bottom, 0 left (8pt when the sidebar is collapsed).
- Inside the card, every screen uses the **page frame**:
  - Horizontal padding 48pt (32pt below 900pt card width).
  - Top padding 36pt; page title (`display`) then optional subtitle (`body`, `textSecondary`), 28pt to first content.
  - **Reading width** for subject pages: max 880pt, centred (Notion-like column).
  - **Dashboard width** for Home / Statistics / Calendar / Tasks: max 1120pt, left-aligned to the same 48pt gutter.
- Sections inside a page are separated by 32pt and introduced by a `label` ("TODAY", "UPCOMING EXAMS").
- Two-column pages (Calendar, Home) use a 1fr + 300pt right rail with 24pt gap; the rail collapses below the grid under 1000pt.
- Window: default 1280×820, minimum 960×640. All layouts must reflow without horizontal scrolling at the minimum size.

---

## 6. Navigation & active states

- Selection is single-source (`AppRouter.selection`). Changing section swaps the workspace content instantly — no cross-fade or sliding, so navigation never feels laggy.
- Drill-downs inside a section (a deck's cards) use an in-page back link ("← Flashcards", `callout`, `textSecondary`) above the title rather than a toolbar back button.
- Modal tasks with a clear end (reviewing cards, taking a quiz, importing, editing an event) use **sheets**. PDFs open in their own **window** (and inline in blocks).
- **Focus mode** hides the sidebar and top-strip controls, leaving only the workspace card at full width. **Esc** or the "Exit" button restores the previous section.
- Keyboard: ⌘1–⌘6 global sections, ⌘, settings, ⌃⌘S sidebar, ⇧⌘N new subject, ⌥⌘P start/pause timer, ⇧⌘F focus mode.

---

## 7. Buttons, inputs, menus & controls

**Buttons** (`OSButtonStyle`) — height 30pt (28pt compact), radius 8pt, 13pt `headline`, 12pt horizontal padding, icon 12pt + 6pt gap.

| Variant | Fill | Text | Border | Hover | Use |
| --- | --- | --- | --- | --- | --- |
| `primary` | `ink` | `onInk` | — | 88% opacity | One per view max. "Start focus", "Import 24 cards". |
| `secondary` | `raised` | `textPrimary` | `border` | `hover` fill | Most actions. |
| `ghost` | clear | `textSecondary` | — | `hover` fill, text → primary | Toolbar-style actions, "Add card". |
| `destructive` | clear | `danger` | `danger` 30% | `danger` 8% fill | Delete actions inside sheets. |

Pressed: scale 0.98 + 6% darker.

Disabled: **never fade the whole button** — 40% opacity made labels unreadable in dark mode. Instead the label switches to `textDisabled`; a disabled `primary` button becomes a `muted` fill with a 1pt `border` (so it no longer looks actionable but stays legible); `secondary` keeps its fill and border; no hover. When a primary action is disabled because input is missing, show a one-line `callout` hint beside it explaining why (e.g. "Fill in both sides to continue").

**Icon buttons** — 28×28pt, radius 7pt, 14pt icon `textSecondary`, hover fill `hover`/`sidebarHover` depending on surface. Always have a `.help()` tooltip and accessibility label.

**Text fields** (`OSFieldStyle`) — min height 30pt, radius 8pt, `raised` fill, 1pt `inputBorder`, 10pt horizontal / 7pt vertical padding (so multi-line fields don't crowd the text); focus shows the native accent focus ring. Placeholders use `placeholder(_:)` for the `prompt`. Inline/title fields (page title, block text) are **borderless** and look like plain text until hovered.

**Menus** — always native `Menu`/`contextMenu` (NSMenu). Menu buttons in our chrome use the borderless `ghost` look with a chevron. Every row that can be acted on has a context menu that mirrors its "•••" menu.

**Segmented controls** — native `Picker(.segmented)` for filters; for large mode switches (Flashcards / Quizzes) use the `OSSegmented` pill: `muted` track, `raised` thumb with 1pt border and soft shadow.

**Checkboxes** — custom round 18pt checkbox for tasks (circle → filled `ink` circle with white check, 0.15s spring); square 16pt radius-4 checkbox for checklist items. Native toggles (`.switch`) in Settings.

**Steppers / date pickers** — native (`.field` date picker style; stepper fields in Settings).

---

## 8. Cards, containers & blocks

**Card** (`OSCard`) — `raised` fill, **10pt** radius, 1pt `border`, 16pt padding (20pt for hero cards). No shadow at rest. Cards are never nested more than one level.

**Stat tile** — `muted` fill, 10pt radius, no border; `numeral` + unit label; 16pt padding. Directly modelled on the reference's beige stats card.

**Ink hero card** — `ink` fill, 12pt radius, `onInk` text; used once on Home for "Start a focus session". It echoes the dark banner of the reference without decorative imagery.

### Blocks

Blocks are the atoms of a subject page. Two families share one chrome:

1. **Inline blocks** — text, heading, divider, callout, checklist. They have *no* border; they read as part of the document.
2. **Widget blocks** — flashcards, tasks, PDF, pomodoro, statistics, quiz. They are `OSCard`s with a 36pt header: 14pt icon (`textSecondary`) + title (`headline`) + trailing actions (ghost icon buttons).

Shared block chrome (`BlockContainer`):
- **Gutter** (left, 44pt wide, outside the reading column): on hover shows `+` (insert below) and the `⠿` drag handle (`line.3.horizontal`), 22×22pt, `textTertiary` → `textSecondary` on hover.
- **Block menu** — clicking the `⠿` drag handle opens the block menu (Notion behaviour) as a small popover; right-clicking anywhere on the block shows the same items as a native context menu: Width (Full · ⅔ · ½ · ⅓), heading level / callout colour where relevant, Duplicate (inline blocks), Move up, Move down, Delete. Widget blocks additionally keep their own "•••" menu in the card header for block-specific actions (open deck, change quiz…).
- **Resize** — a 4×28pt pill handle centred on the right edge appears on hover for resizable blocks; drag snaps to ⅓, ½, ⅔, 1. PDF blocks also have a bottom-edge handle to set height (240–1400pt).
- **Layout** — blocks flow in order and pack into rows while their widths sum ≤ 1. Gap: 16pt between blocks in a row, 6pt between inline rows, 16pt around widget rows.
- **Drag & drop** — dragging the handle lifts the block (system drag preview). A 2pt `accent` line marks the insertion point; dropping inserts before the target block (or at the end on the page's end zone).
- **Hover** never shifts layout — chrome is overlaid.

---

## 9. Radii, shadows & spacing

**Spacing scale (pt):** `2, 4, 6, 8, 12, 16, 20, 24, 32, 40, 48`. Nothing else.

| Element | Radius |
| --- | --- |
| Workspace card | 12 |
| Cards, sheets' inner panels, popovers | 10 |
| Buttons, fields, sidebar rows | 8 |
| Icon buttons | 7 |
| Chips, badges, checklist boxes | 4–6 |
| Pills (timer pill, segmented thumb) | Capsule |

Use `.continuous` (squircle) rounding everywhere.

| Shadow | Value | Use |
| --- | --- | --- |
| `shadowCard` | black 4% r1 y0.5 + black 3% r8 y2 | Workspace card only |
| `shadowFloat` | black 10% r16 y6 | Popovers we draw ourselves, the flashcard during review, drag previews |
| none | — | Everything else (borders do the work) |

---

## 10. Icons

- **SF Symbols only**, `.regular` weight at 13–15pt in lists, `.medium` at 12pt inside buttons. Outline variants in navigation (filled only for the *active* state of toggles such as a completed checkbox).
- Navigation symbols: Home `house`, Calendar `calendar`, Tasks `checklist`, Flashcards `rectangle.on.rectangle.angled`, Statistics `chart.bar.xaxis`, Focus `timer`, Settings `gearshape`, Subjects (default) `book.closed`.
- Block symbols: Text `text.alignleft`, Heading `textformat.size`, Divider `minus`, Callout `lightbulb`, Checklist `checklist.checked`, Tasks `checklist`, Flashcards `rectangle.on.rectangle.angled`, PDF `doc.richtext`, Pomodoro `timer`, Statistics `chart.bar.xaxis`, Quiz `questionmark.square.dashed`.
- Icons are `textSecondary` by default; subject icons take the subject colour; semantic icons take their semantic colour. Icons never appear without a label or tooltip.

---

## 11. Hover, selection, focus & transitions

| State | Treatment |
| --- | --- |
| Hover (rows, buttons) | Fill `hover` (or `sidebarHover` on canvas), 0.12s ease-out. Cursor stays arrow except drag handles (open hand) and resize handles (resize cursor). |
| Selected (list item, calendar day) | `accentSoft` fill or `sidebarActive` pill (sidebar). Never a saturated fill. |
| Keyboard focus | Native focus ring (`accent`). Never suppress it on interactive controls. |
| Press | scale 0.98, 0.1s. |
| Drag target | 2pt `accent` insertion line. |
| Appearing content | opacity 0 → 1, 0.18s ease-out. Lists use default SwiftUI insertion with `.opacity`. |
| Card flip (review) | 3D Y rotation 0.35s spring (response 0.4, damping 0.85). |
| Timer ring | Linear progress, updated 4×/s, no bounce. |

Animation must respect *Reduce Motion*: flips become cross-fades, slides become fades.

---

## 12. Empty & loading states

**Empty state** (`EmptyStateView`): centred in its container, 48pt `muted` disc holding a 20pt `textSecondary` symbol, `title` heading, one or two lines of `body` `textSecondary` explanation (max 360pt wide) that says *what this is* and *how to start*, then at most one `primary` or `secondary` button. No illustrations.

Examples:
- Blank subject page: the page title, a muted line "This page is empty. Press / or click + to add your first block — notes, flashcards, tasks, a PDF…", and the trailing block input.
- Statistics with no data: "Your stats appear as you study. Complete a focus session, review flashcards or finish a task to see progress here."

**Loading**: small native `ProgressView()` (`.controlSize(.small)`) inline next to the label of whatever is loading (“Importing PDF…”). No skeleton screens; local operations are fast.

**Errors**: an inline `danger` callout row inside the relevant card/sheet with a clear sentence and a recovery action (e.g. "This PDF file is missing. [Choose file…] [Remove block]"). Fatal storage errors show a full-window message with "Reveal data folder".

---

## 13. Feature-specific rules

### Home
- Title: time-of-day greeting in `display` ("Good afternoon"), date as subtitle.
- Row 1: **Ink hero card** (start focus / live timer) + **stat tile column** (today's focus minutes, cards due, current streak) — the reference's banner + stats composition.
- Below: `TODAY` label → due/overdue tasks, then `UP NEXT` → the next three tasks due after today; `HABITS` → today's habit checklist; `UPCOMING EXAMS` → countdown rows; `SUBJECTS` → compact subject cards.
- Sections with no data hide or show a one-line hint — no large empty boxes on the dashboard.

### Subject page
- Header: subject symbol (28pt, subject colour) then the editable subject name in `display`. Notion-style: no cover image.
- Body: blocks in the reading column; trailing input "Type / for blocks" in `textTertiary`.
- The `/` menu and `+` popover are the same component: search field on top, list of block types (icon in a 28pt `muted` square + name + one-line description), arrow keys + Return, Esc to close. 300pt wide, max 360pt tall.

### Notes (text blocks)
- Borderless, `reading` style; placeholder "Write something, or press / for blocks" only while empty and focused.
- **Formatting bar** appears only while a note is being edited: a compact `raised` pill (radius 10, `border`, `shadowFloat`) floating at the bottom centre of the page with: Style menu (Text, H1, H2, H3), B, I, U, bullet list, numbered list, checklist, code, link, image, table. Hidden otherwise — advanced formatting is available when needed but never occupies space or covers the text being edited. *(Changed during implementation from "docked above the block": floating above a block covered the previous block's content.)*
- Format bar buttons show the formatting at the caret or selection: B, I, U, list, checklist and code buttons that are on get a `sidebarActive` pill and a `textPrimary` icon (the same soft-pill language as the sidebar's active row). **⌘B / ⌘I / ⌘U** toggle the same formatting as the buttons.
- Lines typed into the trailing "Type / for blocks" field become a note, and the caret moves into it, so following lines are paragraphs of one note (selectable together, e.g. to make a list).
- **Images** (inserted, pasted or dropped) are scaled to fit the note's width and are never clipped; if the note gets narrower they shrink with it. Click an image to select it (2pt `accent` outline with a white square handle at the bottom-right); drag the handle to resize, keeping the aspect ratio. Right-click offers Small (⅓), Medium (½), Large (¾) and Fit Width. The chosen size is saved with the image.
- Deleting a block with content always asks for confirmation; empty blocks are removed immediately. The confirmation explains what is kept (tasks, decks, PDFs and quizzes outlive their blocks).
- Markdown shortcuts: `# `, `## `, `### `, `- `, `1. `, `[] `, ``` ``` ```.
- Inline code / code paragraphs: SF Mono 13 on `muted`.

### Flashcards
- Deck list as cards in a responsive grid (min 240pt): deck name (`headline`), subject chip, card count, **due** count in `warning` when > 0, "Review" secondary button.
- Review: sheet 720×560. The card is a `raised` 10pt-radius panel with `shadowFloat`, `reading` text centred, 32pt padding. "Show answer" (Space). Ratings appear only after flipping: Again (danger), Hard (warning), Good (success), Easy (accent) as secondary buttons with coloured labels, each showing the next interval ("10m", "4d"), keys 1–4.
- Import: three clearly numbered steps in one sheet — **1 Source** (file or paste), **2 Columns** (separator + map each column to Front / Back / Tags / Ignore, "first row is a header"), **3 Preview** (table with per-row status chips: Ready / Duplicate / Missing back). Plain-language helper text under each step.

### Pomodoro & Focus
- Timer ring: 2pt track `border`, 4pt progress `ink`, phase label above (`label`), time in `displayXL` (focus mode) or `numeral` (block).
- Phase colours are *not* used; phase is communicated by label and a small dot (focus = ink, break = success).
- Top-strip pill when running: capsule `raised` + border, dot + `mm:ss` monospaced + phase; click → Focus.
- When a phase ends the chosen alert sound plays (a built-in macOS sound picked in Settings, default Glass). Unless "start automatically" is on for the next phase, a native alert asks what to do: after focus — "Focus session complete" · **Start 5-min Break** (default) · Skip Break · Later; after a break — "Break's over" · **Start Session 2** (default) · Later. The Dock icon bounces once if the app is in the background. Breaks no longer start automatically by default.
- Focus mode: the card is mostly empty `surface`. Centre: timer; under it the current task (`title`) and subject chip; one row of controls (start/pause primary, reset, skip as ghost). Nothing else.

### Tasks
- Grouped list (Overdue / Today / Upcoming / No date) in a single `OSCard`, rows 40pt with 1pt `border` separators inset 44pt. Row: round checkbox, title, then trailing metadata chips (subject dot + name, due date — `danger` when overdue, priority flag).
- Filters: segmented (Open · Completed · All) + subject menu + sort menu in a single toolbar row under the title.

### Calendar
- Month grid on `surface` with 1pt `border` lines; day number `callout` top-left; today gets an `ink` circle with `onInk` number; selected day `accentSoft`.
- Items render as single-line chips (subject-tinted 12% background, 11pt text); exams use a `flag.fill` `danger` icon; tasks a small circle. Max 3 per cell, then "+2 more".
- Right rail: selected-day agenda + Upcoming exams with countdown numerals ("12 days").

### Quizzes
- Editor: questions as cards; type switcher (Multiple choice · True/False · Short answer).
- Taking: one question at a time, progress bar (2pt, `accent`), options as full-width selectable rows (radius 8, `border`; selected = `accentSoft` + accent border). Results: big `numeral` score, then incorrect questions listed with your answer (danger) vs correct (success).

### PDF
- Reader: native `PDFView` on `surface`, a slim toolbar (page x / y, prev/next, zoom, Highlight, Note, Annotations list). Highlights use system yellow at 45% alpha (the one place we allow it — it's the universal highlighter metaphor). Highlight is never disabled: with text selected it highlights the selection; otherwise it turns on highlighter mode (button shown as primary, an `accentSoft` hint bar with Done/Esc) where each selection is highlighted on mouse-up.

### Statistics
- Range picker (7 days · 30 days · 90 days). KPI tiles row (stat tiles), then charts in cards: Study time per day (bars, `ink` 85%), Reviews per day (bars, `accent`), Focus by subject (horizontal bars in subject colours), Activity heatmap (`ink` at 15/35/60/85% steps on `muted`).
- Charts: no gridline clutter — dashed `border` horizontal gridlines only, `callout` axis labels.

### Habits
- Habit rows: symbol, name, 7-day dot strip (filled `ink` = done), streak "🔥"-free text ("5 days"), toggle for today. Manager sheet shows 16-week heatmap per habit with current/longest streak.

### Onboarding
- Shown once on first launch, full-window, built from the app's own shell: the sidebar sits on `canvas` where the real one lives, and each question sits inside the workspace card. The sidebar is a **live, non-interactive preview** that fills in with the user's subjects as they answer, with a `callout` `textTertiary` line explaining that.
- **Personalisation, not a tour.** Every step asks one question whose answer is written into the real workspace, and shows the effect rather than explaining features: the name step's title *is* the Home greeting ("Good evening, Sam"), the tools step shows a miniature of the subject page, the rhythm step derives sessions-per-day from the goal, exams show their countdown, appearance applies live.
- Steps: name → subjects → study tools → focus rhythm + daily goal → exams → habits → appearance, notifications & privacy → summary. Header row: `label` "STEP n OF 7" + a 2pt `accent` progress bar; title in `display`, subtitle `body` `textSecondary`; content column max 620pt. Footer: ghost "Back", optional one-line `callout` hint, one `primary` button.
- Option cards (tools, rhythm, appearance) use the quiz-option treatment: `raised` + `border`; selected = `accentSoft` fill + 1.5pt `accent` border.
- **Blank by default still holds.** Study tools add *empty* widget blocks (in setup state, no sample content) only to subjects created during onboarding. Choosing no tools keeps pages blank. Subject icons are guessed from the name and colours assigned without repeats; both editable via the subject editor popover.
- Everything is optional; "Skip setup" (top-right) writes nothing except that setup was seen. Settings → Setup → "Run setup again…" re-runs it prefilled from current preferences. Re-runs are **additive only**: existing subjects show as "Already in your sidebar" and are never edited or removed, existing habits aren't suggested again, and a custom focus length is kept unless a preset is picked.
- Existing users (a store with subjects but no onboarding flag) are never shown first-run setup.
- Analytics records counts and choices only (`onboarding_completed`, `onboarding_skipped`), never names or titles.

### Settings
- Native `Form` with `.grouped` style inside the workspace card; sections: Focus timer, Notifications (including the end-of-phase Sound picker, which previews on change), Study goal, Appearance, Setup ("Run setup again…"), Data, Privacy.

---

## 14. Reusable component guidelines

| Component | File | Contract |
| --- | --- | --- |
| `Theme` / `Typo` / `Space` / `Radius` | `Design/Theme.swift` | The only place hex values, font sizes and spacing constants are written. |
| `OSButtonStyle(.primary/.secondary/.ghost/.destructive)` | `Design/Components.swift` | Use for every custom button in the workspace. |
| `IconButton` | Components | 28pt square icon button with tooltip + hover. |
| `OSCard` | Components | Raised bordered container. Never nest twice. |
| `StatTile` | Components | Muted tile with serif numeral + unit. |
| `SectionLabel` | Components | Uppercase tracked label with optional trailing accessory. |
| `PageHeader` / `PageScroll` | Components | Consistent page title, subtitle, paddings and max widths. |
| `EmptyStateView` | Components | The only way to render empty states. |
| `SubjectChip` / `SubjectDot` | Components | Subject identity everywhere (tasks, calendar, decks). |
| `TaskCheckbox`, `SquareCheckbox` | Components | Shared checkbox visuals. |
| `OSSegmented` | Components | Large mode switches. |
| `HoverHighlight` modifier | Components | Standard hover fill + animation. |
| `BlockContainer` | `Views/Subject/BlockContainer.swift` | Shared block chrome: gutter, menu, resize, drag & drop. |
| `BlockInserter` | `Views/Subject/BlockInserter.swift` | The `/` and `+` menu. |
| `TimerRing` | `Views/Focus/TimerViews.swift` | Pomodoro ring, used in block, Home and Focus. |

Rules for new components: build from tokens; support light + dark; provide hover, focus and disabled states; label every icon for VoiceOver; keep interaction native (menus, sheets, context menus).
