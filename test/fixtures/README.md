# Test fixtures

Real files saved by REAPER, used for parsing and byte-exact round-trip tests.
Never edit them by hand, except to anonymize a value (same structure kept).

## Rules for new fixtures

- REAPER 7.8x, normal settings, saved by REAPER itself.
- Cockos plugins and stock JSFX only (exception: `clap.rpp`, Surge XT).
- No user presets, no sampler or IR loader, no plugin storing a path.
- Generic names only (`Sample song`, `Band`, `Guitar`…): nothing from a real
  song, in track names, notes, markers or plugin states.
- Short media (a few seconds). Media files are never committed: only `.rpp`,
  `.RTrackTemplate` and trimmed plugin cache `.ini` files are.
- Project Settings > Media: recording path `Media`, unless stated otherwise.
- Before committing, check for local paths and names, including inside the
  base64 plugin states and in `ORIGINAL_FILENAME` lines (written by REAPER when
  it copies a media file into the project folder).

## Current corpus (being replaced)

`project-1.rpp` to `project-5.rpp` and `track-template-2.RTrackTemplate` are
replaced by the new corpus below. `reference-metadata.rpp`,
`project-template.rpp` and `track-template-1.RTrackTemplate` are kept.

Values the tests rely on:

| Fixture | Values |
|---|---|
| `reference-metadata.rpp` | `7.84/win64`, title `demosong`, author `band`, notes `notes 1`, record path `.\audio-files`, render file empty, pattern `$project`, tempo 120, 4/4, 44100 Hz, `EXTSTATE` `ReaHarvest` → `VERSIONID=test`, `RENDER_STEMS 0` |
| `project-1.rpp` | first track `Track 1` at depth 0, nested tracks, media starting with `.\audio-files\media-`, length > 0; copied as a version in index, repository, app and integration tests |
| `project-2.rpp` | `FILE` references rewritten by `rewriteMediaPaths` |
| `project-3.rpp` | record path and render settings patches |
| `project-4.rpp` | quoted title `Sample song`, tempo 109 |
| all projects | at least one `TDR Kotelnikov.vst3` VST3 and one JS plugin |
| `project-template.rpp` | template used to create versions (rpp and integration tests) |

## New corpus (`new/`, work in progress)

All saved with REAPER 7.85 on Windows.

| Fixture | Content | Status |
|---|---|---|
| `tracks.rpp` | main project: title, author, notes with accents, 128 BPM 3/4, 48 kHz, nested folders, colors, takes, MIDI, take FX, FX container, master FX, bypassed and offline FX, markers, regions | to complete (see TODO) |
| `render.rpp` | FLAC render, folder `Renders`, pattern `$project - $region`, stems | to complete (see TODO) |
| `render-file.rpp` | MP3 render to the file `Renders\Mix final.mp3` | done |
| `media-paths.rpp` | one media path form per item | to redo (see TODO) |
| `empty.rpp` | new project saved untouched (REAPER defaults) | done |
| `subproject.rpp`, `subproject-child.rpp` | a project inserted as an item of another one | to anonymize (see TODO) |
| `clap.rpp`, `reaper-clap-win64.ini`, `reaper-vstplugins64.ini` | Surge XT as CLAP and VST3, with the plugin caches | caches to trim |
| `track-template-single.RTrackTemplate` | one track with ReaEQ and ReaComp | done |
| `track-template-folder.RTrackTemplate` | a folder and two child tracks, FX on the folder | done |
| `linux.rpp` | project saved on Linux (WSL): LF line endings, platform name | to add |

No older REAPER version: installers only, not worth risking the daily
install. `project-4.rpp` (older format, no personal data) may be kept as the
only older format sample (to decide).

## TODO

### `tracks.rpp`

1. Make `FX Bus` a folder holding `Reverb`, so that `Reverb`, the last track,
   closes it (`ISBUS 2 -1`).
2. Add a tempo change to 140 BPM in the middle of the project
   (Insert > Tempo/time signature change marker).

### `render.rpp`

1. Fill File > Project Render Metadata, then save:
   - ID3: Title `$title`, Artist `$author`, Album `Sample album`, Year `2026`;
   - Vorbis: Title `$title`, Artist `$author`.
2. Anonymize the `ORIGINAL_FILENAME` lines (`I:\documents-win\…`).

### `media-paths.rpp`

Goal: one media path form per item. Redo it from scratch:

1. Prepare the files on disk before opening REAPER (copies of any `.wav`; the
   `.flac` and `.mp3` from a quick render of an item, the `.mid` from
   File > Export project MIDI):
   ```
   D:\RH-test\
     media-paths\            project folder
       Media\
         a.wav
         gone.wav            deleted at the end
         b.flac
         c.mp3
         d.mid
         Loops\
           loop.wav
     Samples\
       kick.wav              outside the project folder
   ```
2. New project, saved right away as `D:\RH-test\media-paths\media-paths.rpp`,
   without copying media into the project folder.
3. Insert one file per track (Insert > Media file), without copying it:

   | Track | File | Case |
   |---|---|---|
   | 1 | `Media\a.wav` | relative path |
   | 2 | `Media\Loops\loop.wav` | subfolder |
   | 3 | `D:\RH-test\Samples\kick.wav` | outside the project, absolute path |
   | 4 | `Media\b.flac` | FLAC |
   | 5 | `Media\c.mp3` | MP3 |
   | 6 | `Media\d.mid` | external MIDI file (refuse the conversion to an in-project MIDI item, Preferences > Media > MIDI) |
   | 7 | `Media\a.wav` again | same file used by two items |
   | 8 | `Media\gone.wav` | missing media |

4. Project Settings: recording path `D:\Export\Media`, render folder
   `D:\Export\Renders`.
5. Save, close the project, delete `gone.wav`. Do not reopen the project.

To check in the result: how REAPER writes a file outside the project folder
(absolute path expected, never `..\`).

### `subproject.rpp`

Anonymize the `ORIGINAL_FILENAME` line (local path of
`subproject-child.rpp`).

### `linux.rpp`

Add the project saved on Linux (WSL) to `new/`.

### Integration

1. Trim the plugin caches to the lines used by the tests.
2. Do not commit `new/Media/` nor `*.rpp-bak`.
3. Move the new files to `test/fixtures/`, remove the replaced ones, adapt
   the tests to the new values, and fill the "values the tests rely on" table
   for the new corpus.
