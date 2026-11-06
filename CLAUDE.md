# ReaHarvest

Collaborative REAPER project manager (Flutter desktop + Dart).

## Specification

`SPEC.md` is the single source of truth. Read the relevant sections before implementing any feature.
- Items marked **[TO VALIDATE]** must be verified (on real files / real REAPER behavior) before implementing the related feature. Record the outcome in `SPEC.md`.
- Open points are listed in §10; out-of-scope items in §11.
- Deliver in milestone order (§9): A (`local`) → B (`cloud`) → C (`collab`).

## Workspace

Dart pub workspace (root `pubspec.yaml`). App in `apps/desktop` (Flutter, package `reaharvest`), libraries in `packages/<name>` (package `reaharvest_<name>`). New packages must be added to the root `workspace:` list and use `resolution: workspace`.

Commands (from repo root unless stated):
- `flutter pub get`: resolve the whole workspace
- `flutter analyze`: analyze everything
- `dart test` in a `packages/<name>` folder; `flutter test` in `apps/desktop`
- `flutter run -d windows` / `flutter build windows` in `apps/desktop`

Test fixtures: real `.rpp` files in `test/fixtures/`.

## Rules

- Code, identifiers, comments and technical file names in English. UI text in French, i18n-ready.
- KISS. No speculative abstractions beyond the ports defined in the spec (`RepositoryStorage`, `CollabStore`).
- `packages/domain` and `packages/rpp` are pure Dart: no Flutter, no `dart:io`.
- Packages depend on interfaces from `domain`, never on concrete adapters. Adapters are wired only in the app entry point.
- No PocketBase or journal type leaks outside its adapter.
- RPP writer: targeted text patches only, never re-emit a whole file; atomic writes (temp file + rename).
- Never block the UI isolate: scan, parsing, hashing and copies run in isolates.
- No destructive operation without trash/history and explicit confirmation.
- Cloud folders may contain on-demand files: never read or hash them unless size/mtime changed.
