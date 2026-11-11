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
  `.RTrackTemplate` and trimmed plugin cache `.ini` files are. The tests that
  need media files create them.
- Project Settings > Media: recording path `Media`, unless stated otherwise.
- Before committing, check for local paths and names, including inside the
  base64 plugin states and in `ORIGINAL_FILENAME` lines (written by REAPER when
  it copies a media file into the project folder, not shown in its UI).

## Corpus

Saved with REAPER 7.85 on Windows, unless stated otherwise.

| Fixture | Content |
|---|---|
| `tracks.rpp` | main project: title, author, notes with accents, 128 BPM 3/4 with a tempo change to 140, 48 kHz, nested folders, colors, takes, MIDI, take FX, FX container, master FX, bypassed and offline FX, markers, regions |
| `render.rpp` | FLAC render, folder `Renders`, pattern `$project - $region`, stems, ID3 and Vorbis metadata |
| `render-file.rpp` | MP3 render to the file `Renders\Mix final.mp3` |
| `media-paths.rpp` | one media path form per item (see below) |
| `empty.rpp` | new project saved untouched (REAPER defaults) |
| `subproject.rpp`, `subproject-child.rpp`, `Media/subproject-child-imported.rpp` | a project inserted as an item of another one; REAPER copied the child into `Media/` and wrote its media as an absolute path |
| `clap.rpp`, `reaper-clap-win64.ini`, `reaper-vstplugins64.ini` | Surge XT as CLAP and VST3, with the plugin caches trimmed to the plugins of the corpus |
| `track-template-single.RTrackTemplate` | one track with ReaEQ and ReaComp |
| `track-template-folder.RTrackTemplate` | a folder and two child tracks, FX on the folder |
| `linux.RPP` | project saved on Linux (WSL, REAPER 7.84): platform name; CRLF line endings, as on Windows |
| `reference-metadata.rpp` | metadata written by REAPER 7.84 (`EXTSTATE`, render metadata) |
| `project-template.rpp` | template used to create versions |
| `track-template-1.RTrackTemplate` | older track template |
| `windows-1252.rpp` | project that is not valid UTF-8: one track named `Café tête` written in Windows-1252 (bytes `E9`, `EA`), record path `.\audio-files`. Built by hand, opened and saved again by REAPER 7.85, which kept these bytes as they were |

`media-paths.rpp` (all items on one track, media not copied into the project
folder, recording path `D:\Export\Media`, render folder `D:\Export\Renders`):

| Reference | Case |
|---|---|
| `a.wav` | relative path |
| `Loops\loop.wav` | subfolder |
| `D:\ReaHarvestTests\Samples\kick.wav` | outside the project, absolute path |
| `b.flac`, `c.mp3` | FLAC, MP3 |
| `d.mid` | external MIDI file (`FILE "d.mid" QN`) |
| `a.wav` again | same file used by two items |
| `gone.wav` | missing media |

## Values the tests rely on

| Fixture | Values |
|---|---|
| `reference-metadata.rpp` | `7.84/win64`, title `demosong`, author `band`, notes `notes 1`, record path `.\audio-files`, render file empty, pattern `$project`, tempo 120, 4/4, 44100 Hz, `EXTSTATE` `ReaHarvest` → `VERSIONID=test`, `RENDER_STEMS 0` |
| `tracks.rpp` | `7.85/win64`, quoted title `Sample song`, author `Band`, notes `line 1` / `   line 2` / `Prise de voix à refaire`, tempo 128, 3/4, 48000 Hz, 13 tracks (names and depths in `rpp_test.dart`), 6 items, 5 media under `.\Media\`, ReaEQ, ReaComp, ReaSynth and a JS plugin, no `EXTSTATE`; copied as a version in index, repository, app and integration tests |
| `render-file.rpp` | no `RENDER_PATTERN` line (record path and render settings patches); loose project in app and integration tests |
| `media-paths.rpp` | `FILE` references rewritten by `rewriteMediaPaths`, MIDI `QN` token kept; left intact by the normalization (missing `gone.wav`, external `kick.wav`) |
| `clap.rpp` | `Surge XT.vst3` VST3i plugin |
| `linux.RPP` | `7.84/linux-x86_64` |
| `project-template.rpp` | template used to create versions (rpp and integration tests) |
| all projects | parsed and written back byte-exact; normalized without losing a media (except `media-paths.rpp`) |
