# Contributing to Open Study

Thank you for your interest in improving Open Study! Whether you are fixing a typo, reporting a bug, suggesting a feature or writing code, your help is appreciated.

This guide explains how the project is organised and what we look for in a contribution, so that your time is well spent and your changes can be merged smoothly.

## Table of contents

- [Code of Conduct](#code-of-conduct)
- [Ways to contribute](#ways-to-contribute)
- [Reporting bugs](#reporting-bugs)
- [Suggesting features](#suggesting-features)
- [Development setup](#development-setup)
- [Project architecture](#project-architecture)
- [Coding guidelines](#coding-guidelines)
- [Design guidelines](#design-guidelines)
- [Privacy and analytics rules](#privacy-and-analytics-rules)
- [Changing the data model](#changing-the-data-model)
- [Testing your changes](#testing-your-changes)
- [Commit messages](#commit-messages)
- [Pull request process](#pull-request-process)
- [Licensing of contributions](#licensing-of-contributions)

## Code of Conduct

This project and everyone participating in it are governed by our [Code of Conduct](CODE_OF_CONDUCT.md). By participating, you are expected to uphold it.

## Ways to contribute

- **Report bugs** you encounter while using the app.
- **Suggest features** or improvements to existing ones.
- **Improve documentation**, including this guide, the [README](README.md) and [DESIGN.md](DESIGN.md).
- **Fix bugs or implement features** — issues labelled `good first issue` or `help wanted` are a great place to start.
- **Review pull requests** and test changes others have proposed.

For anything larger than a small fix, please **open an issue first** to discuss the approach. This avoids duplicated effort and makes sure the change fits the project's direction.

## Reporting bugs

Before opening a bug report, please search the [existing issues](https://github.com/theopenlauncher/open-study/issues) to see whether it has already been reported.

A good bug report includes:

- **Open Study version** (or the commit you built from) and **macOS version**.
- **Steps to reproduce** the problem, as minimal as possible.
- **What you expected** to happen and **what actually happened**.
- **Screenshots or a screen recording**, if the issue is visual.
- **Crash logs**, if the app crashed (available in *Console.app → Crash Reports*).

> [!IMPORTANT]
> Remove any personal content — notes, card text, file names — from screenshots and logs before attaching them.

**Security vulnerabilities must not be reported in public issues.** Please follow the process in [SECURITY.md](SECURITY.md) instead.

## Suggesting features

Feature requests are welcome. Open an issue that describes:

- the **problem** you are trying to solve or the study workflow you want to support;
- your **proposed solution**, and any alternatives you considered;
- how it fits Open Study's principles (see [Design guidelines](#design-guidelines)).

Open Study intentionally stays calm and focused, so not every feature will be a good fit — but every suggestion is read and considered.

## Development setup

### Prerequisites

- A Mac that can run Xcode 26 (the app itself runs on **macOS 14** or later)
- **Xcode 26** or later
- Git

There are no other tools to install. The only third-party dependency, the [PostHog iOS/macOS SDK](https://github.com/PostHog/posthog-ios), is fetched automatically by Swift Package Manager.

### Getting the code

1. [Fork the repository](https://github.com/theopenlauncher/open-study/fork) on GitHub.
2. Clone your fork and add the upstream remote:

   ```bash
   git clone https://github.com/<your-username>/open-study.git
   ```

   ```bash
   cd open-study
   ```

   ```bash
   git remote add upstream https://github.com/theopenlauncher/open-study.git
   ```

3. Open `open-study.xcodeproj` in Xcode and wait for package resolution to finish.

### Signing

The project uses automatic signing. To run it locally, open the `open-study` target's **Signing & Capabilities** tab and either select your own development team or choose *Sign to Run Locally*.

**Do not commit signing changes** (team IDs or bundle identifier edits) in your pull request. If Xcode modifies `project.pbxproj` only for signing, discard that hunk before committing.

### Building and running

- **In Xcode:** select the `open-study` scheme and press **⌘R**.
- **From the command line** (ad-hoc signed):

  ```bash
  xcodebuild -project open-study.xcodeproj -scheme open-study -configuration Debug CODE_SIGN_IDENTITY=- build
  ```

### Your data while developing

Debug builds use the **same data store as an installed copy of the app**:

```
~/Library/Containers/xyz.elipseday.open-study/Data/Library/Application Support/OpenStudy/
```

If you use Open Study for your own studies, back up this folder before running development builds — especially when working on the [data model](#changing-the-data-model). For screen-by-screen visual work, prefer the [snapshot harness](#ui-snapshot-harness), which never touches real data.

### Analytics during development

Usage data is **enabled by default**, and debug builds send to the project's PostHog instance tagged with the `development` environment. To keep test traffic out of the project's data, do one of the following:

- turn off **Settings → Privacy → Share anonymous usage data** in your development build; or
- point the app at your own PostHog project by setting environment variables in Xcode under **Product → Scheme → Edit Scheme… → Run → Arguments → Environment Variables**:

  | Variable | Description | Default |
  | --- | --- | --- |
  | `POSTHOG_PROJECT_TOKEN` | PostHog project (public client) token | The Open Study project token |
  | `POSTHOG_HOST` | PostHog ingestion host | `https://us.i.posthog.com` |

[`.env.example`](.env.example) documents these variables for reference. Note that the app **does not load `.env` files** — values must be provided as process environment variables (for example through the scheme). Keep personal scheme edits out of your pull request.

## Project architecture

Open Study is a single-target SwiftUI app with no backend.

| Layer | Location | Responsibilities |
| --- | --- | --- |
| **App** | `open-study/open_studyApp.swift` | Scenes (main window, PDF reader window, Settings), menu commands, SwiftData container set-up |
| **Models** | `open-study/Models/Models.swift` | All `@Model` types and their enums; `AppSchema.models` lists every persisted type |
| **Services** | `open-study/Services/` | Logic that is independent of views: SM-2 scheduling and streaks (`StudyLogic`), the Pomodoro state machine and preferences (`PomodoroEngine`), CSV import (`CardImporter`), PDF storage (`DocumentStore`), page operations (`TopicPages`), navigation (`AppRouter`) and analytics |
| **Views** | `open-study/Views/<Feature>/` | One folder per feature: Home, Subject, Notes, Flashcards, PDF, Focus, Tasks, Calendar, Quizzes, Habits, Statistics, Settings, Sidebar |
| **Design** | `open-study/Design/` | Design tokens (`Theme.swift`) and reusable components (`Components.swift`) |
| **Debug** | `open-study/Debug/` | `DEBUG`-only UI snapshot harness |

Key technical facts:

- **Persistence** is SwiftData with a single on-disk store (`OpenStudy.store`); CloudKit is disabled. Imported PDFs are copied into `Documents/` beside the store and referenced by file name.
- **Concurrency:** the target uses *Approachable Concurrency* with **`MainActor` as the default actor isolation**. Code is main-actor isolated unless explicitly marked otherwise; mark pure helpers `nonisolated` only when they need to be called off the main actor.
- **Rich notes** use `NSTextView` with TextKit 1 (for native lists and tables) and are stored as RTFD data on the block.
- **Sandboxing:** the app runs in the App Sandbox with read-only access to user-selected files and outgoing network connections only. Changes that require new entitlements need a clear justification in the pull request.

## Coding guidelines

- **Follow the existing style.** Match the formatting, naming and file organisation of the code around your change. Use Xcode's default indentation (4 spaces).
- **Prefer native APIs.** Use SwiftUI, SwiftData and AppKit before reaching for custom implementations. New third-party dependencies are discouraged and must be discussed in an issue first.
- **Keep logic testable.** Put pure logic (scheduling, parsing, aggregation) in `Services/` as plain functions or types, separate from views.
- **Comment the *why*.** Add a short comment wherever behaviour is non-obvious, especially around AppKit/TextKit workarounds — see `RichTextEditor.swift` for examples.
- **Handle failure gracefully.** Never crash on bad input or damaged files; show a helpful message instead. Never lose or silently overwrite user data — write to a temporary file and replace atomically, as `DocumentStore` does.
- **No compiler warnings.** Your change should build cleanly in both Debug and Release configurations.
- **Accessibility.** Give icon-only buttons a help tag or accessibility label, keep keyboard navigation working and respect *Reduce Motion*.
- **Keep user-facing text consistent.** Use sentence case ("New subject", not "New Subject") and plain, friendly language.

## Design guidelines

[DESIGN.md](DESIGN.md) is the single source of truth for how Open Study looks and behaves. Before working on UI:

1. **Read the relevant sections** of DESIGN.md, including the feature-specific rules in §13.
2. **Use the tokens.** Colours, typography, spacing, radii and motion come from `Theme.swift` (`Theme`, `Typo`, `Space`, `Motion` …). Don't introduce one-off values.
3. **Reuse components** from `Components.swift` (buttons, cards, page headers, empty states) before creating new ones.
4. **Respect the principles:** content first, colour only for meaning, native controls, honest data and blank-by-default pages — never add sample or placeholder data to a user's workspace.
5. **Support light and dark mode.** Check every UI change in both.
6. **If a design decision changes, update DESIGN.md in the same pull request.** The document changes first.

## Privacy and analytics rules

Open Study promises its users that their content never leaves their Mac. Every contribution must preserve this:

- **Never send user content** — note text, card text, task or subject names, file names, PDF contents or anything derived from them — to any network service.
- **All analytics go through `PostHogAppLogger` / `Analytics`.** New events must respect the user's setting (they are dropped automatically when `Analytics.isEnabled` is `false`) and contain only counts, durations and on/off values.
- **New analytics events must be listed in the pull request description** and reflected in the *Anonymous usage data* section of the [README](README.md).
- **No new network connections** beyond PostHog without prior discussion in an issue.

## Changing the data model

SwiftData models in `Models.swift` define the on-disk format of every user's data, so changes need extra care. A change that SwiftData cannot migrate automatically will prevent the store from opening, and users will see the "couldn't open its data" screen.

- **Prefer additive changes:** new properties should be optional or have a default value.
- **Avoid renaming or removing** properties or models; if unavoidable, discuss it in an issue first so a migration plan can be agreed.
- **Register new model types** in `AppSchema.models`.
- **Test with an existing store:** run your build against data created by the version on `main` (using a backed-up copy) and confirm everything opens and is intact.
- Call out any model change prominently in your pull request description.

## Testing your changes

The project does not yet have an automated test suite — contributions that add unit tests (for example for `SM2`, `CardImporter` or streak calculations) are very welcome.

Until then, please verify your changes manually:

- [ ] The app builds without warnings in Debug and Release.
- [ ] The feature works as described, including edge cases (empty states, very long text, missing files).
- [ ] UI looks correct in **light and dark mode** and at different window sizes.
- [ ] Keyboard shortcuts and focus behave correctly.
- [ ] Existing data still opens after your change (if you touched models or storage).
- [ ] Nothing that contains user content is logged or sent over the network.

### UI snapshot harness

Debug builds include a snapshot harness (`Debug/UISnapshotHarness.swift`) that seeds fixture content into an **in-memory store** (your real data is never touched), visits every screen and writes PNG snapshots. Add these launch arguments under **Edit Scheme… → Run → Arguments → Arguments Passed On Launch**:

| Argument | Effect |
| --- | --- |
| `-uiSnapshots` | Enable the harness with seeded sample content |
| `-uiSnapshotsEmpty` | Capture first-run (empty) states instead |
| `-uiSnapshotsDark` | Capture in dark mode |
| `-uiSnapshotsQuit` | Quit automatically when finished |

Snapshots are written to the app container's temporary directory:

```
~/Library/Containers/xyz.elipseday.open-study/Data/tmp/snapshots/
```

Attaching before/after snapshots to UI pull requests makes review much faster.

## Commit messages

- Write the subject line in the **imperative mood**, describing the behaviour change: *"Continue outer list numbering after nested items"*, not *"Fixed lists"*.
- Keep the subject line under about 72 characters, with no trailing full stop.
- Add a body when the reason for a change isn't obvious from the subject.
- Keep each commit focused on one logical change.

## Pull request process

1. **Create a branch** from an up-to-date `main`, using a descriptive prefix:
   - `feat/…` for new features
   - `fix/…` for bug fixes
   - `docs/…` for documentation
   - `refactor/…` for internal changes with no behaviour change
2. **Make your changes**, following the guidelines above.
3. **Rebase on `main`** before opening the pull request:

   ```bash
   git fetch upstream
   ```

   ```bash
   git rebase upstream/main
   ```

4. **Open a pull request** against `main`, and in the description:
   - explain **what** changed and **why**, linking the related issue (e.g. `Closes #12`);
   - include **screenshots** (light and dark) for any visual change;
   - list any **data model**, **entitlement** or **analytics** changes;
   - describe **how you tested** it.
5. **Respond to review.** A maintainer will review your pull request; please address feedback by pushing new commits. Pull requests may be squashed when merged.

Keep pull requests small and focused — several small pull requests are much easier to review than one large one.

## Licensing of contributions

Open Study is licensed under the [GNU Affero General Public License v3.0](LICENSE). By submitting a contribution, you agree that it is licensed under the same license, and you confirm that you have the right to submit it.

---

Thank you for helping make Open Study better! 📚
