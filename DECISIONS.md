# ReaHarvest — Decisions

Dated decisions and the open points left to the maintainer. Agents do not need this file: `SPEC.md` and the tickets already hold what they need.

## Open points for the maintainer
- #161: the synchronization preference is confirmed (2026-11-14); its implementation details are to write before an agent starts.
- #24: confirm the proposed rule for a timestamp far ahead of the local clock (in the ticket; SPEC §10 point 14).
- #52: confirm that the built-in PDF preview is left out of the MVP (in the ticket; SPEC §5.9 asks for it).
- #31: the Microsoft Store study, at the start of M2. #25: the watching spike on the real Drive, at the start of M3. #110: the design proposal.

## Decisions (2026-11-09)
- Preparation (migration) works **in place** on the Drive folder (first a copy holding a sample, then the real one), through `RepositoryStorage`; the same code will later organize local folders.
- Members are declared in `.library.json` (`members`) during preparation; joining writes a client folder in `.collab/<memberId>/` (revised on 2026-11-10, #108).
- No file is ever deleted: inventory (path, size, XXH3) before and after, raw `.rpp` originals in `.migration/<timestamp>/`.
- Non-project, non-media, non-REAPER files go to `Assets/`, unless a project references them (plain text or base64 plugin state): then reported.
- Joining requires an **empty** workspace. Windows only; macOS best effort.
- Statuses and activity are in the MVP through a minimal `JournalStore`.
- Every long action: background task (tasks zone) + report structured by kind of problem + log.
- Portable mode: `settings.json` / `index.sqlite` next to the executable are used first (demo, tests, two members on one machine).

## Decisions (2026-11-10, project review)
- Priority to the core: one role per class or module, business rules in the packages and testable without the interface (SPEC §7.2). The core hardening tickets (#90 to #105) come before the remaining M1 features.
- Design direction (DAW, mixing console) and typeface wait: recorded in #110 (M2).
- Milestones: only M0 to M3 and the Backlog remain; the tickets of phases 2 and 3 are in the Backlog, their milestones are closed.
- Progress is written in this file only; SPEC.md refers to it (since 2026-11-18: `PROGRESS.md`, one file per milestone in `progress/`, and the dated decisions in `DECISIONS.md`; since 2026-11-19: scope, state, order and dependencies in the GitHub issues, `PROGRESS.md` and `progress/` only give the lanes and advised models).
- M1 validation checks the quality of the product, not a folder left without any issue.
- Assets: a link opening the `Assets/` folder is enough until M3 (#106); the assets view comes in M3, right after the statuses and before the activity (#52, #28).
- Distribution: the members are not technical, so M2 delivers a Windows installer with auto-update (#31); the zip shared by hand is dropped (#75 closed), a portable zip stays attached to each release. #31 starts with a study of the Microsoft Store as another route. Code signing (SignPath Foundation) is out of M2: Backlog, #113; the M2 installer is unsigned, with a guide for the SmartScreen warning.
- Recovery: a failed fix is undone at once, an interrupted one is offered to be undone, a cancelled batch leaves only complete fixes (#94); a checkout or publish started again copies only what is missing (#18, #19).
- The scan creates no folder and never writes in a repository (#97); a version adopted in batch takes its file name as label (#114, former #98); a file named by a plugin state is never moved nor purged (#96).
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

## Decisions (2026-11-14, feedback after the first test)
SPEC.md is updated with every point; the impacted tickets start with a "Rework (2026-11-14)" section that wins over their older text. No backward compatibility: nothing has shipped.
- One self-contained folder per version (`<title>/<version>/<version>.RPP`, its own `Media/`, `Renders/`, `.history/`; the title keeps `.node.json`, `Assets/`, `.trash/`). No shared pool, no de-duplication, no collision rename, no unused-media purge: space is managed by hand (sizes shown, trash, purge in every mode) (SPEC §3.2, §4.3, §5.4; #145). This replaces the pool merge, dedup and lift delivered in #68, #69 and #81.
- The application never changes the date of a `.RPP`: adoption, migration, checkout and backup keep it; only a new version takes the current date (§4.2; #146).
- Title-oriented scan and To sort; each version gets its label and member in the fix (§5.8; #147, #148, #149). Organizing a band's library in place on the repository is confirmed (§3.0): clean up first, convert (#72), then members join a clean repository.
- Synchronization version by version, one writer per version; "Recover as my version" (§5.5; #18, #19). Synchronization preference in M2 (#161, confirmed on 2026-11-14). Edge cases (#38): a deletion by the owner is never a conflict; a creation clash renames the second version folder and tells its author.
- Title status derived from the versions, no longer stored (§5.9). Tags shared in `.node.json` (#132).
- Long and sensitive actions in the foreground, library locked; only the scan in the background; one notification zone (§5.2; #150, #151).
- Statistics (#129, #130), tags (#132), version detail view (#12) and tray (#135) move to M1. #109 and #111 are closed as obsolete.

## Decisions (2026-11-20)
- The "Organize a collaboration folder" wizard creates a `collab` library at once (name, repository and workspace folders, members with the local member required, layout and known values), then a full scan and "To sort". "Finish the organization" sets `ready` in `.library.json`; only a ready library can be joined; the fixes in place are reserved to its creator (SPEC §5.1, §5.8; #89). No conversion: #72 is dropped, every mode change goes to the Backlog.
- Statuses, version labels and owners stay in the `.node.json` files in every mode; in `collab` mode their changes are also activity events of the collab store, never its source (SPEC §5.9). Their propagation to the other members before notifications is to refine (SPEC §10 point 15).
- Copies of projects and version folders are detected with generic patterns, whatever the provider, under one generic report kind (#23).

## Decisions (2026-11-21)
- No forcing: no action overwrites a version of the repository changed by someone else. A conflict on one same version offers to keep the repository version or to publish as a new version. Another member's version is not publishable: "Save as my own version" is a shortcut to its duplication (label asked, owner = current member). A version never published can be published by the local member whatever its owner; in a library with members, a version without owner is refused until it gets one (SPEC §5.5; #19, #26).
- Release only frees space in the workspace, for a version or a whole title, and only when everything is in the repository; the repository is unchanged, nothing goes to the trash, no confirmation lets unpublished files be lost (SPEC §5.5; #20).
- Node file merge: `tags` merged tag by tag, each tag once (SPEC §5.5; #18).
