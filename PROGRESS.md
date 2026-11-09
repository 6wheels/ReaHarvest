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

## M0 — Foundations
- [ ] #61 portable mode
- [ ] #62 background tasks zone
- [ ] #63 structured reports popup
- [ ] #64 file logging
- [ ] #65 coverage gate in CI (measure first, then raise the existing MVP-path code to the target)
- [ ] #59 integration tests (moves with the milestones)

## M1 — Migration (umbrella #30)
- [ ] #66 inventory and no-loss check
- [ ] #67 typed migration issues in To sort
- [ ] #68 layout moves and member subfolders
- [ ] #69 media normalization and pool merge
- [ ] #70 other files to Assets with reference check
- [ ] #71 members list in `.library.json`
- [ ] #72 convert to a collab repository
- [ ] #15 REAPER-running warning before `.rpp` rewrites
- [ ] #23 Google Drive conflict copies (reported only)
- [ ] Validation: full preparation on the sample copy, zero issues left, inventory check passes, every project opens in REAPER with no missing media

## M2 — Join and sync
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
- [ ] #24 JournalStore (reduced to statuses and activity)
- [ ] #76 statuses through the JournalStore
- [ ] #29 activity feed

## Parked (Backlog)
#12, #14, #22, #25, #27, #28, #31, #32, #38, #40, #43, #46, #47, #48, #52, #53, #58, #60. Phases 2 and 3 unchanged.

## Pending outside the plan
- New fixture corpus parked in a git stash (`fixtures: new anonymized corpus in progress`), TODO in `test/fixtures/README.md`.

## Next step
Start M0 with #65: measure the current coverage of every package and the app, report it, then decide the order with the user (#61 is small and unblocks multi-member testing).
