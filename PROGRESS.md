# ReaHarvest — Progress

Re-oriented MVP decided on 2026-11-09 (SPEC §9). Goal: move the band (3 members, Windows) onto a structured shared Drive folder, with a simple app to check out, publish and manage versions. Nothing already built is removed; off-path work is parked in the **Backlog** milestone.

Deliver in order; each milestone is usable on its own. Coverage gate (95–100 %, justified exclusions) applies to every step once #65 is done.

## Decisions (2026-11-09)
- Preparation (migration) works **in place** on the Drive folder (first a copy holding a sample, then the real one), through `RepositoryStorage`; the same code will later organize local folders.
- Members are declared in `.library.json` (`members`) during preparation; joining writes `.collab/<memberId>/member.json`, and joined members are hidden from the others.
- No file is ever deleted: inventory (path, size, XXH3) before and after, raw `.rpp` originals in `.migration/<timestamp>/`, duplicates moved to `.trash/`.
- Non-project, non-media, non-REAPER files go to `Assets/`, unless a project references them (plain text or base64 plugin state): then reported.
- Joining requires an **empty** workspace. Windows only; macOS best effort.
- Statuses and activity are in the MVP through a minimal `JournalStore`.
- Every long action: background task (tasks zone) + report structured by kind of problem + log.
- Portable mode: `settings.json` / `index.sqlite` next to the executable are used first (demo, tests, two members on one machine).

## M0 — Foundations (closed)
- [x] #61 portable mode
- [x] #62 background tasks zone
- [x] #63 structured reports popup
- [x] #64 file logging
- [x] #65 coverage gate in CI (measure first, then raise the existing MVP-path code to the target)
- [x] #85 integration tests of M0

## M1 — Migration (umbrella #30)
- [x] #79 center the main window at launch (priority 1)
- [ ] #59 integration tests of M1 and of the existing features (regression net; one integration test ticket per milestone: M0 #85, M2 #86, M3 #87; the version management test follows the label display again; CI skipped on push while the repository is private, run it on demand)
- [x] #77 known level values (artists, albums) for layout recognition
- [x] #66 inventory and no-loss check (logic in `repository`; started as a background task by the M1 fix flows)
- [x] #67 typed migration issues in To sort (layout, levels, duplicated `versionId`; media, Assets and conflict-copy detectors come with #69, #70, #23)
- [x] #71 members list in `.library.json` (done before #68, which needs the declared members)
- [x] #68 layout moves and member subfolders (batch fix with preview and optional level values, unknown folders included with a chosen level, free move per item (level chosen for unknown folders), fresh inventory (hashes of the previous one reused) and check around every batch, cancellable at every step; values of moved folders added to the known values; every step and library change logged; batch adoption of the versions already in place: see #80)
- [x] #81 merge folders moved to the same title (recursive merge of a folder moved onto an existing one; name collisions suffixed and references of the moved projects rewritten; node files merged, the target's title status wins and the dropped one is reported; what is left of the source kept in `.migration/<stamp>/merged/`; merge shown in the fix previews; identical media dedup left to #69)
- [x] #82 select the To sort items to fix in bulk (checkbox on the cards of the batch-fixable kinds, select all and counter per section; "Fix…" previews the selection, or the whole section when none; selection kept through a rescan)
- [x] #80 number of versions to adopt on the card ("N to adopt" in its figures), overview and detail header (hidden when none); the To adopt double filter and the batch adoption stay ideas on the issue
- [ ] #69 media normalization and pool merge (scan detectors done: media outside `Media/`, missing, absolute or outside the library, record path other than `Media`, render target outside `Renders/`, one issue per project with the references as detail, recomputed from the indexed references without reading unchanged projects; "Full scan" on the To sort page reads every project again. Normalization fix done, in batch from To sort, one per title: media moved once into `Media/` (copied when outside the title or used by a blocked project), identical duplicates to `.trash/`, name collisions suffixed, references rewritten, record path `Media`, subprojects with their proxy; projects with missing or external media left intact and reported; non-regression on every fixture; record path already `.\Media` left as written; media used by no project in the title subfolders merged into the pool; files of projects not lifted yet kept; subprojects of the pool checked by the scan (references indexed) and normalized. Validated in REAPER by hand. Guided move goes through the normalization of the whole target title (project references kept on the move, its unshared media moved, shared ones copied, blocked project moved with its media left in place). Fixture corpus replaced (REAPER 7.85, one case per file). Left: integration test (#59), media used by another title (to decide). `RENDER_FILE` fix and issues in the detail view: #84)
- [ ] #84 issues in the detail view, render target fix
- [ ] #70 other files to Assets with reference check
- [ ] #72 convert to a collab repository
- [ ] #15 REAPER-running warning before `.rpp` rewrites
- [ ] #23 Google Drive conflict copies (reported only)
- [ ] Validation: full preparation on the sample copy, zero issues left, inventory check passes, every project opens in REAPER with no missing media

## M2 — Join and sync
- [ ] #86 integration tests of M2
- [ ] #73 first-run wizard: join / organize / create
- [ ] #17 RepositoryStorage / MountedFolderStorage (mostly done)
- [ ] #74 repository view of titles not checked out
- [ ] #18 checkout
- [ ] #19 publish
- [ ] #20 release
- [ ] #21 sync states and actions
- [ ] #26 members, ownership and forced publish
- [ ] #75 Windows release zip
- [ ] Validation: two portable copies on one machine sharing `H:\My Drive\test_sync`

## M3 — Shared statuses and activity
- [ ] #87 integration tests of M3
- [ ] #24 JournalStore (reduced to statuses and activity)
- [ ] #76 statuses through the JournalStore
- [ ] #29 activity feed

## Parked (Backlog)
#12, #14, #22, #25, #27, #28, #31, #32, #38, #40, #43, #46, #47, #48, #52, #53, #58, #60, #78, #83, #88. Phases 2 and 3 unchanged.

## Pending outside the plan
None.

## Next step
Continue M1: #69 integration test (#59) and decision on media used by another title, then #84 (issues in the detail view, render target fix) and #70.
