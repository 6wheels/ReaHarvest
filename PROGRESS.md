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
- Distribution: the members are not technical, so M2 delivers a Windows installer with auto-update (#31); the zip shared by hand is dropped (#75 closed), a portable zip stays attached to each release. #31 starts with a study of the Microsoft Store as another route. Code signing (SignPath Foundation) is out of M2: Backlog, #113; the M2 installer is unsigned, with a guide for the SmartScreen warning.
- Recovery: a failed fix is undone at once, an interrupted one is offered to be undone, a cancelled batch leaves only complete fixes (#94); a checkout or publish started again copies only what is missing (#18, #19).
- The scan creates no folder and never writes in a repository (#97); a version adopted in batch takes its file name as label (#114, former #98); a file named by a plugin state is never moved nor purged (#96); purge is for `local` mode only in the MVP (#111).
- Identity: the installation keeps its own; a `collab` library stores the member it acts as, and each installation writes in its own client folder, so a member can join again from another computer (#108).

## Decisions (2026-11-11, hardening tickets review)
- The hardening tickets are completed on GitHub so that an agent can take one without other context; order, lanes and advised models are in the hardening plan of M1.
- #98 is folded into #114: the default label of a version adopted in batch is written in `.node.json` by the lift.
- #97 only adds the `writeNodes` flag: a repository folder without node file gives no title; how it is shown is decided in #74.
- Until the collab store exists (M3), label and owner are in `.node.json` in every mode; an owner is written only when the library declares members (#114). SPEC.md is updated with it and with the other decisions of this review.
- The migration journal and inventory are appended line by line: `RepositoryStorage` gets an `append` operation (#92).
- The file needed by the tests of #96 is built by the tests, not added to the fixtures.
- Version actions take the turn of their library like the tasks, without being shown in the tasks zone (#101); the UI isolate opens the index read-only (#103).

## Decisions (2026-11-11, review of every open ticket)
- Encoding (#91, validated in REAPER 7.85 with `test/fixtures/windows-1252.rpp`): REAPER saves a project that is not valid UTF-8 without converting it. Such a project is read as Windows-1252 and written back as read; nothing is reported and no fix refuses it. This replaces "reported, never rewritten".
- REAPER running (#88): a project change is refused while a REAPER process runs, with "Retry" and "Cancel" only; "Continue anyway" disappears.
- Node files in the synchronization (#18, #19, #107): never in conflict, merged key by key against their last common content kept in the sync state; the local value wins on an entry changed on both sides, and the report says so.
- Integration tests (#59, #86, #87): each feature ticket writes the test of its feature; #59 itself covers the features already delivered and runs now, as the regression net of the hardening.
- Other files (#70): one issue per file; a file named by a project stays listed, the report of the fix tells why.
- Conversion (#72): the converted folder leaves the application; it is joined again in M2 (#73).
- Repository folder without node file (#74): not a title, reported in "To sort".
- Every open ticket of M1, M2 and M3 now holds its implementation details, order and advised model. The Backlog is not detailed: only #46 and #53 got a note about #114.

## M0 — Foundations (closed)
- [x] #61 portable mode
- [x] #62 background tasks zone
- [x] #63 structured reports popup
- [x] #64 file logging
- [x] #65 coverage gate in CI (measure first, then raise the existing MVP-path code to the target)
- [x] #85 integration tests of M0

## M1 — Migration (umbrella #30)
- [x] #79 center the main window at launch (priority 1)
- [x] #59 integration tests of M1 and of the existing features (regression net; one integration test ticket per milestone: M0 #85, M2 #86, M3 #87; the version management test follows the label display again; the repository is public: CI runs on every push; lot A, the existing features, done with a shared `integration_test/harness.dart`; lot B, the delivered M1 features, done: To sort issues and bulk selection, inventory with its resume and gap, layout moves, lifts and merges, members, versions to adopt; the remaining lines are ticked by their feature tickets)
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

Core hardening, before the remaining features (listed in the order of the steps below; #98 is folded into #114 and closed):
- [x] #90 one module for library paths and media references
- [x] #91 one reader and writer for project files, one encoding policy (not valid UTF-8: read as Windows-1252, written back as read)
- [x] #104 recovery screen when `settings.json` is unreadable or newer (independent)
- [x] #92 Migration split into inventory, append-only journal and guarded storage
- [x] #93 batch of fixes run outside the app, in one isolate
- [x] #114 only `versionId` in the `.RPP`; label and owner in `.node.json` in every mode until the collab store exists (M3); default label of the versions adopted in batch (former #98); no migration of existing data
- [x] #97 scan creating no folder, never writing in a repository
- [x] #94 undo of a fix that failed or was interrupted, from the journal (failed fix undone at once and reported, `undoFailed` stops the batch; interrupted fix offered at startup and before any fix of its library, no batch until undone; every rewrite names its copy, `fixes/<n>/` beyond the first; a move refused before its line when impossible; failures and stops injected after each change of a normalization, lift, merge and guided move, partial journal appends included; integration test of the interrupted fix; after review: batches and undos of a library run one after the other, an undo not ended leaves its fix to undo, copies checked before the first change, replaced content kept under `replaced/`, the batch reads again its own journal only, journal paths confined to the library, a move whose source exists again stops the undo, REAPER warning before the undo, detection without reading the inventory, a queued fix shown as a waiting task)
- [x] #95 media normalization as gather, pure plan, then apply (the plan is the preview; shown per title in the fix dialog with its counts and operations, computed in an isolate; the guided move goes through the same steps; `xxh3Hash` moved to `repository`, hashes taken from the inventory for unchanged media)
- [x] #96 files named by a plugin state never moved nor purged (`namedOutsideSources`: plain text and base64 plugin states, UTF-8 and UTF-16LE; normalization leaves such a file and reports `referencedByPlugin`; the purge never lists it, versions and backups count, the trash does not)
- [x] #99 fix proposals computed outside the interface (`proposeFixes` and `buildFixes` in `repository`; the dialog shows and collects; the lift preview shows the final label; PR #138)
- [x] #100 LibraryService split into one service per role (`LibraryCatalog`, `LibraryScans`, `VersionActions`, `MigrationActions`, `ReaperActions` in `state/`, each with its provider and tests; `libraryServiceProvider` removed)
- [ ] #101 one writing task per library at a time
- [ ] #102 rescan of the title changed by an action only
- [ ] #103 index written outside the UI isolate
- [ ] #105 one interface file per page or component

### Hardening plan for the agents (2026-11-11)

Every ticket was checked against the code and completed on GitHub with an "Implementation details" section (formats, signatures, texts, tests, order): a ticket is self-sufficient with the SPEC sections it names. The same order is written in each ticket.

Steps. A ticket starts when the tickets named before it are merged; at most 3 agents at once, one branch or worktree per ticket.

| Step | Tickets | Run | Starts when merged |
|---|---|---|---|
| 1 | #90 | alone | now |
| 1–2 | #59, lots A and B (integration tests of the delivered features) | two agents, beside #90 and #91 | now; merged before step 3 |
| 2 | #91 | alone | #90 |
| 3 | #92, then #93 | lane "migration" | #91 |
| 3 | #114 | lane "version metadata", beside the two others | #91 |
| 3 | #97 | lane "scan", beside the two others | #91 |
| 4 | #94 | beside #95 | #93, #114 |
| 4 | #95 | beside #94 | #93 |
| 5 | #96 | beside #99 | #95 |
| 5 | #99 | beside #96 | #95, #114 |
| 6 | #100 | alone | every ticket above |
| 7 | #101 | beside #102, merged first | #100 |
| 7 | #102 | beside #101 | #100 |
| 8 | #103 | beside #105 | #102 |
| 8 | #105 | beside #103 | #101, #102 |
| any | #104 | beside any step | now |

- #90, #91 and #100 run alone: the first two touch every file of `packages/repository`, the last moves the whole of `state/libraries.dart`.
- Longest chain: #90, #91, #92, #93, #95, #99, #100, #102, #103 (9 tickets in a row instead of 16).
- Files shared by tickets run side by side (small conflicts expected, the second to merge rebases): `ReportKind` in `domain/report.dart` (the declaration order is the display order), `app_en.arb` and `app_fr.arb`, the exports of `reaharvest_repository.dart`, the schema version of the index, `scanner.dart`, `fixes.dart`, `state/libraries.dart` until #100.

Smallest model advised per ticket (a judgment from the tickets and the code, not a measure):

| Model | Tickets | Why |
|---|---|---|
| Sonnet | #90, #91, #96, #97, #99, #100, #101, #104, #105 | Moves, splits and bounded rules, fully specified, with the existing tests as a net |
| Opus | #59, #92, #93, #95, #102, #103, #114 | Tests driving the real application, formats and crash safety, isolates, rewrite of subtle rules, consistency of the index, change across every package |
| Opus, then a review by the largest model before merge | #94 | Undo after a failure or a crash: data safety |

Haiku is not advised for any of these tickets: the only one small enough was #98.

Brief common to every ticket:
- Read the ticket in full (its "Implementation details" win over the older text above them when they differ), the SPEC sections it names and this plan. Counts given in a ticket ("six files", "eleven places") are indicative: search the code.
- Done means: `flutter analyze` clean, `dart tool/coverage.dart <suite>` passing for every suite named in the ticket, texts in both ARB files, the box ticked here. SPEC.md already states the target of every ticket (updated on 2026-11-11): it changes only when a ticket finds a gap in it.
- Fixtures are saved by REAPER, never edited by hand, and hold no plugin storing a path (`test/fixtures/README.md`): #91 uses `windows-1252.rpp`; the special file of #96 (plugin state naming a file) is built by the tests.
- No in-memory `RepositoryStorage` is shared today: #92 adds one to the tests of `packages/repository`, with injected failures; #93, #94 and #95 reuse it.
- Not for an agent: the steps listed in "For the maintainer", the hand validation of each milestone.

Remaining features:
- [ ] #84 issues in the detail view, render target fix
- [ ] #70 other files to Assets with reference check (uses #96)
- [ ] #106 Assets folder link in the title detail
- [ ] #23 Google Drive conflict copies (reported only)
- [ ] #89 "Organize my band's folder" wizard (split from #73: folder, layout, known values, members, then To sort)
- [ ] #60 title card actions menu
- [ ] #88 Retry and Cancel only in the REAPER running dialog (a change is refused while REAPER runs)
- [ ] #72 convert to a collab repository

Plan of the remaining features (after the core hardening; at most 3 agents at once):

| Step | Tickets | Model | Starts when merged |
|---|---|---|---|
| 9 | #84 beside #70 beside #23 | Sonnet | #105 (and #96, #99 for #70) |
| 10 | #60 beside #88 beside #106 | Sonnet for #60; Haiku for #88 and #106 | #105 |
| 11 | #89 beside #72 | Sonnet | #100 (and #94 for #72) |
| 12 | Validation of M1 | maintainer | everything above |

Steps 9 to 11 only depend on the hardening: with more agents they can overlap. Shared files: `ReportKind`, both ARB files, `scanner.dart` (#70, #23), the title detail files (#84, #60, #106).
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
- [ ] #31 Windows installer, GitHub Releases and auto-update (replaces #75; Microsoft Store study first, at the start of M2; unsigned)
- [ ] #110 design direction (DAW, mixing console), typeface and own components

Plan of M2 (ticket details written on 2026-11-11; the names of existing code they give are to check after the hardening):

| Step | Tickets | Model | Starts when merged |
|---|---|---|---|
| 1 | #107 beside #108 beside #83 | Sonnet | M1 |
| 1 | #109 | Sonnet | #103 |
| 1 | #31, Store study | maintainer (an agent prepares the MSIX build) | M1 |
| 1 | #17 | none: closed when #92 is merged | #92 |
| 2 | #74 | Opus | #107, #97, #103 |
| 3 | #73 beside #18 | Sonnet for #73, Opus for #18 | #74 (and #108, #89 for #73) |
| 4 | #19 beside #20 | Opus; #19 reviewed by the largest model before merge | #18 |
| 5 | #21 | Sonnet | #18, #19, #20 |
| 6 | #26 beside #38 | Sonnet for #26, Opus for #38 | #21 (and #108 for #26); #38 once its proposal is confirmed |
| 7 | #31, delivery | Sonnet | step 6 |
| 8 | #110 | largest model with the maintainer for the proposal, then Sonnet, alone | every interface ticket of M2 |
| 9 | Validation of M2 | maintainer | everything above |

#86 has no agent of its own: each ticket ticks its line.
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

Plan of M3:

| Step | Tickets | Model | Starts when merged |
|---|---|---|---|
| 1 | #25 | maintainer (an agent writes the probe tool, Sonnet) | M2 |
| 2 | #24 beside #52 | Opus for #24, Sonnet for #52 | #25, #108 for #24; nothing for #52 |
| 3 | #76 beside #28 | Opus for #76, Sonnet for #28 | #24 (and #52 for #28) |
| 4 | #29 | Sonnet | #76 |
| 5 | #27 | Sonnet | #29 |
| 6 | Validation of M3 | maintainer | everything above |

#87 has no agent of its own: each ticket ticks its line.

## Parked (Backlog)
#12, #14, #22, #32, #40, #43, #46, #47, #48, #53, #58, #78, #111, #112, #113, #121.
Done outside the milestones: #126 CI time, ~5 min 20 instead of ~12.5 (parallel jobs, integration tests in three Windows batches run by `tool/coverage.dart`, app coverage gate on the merged reports; new integration test files join a batch on their own).
Former phase 2 (backend): #33, #34, #45. Former phase 3 (tools): #35, #36, #37.

## For the maintainer (not for an agent)
- #38: confirm the proposed behavior of the two edge-case conflicts (in the ticket) before an agent starts.
- #24: confirm the proposed rule for a timestamp far ahead of the local clock (in the ticket; SPEC §10 point 14).
- #52: confirm that the built-in PDF preview is left out of the MVP (in the ticket; SPEC §5.9 asks for it).
- #23: produce a real conflict on Google Drive for desktop to confirm its naming pattern (SPEC §3.0).
- #31: the Microsoft Store study, at the start of M2. #25: the watching spike on the real Drive, at the start of M3. #110: the design proposal.

## Next step
Done: #90, #91 and both lots of #59 (the integration harness now sizes the native window to 1024x768, so the app stays visible during the tests, #119).
Now: step 3 of the hardening plan. #92 and #93 are merged (PR #120, #122): #95 can start. #114 is merged (PR #124): #94 can start. #97 is merged (PR #125): step 3 is complete. #95 is merged (PR #128): #96 and #99 can start. #96 is merged (PR #137). #99 is merged (PR #138). #94 is merged (PR #136, reviewed, its ten findings fixed). After the hardening: the remaining features of M1 (steps 9 to 11), then the validation of M1.
