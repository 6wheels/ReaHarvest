# ReaHarvest

Collaborative project manager for [REAPER](https://www.reaper.fm/).

ReaHarvest keeps REAPER projects organized, versioned and shared without
duplicating media:

- **Enforced organization**: projects live in a fixed folder layout
  (e.g. `artist/album/title`), navigable by tags.
- **Versions**: every `.rpp` of a title is a version with a stable id, an
  owner and a label, stored in the project itself.
- **Shared media pool**: all versions of a title use a single append-only
  `Media/` folder. Media is never copied per person or per version.
- **Local work, cloud repository**: you always work on a local copy; a cloud
  folder (Google Drive, Dropbox, OneDrive, Nextcloud, NAS…) acts as the shared
  repository, with checkout / publish / release and conflict detection.
- **Collaboration**: members, version ownership, statuses, tasks, notes,
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

Progress is tracked in [PROGRESS.md](PROGRESS.md) and in
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

ReaHarvest is an independent project, not affiliated with or endorsed by
Cockos Incorporated. REAPER is a trademark of Cockos Incorporated.
