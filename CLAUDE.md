# ReaHarvest

Collaborative REAPER project manager (Flutter desktop + Dart).

## Sources of truth

- **GitHub issues** define the scope and the acceptance criteria. Read the issue in full with its comments (`gh issue view <n> --comments`): a later section ("Rework", "Implementation details", comments) wins over older text.
- Only issues labelled `ready` may be implemented. Any other issue: do not start, ask.
- `SPEC.md` holds the vision, the domain model and the cross-cutting rules. Read the sections the issue names. Items marked **[TO VALIDATE]** are verified on real files or real REAPER behavior before the related feature is implemented; the outcome is recorded in `SPEC.md`.
- `PROGRESS.md` and `progress/` are for planning only (order, lanes, advised models), never a source of scope or state.
- Issue state (open, closed, labels, milestone) is read with `gh`, never from the markdown files.

## Workspace

Dart pub workspace (root `pubspec.yaml`). App in `apps/desktop` (Flutter, package `reaharvest`), libraries in `packages/<name>` (package `reaharvest_<name>`). New packages must be added to the root `workspace:` list and use `resolution: workspace`.

Commands (from repo root unless stated):
- `flutter pub get`: resolve the whole workspace
- `flutter analyze`: analyze everything
- `dart test` in a `packages/<name>` folder; `flutter test` in `apps/desktop`
- `dart tool/coverage.dart <suite>`: tests with the coverage gate
- `flutter run -d windows` / `flutter build windows` in `apps/desktop`

Test fixtures: real `.rpp` files in `test/fixtures/`.

## Rules

- Code, identifiers, comments and technical file names in English. UI text in English (default) and French, through ARB localization files.
- KISS. No speculative abstractions beyond the ports defined in the spec (`RepositoryStorage`, `CollabStore`).
- `packages/domain` and `packages/rpp` are pure Dart: no Flutter, no `dart:io`.
- Packages depend on interfaces from `domain`, never on concrete adapters. Adapters are wired only in the app entry point.
- No PocketBase or journal type leaks outside its adapter.
- RPP writer: targeted text patches only, never re-emit a whole file; atomic writes (temp file + rename).
- No destructive operation without trash/history and explicit confirmation.
- At most 3 agents at once, one worktree and one branch per issue.
- Fixtures are saved by REAPER, never edited by hand, and hold no plugin storing a path (`test/fixtures/README.md`); a special file a test needs is built by the test.
- The tests of `packages/repository` share an in-memory `RepositoryStorage` with injected failures (`packages/repository/test/memory_storage.dart`): reuse it.
- Each milestone ends with a hand validation by the maintainer: not for an agent.

## UI

- Look: DAW / mixing console, polished, never flashy. Own design system over a minimal Material base (SPEC §7.1).
- Every color, radius, spacing, text style and duration comes from the theme tokens (`apps/desktop/lib/theme/`): no hard-coded value.
- Reuse the existing components (`apps/desktop/lib/ui/widgets.dart`, `glass_dialog.dart`…) before writing a new one.
- Never tell states apart by hue alone: also luminance, shape, icon or glow.
- The showcase (`apps/desktop/lib/main_showcase.dart`, real components on mock data, no I/O) must keep compiling; a new or reworked component is added to it. Run: `flutter run -d windows -t lib/main_showcase.dart` in `apps/desktop`.

## Definition of done

- The acceptance criteria of the issue are met, nothing beyond its scope. Deferred or discovered work is written as a comment on the issue.
- `flutter analyze` clean; `dart tool/coverage.dart <suite>` passing for every suite the issue names (gate 95–100 %, each excluded line justified by `// coverage:ignore-…`).
- Every new text in both ARB files.
- The integration test of the feature written when the issue asks for it, and its line ticked in the integration tests issue of the milestone.
- `SPEC.md` changed only when the issue revealed a gap in it; the pull request says so.

## When in doubt

- Ask before acting, on any doubt: scope, wording, side effects, data safety. Never pick a default silently.
- An issue that contradicts `SPEC.md` or the code: stop and report the contradiction.
- When no one can be asked (unattended run): write the question as a comment on the issue and stop.

## Performance

Targets in SPEC §8.
- Never block the UI isolate: scan, parsing, hashing, copies and index writes run in isolates.
- Cloud folders may contain on-demand files: never read or hash them unless size/mtime changed.
- Check the weight of a dependency before adding it (footprint, SPEC §8).
