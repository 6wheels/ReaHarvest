# ReaHarvest — Progress

Re-oriented MVP decided on 2026-11-09 (SPEC §9). Goal: move the band (3 members, Windows) onto a structured shared Drive folder, with a simple app to check out, publish and manage versions. Nothing already built is removed; off-path work is parked in the **Backlog** milestone.

Deliver in order; each milestone is usable on its own. Coverage gate (95–100 %, justified exclusions) applies to every step once #65 is done.

## Decisions (2026-11-09)
- Preparation (migration) works **in place** on the Drive folder (first a copy holding a sample, then the real one), through `RepositoryStorage`; the same code will later organize local folders.
- Members are declared in `.library.json` (`members`) during preparation; joining writes a client folder in `.collab/<memberId>/` (revised on 2026-11-10, #108).
- No file is ever deleted: inventory (path, size, XXH3) before and after, raw `.rpp` originals in `.migration/<timestamp>/`, duplicates moved to `.trash/`.
- Non-project, non-media, non-REAPER files go to `Assets/`, unless a project references them (plain text or base64 plugin state): then reported.
- Joining requires an **empty** workspace. Windows only; macOS best effort.
- Statuses and activity are in the MVP through a minimal `JournalStore`.
- Every long action: background task (tasks zone) + report structured by kind of problem + log.
- Portable mode: `settings.json` / `index.sqlite` next to the executable are used first (demo, tests, two members on one machine).

## Decisions (2026-11-10, project review)
- Priority to the core: one role per class or module, business rules in the packages and testable without the interface (SPEC §7.2). The core hardening tickets (#90 to #105) come before the remaining M1 features.
- Design direction (DAW, mixing console) and typeface wait: recorded in #110 (M2).
- Milestones: only M0 to M3 and the Backlog remain; the tickets of phases 2 and 3 are in the Backlog, their milestones are closed.
- Progress is written in this file only; SPEC.md refers to it.
- M1 validation checks the quality of the product, not a folder left without any issue.
- Assets: a link opening the `Assets/` folder is enough until M3 (#106); the assets view comes in M3, right after the statuses and before the activity (#52, #28).
- Distribution: the members are not technical, so M2 delivers a Windows installer with auto-update (#31); the zip shared by hand is dropped (#75 closed), a portable zip stays attached to each release. The SignPath application is to be submitted by the repository owner at the start of M2.
- Recovery: a failed fix is undone at once, an interrupted one is offered to be undone, a cancelled batch leaves only complete fixes (#94); a checkout or publish started again copies only what is missing (#18, #19).
- The scan creates no folder and never writes in a repository (#97); a version adopted in batch takes its file name as label (#98); a file named by a plugin state is never moved nor purged (#96); purge is for `local` mode only in the MVP (#111).
- Identity: the installation keeps its own; a `collab` library stores the member it acts as, and each installation writes in its own client folder, so a member can join again from another computer (#108).

## M0 — Foundations (closed)
- [x] #61 portable mode
- [x] #62 background tasks zone
- [x] #63 structured reports popup
- [x] #64 file logging
- [x] #65 coverage gate in CI (measure first, then raise the existing MVP-path code to the target)
- [x] #85 integration tests of M0

## M1 — Migration (umbrella #30)
- [x] #79 center the main window at launch (priority 1)
- [ ] #59 integration tests of M1 and of the existing features (regression net; one integration test ticket per milestone: M0 #85, M2 #86, M3 #87; the version management test follows the label display again; the repository is public: CI runs on every push)
- [x] #77 known level values (artists, albums) for layout recognition
- [x] #66 inventory and no-loss check (logic in `repository`; started as a background task by the M1 fix flows)
- [x] #67 typed migration issues in To sort (layout, levels, duplicated `versionId`; media, Assets and conflict-copy detectors come with #69, #70, #23)
- [x] #71 members list in `.library.json` (done before #68, which needs the declared members)
- [x] #68 layout moves and member subfolders (batch fix with preview and optional level values, unknown folders included with a chosen level, free move per item (level chosen for unknown folders), fresh inventory (hashes of the previous one reused) and check around every batch, cancellable at every step; values of moved folders added to the known values; every step and library change logged; batch adoption of the versions already in place: see #80)
- [x] #81 merge folders moved to the same title (recursive merge of a folder moved onto an existing one; name collisions suffixed and references of the moved projects rewritten; node files merged, the target's title status wins and the dropped one is reported; what is left of the source kept in `.migration/<stamp>/merged/`; merge shown in the fix previews; identical media dedup left to #69)
- [x] #82 select the To sort items to fix in bulk (checkbox on the cards of the batch-fixable kinds, select all and counter per section; "Fix…" previews the selection, or the whole section when none; selection kept through a rescan)
- [x] #80 number of versions to adopt on the card ("N to adopt" in its figures), overview and detail header (hidden when none); the To adopt double filter and the batch adoption stay ideas on the issue
- [x] #69 media normalization and pool merge (scan detectors done: media outside `Media/`, missing, absolute or outside the library, record path other than `Media`, render target outside `Renders/`, one issue per project with the references as detail, recomputed from the indexed references without reading unchanged projects; "Full scan" on the To sort page reads every project again. Normalization fix done, in batch from To sort, one per title: media moved once into `Media/` (copied when outside the title or used by a blocked project), identical duplicates to `.trash/`, name collisions suffixed, references rewritten, record path `Media`, subprojects with their proxy; projects with missing or external media left intact and reported; non-regression on every fixture; record path already `.\Media` left as written; media used by no project in the title subfolders merged into the pool; files of projects not lifted yet kept; subprojects of the pool checked by the scan (references indexed) and normalized. Validated in REAPER by hand. Guided move goes through the normalization of the whole target title (project references kept on the move, its unshared media moved, shared ones copied, blocked project moved with its media left in place). Fixture corpus replaced (REAPER 7.85, one case per file). A title whose media (outside `Media/`) are used by another title is left as is and reported, from the indexed references; the guided move copies such media. Integration test: normalization and guided move from To sort. Projects rewritten by the migration keep their modification date (version date), read again by the rescan; report details as absolute paths. `RENDER_FILE` fix and issues in the detail view: #84)
- [x] #15 REAPER-running warning before `.rpp` rewrites (checked in the code: opening in the running instance, every rewrite started from the interface goes through `runProjectChange`)

Core hardening, in this order, before the remaining features:
- [ ] #90 one module for library paths and media references
- [ ] #91 one reader and writer for project files, one encoding policy (not valid UTF-8: reported, never rewritten)
- [ ] #92 Migration split into inventory, append-only journal and guarded storage
- [ ] #93 batch of fixes run outside the app, in one isolate
- [ ] #94 undo of a fix that failed or was interrupted, from the journal
- [ ] #95 media normalization as gather, pure plan, then apply (the plan is the preview)
- [ ] #96 files named by a plugin state never moved nor purged
- [ ] #97 scan creating no folder, never writing in a repository
- [ ] #98 default label for versions adopted in batch
- [ ] #99 fix proposals computed outside the interface
- [ ] #100 LibraryService split into one service per role
- [ ] #101 one writing task per library at a time
- [ ] #102 rescan of the title changed by an action only
- [ ] #103 index written outside the UI isolate
- [ ] #104 recovery screen when `settings.json` is unreadable or newer (independent)
- [ ] #105 one interface file per page or component

Remaining features:
- [ ] #84 issues in the detail view, render target fix
- [ ] #70 other files to Assets with reference check (uses #96)
- [ ] #106 Assets folder link in the title detail
- [ ] #23 Google Drive conflict copies (reported only)
- [ ] #89 "Organize my band's folder" wizard (split from #73: folder, layout, known values, members, then To sort)
- [ ] #60 title card actions menu
- [ ] #88 Retry instead of Continue anyway in the REAPER running warning
- [ ] #72 convert to a collab repository
- [ ] Validation (quality of the product, not the state of the migrated folder): full preparation on the sample copy with no product defect (every fix behaves as specified, nothing lost, no crash); issues without an automatic fix (missing or external media, conflict copies…) stay listed in To sort for a manual decision; inventory check passes; every fixed project opens in REAPER with no new missing media

## M2 — Join and sync
- [ ] #86 integration tests of M2
- [ ] #107 durable sync state outside the rebuildable index (before #18)
- [ ] #108 member identity per library, joining again from another computer (before #73)
- [ ] #73 first-run wizard: join / create (organize: #89, M1)
- [ ] #17 RepositoryStorage / MountedFolderStorage (mostly done)
- [ ] #74 repository view of titles not checked out
- [ ] #18 checkout
- [ ] #19 publish
- [ ] #38 edge-case conflicts (remote deletion, concurrent creation)
- [ ] #20 release
- [ ] #21 sync states and actions
- [ ] #26 members, ownership and forced publish
- [ ] #83 repair of corrupted application files
- [ ] #109 history of a title without parsing every backup again
- [ ] #31 Windows installer, GitHub Releases and auto-update (replaces #75; SignPath application submitted at the start of M2)
- [ ] #110 design direction (DAW, mixing console), typeface and own components
- [ ] Validation: two portable copies on one machine sharing `H:\My Drive\test_sync`

## M3 — Shared statuses and activity
- [ ] #87 integration tests of M3
- [ ] #25 file watching reliability on Drive streaming folders (spike, before #24)
- [ ] #24 JournalStore (statuses, activity, tasks, notes, lyrics; journals per installation, #108)
- [ ] #76 statuses through the JournalStore
- [ ] #52 assets view in the title detail
- [ ] #28 shared asset metadata
- [ ] #29 activity feed
- [ ] #27 tasks, notes and lyrics in the interface (collab mode)

## Parked (Backlog)
#12, #14, #22, #32, #40, #43, #46, #47, #48, #53, #58, #78, #111, #112.
Former phase 2 (backend): #33, #34, #45. Former phase 3 (tools): #35, #36, #37.

## Pending outside the plan
None.

## Next step
Core hardening of M1, starting with #90, then #91 to #105 in order; then #84 and #70.
