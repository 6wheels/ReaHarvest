# ReaHarvest

Collaborative project manager for [REAPER](https://www.reaper.fm/).

ReaHarvest keeps REAPER projects organized, versioned and shared:

- **Enforced organization**: projects live in a fixed folder layout
  (e.g. `artist/album/title`), navigable by search, filters and free tags.
- **Self-contained versions**: each version of a title is its own folder
  (project, media, renders and backup points), with a stable id stored in the
  project, an owner and a label. Version sizes are shown; space is freed by
  hand through the trash.
- **Local work, cloud repository**: you always work on a local copy; a cloud
  folder (Google Drive, Dropbox, OneDrive, Nextcloud, NAS…) acts as the shared
  repository, with checkout / publish / release version by version, each
  version having a single writer, its owner.
- **Collaboration**: members, version ownership, statuses, tags, tasks, notes,
  lyrics and shared assets.

Each library runs in one of three modes: `local` (personal projects on one
machine), `cloud` (local + cloud backup, multi-machine) or `collab` (shared
with a band).

## Status

Early development, not usable yet. The first goal is an MVP that moves a band
onto a structured shared cloud folder, delivered in four milestones:

- **M0 — Foundations** (done): portable mode, background tasks, reports, logs.
- **M1 — Migration** (in progress): organize an existing folder in place,
  without losing any file.
- **M2 — Join and sync**: join a library, checkout, publish, release.
- **M3 — Shared statuses and activity**

Progress is tracked in [PROGRESS.md](PROGRESS.md) (one file per milestone in
[progress/](progress/)) and in
[GitHub issues](https://github.com/6wheels/ReaHarvest/issues).

## Platforms

Windows and macOS first, Linux secondary.

## Development

Requirements: Flutter (Dart SDK ^3.13).

The repository is a Dart pub workspace:

```
apps/desktop/      Flutter desktop app (package reaharvest)
packages/domain/   pure Dart entities, rules and ports
packages/rpp/      pure Dart REAPER .rpp parser and targeted patch writer
packages/library/  libraries, modes and configuration
packages/repository/  repository/workspace scanning and layouts
packages/index/    local SQLite index
packages/reaper/   REAPER launching, resources and plugin caches
test/fixtures/     sample .rpp files used by the tests
```

Common commands (from the repository root unless stated):

```sh
flutter pub get          # resolve the whole workspace
flutter analyze          # analyze everything
dart test                # in a packages/<name> folder
flutter test             # in apps/desktop
flutter run -d windows   # in apps/desktop
```

The full specification is in [SPEC.md](SPEC.md).

## License

[GPL-3.0](LICENSE)

## Disclaimer

REAPER is a registered trademark of Cockos Incorporated, used with permission.
ReaHarvest is an independent project, not affiliated with or endorsed by
Cockos Incorporated.
