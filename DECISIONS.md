# ReaHarvest — Decisions

Dated decisions and the open points left to the maintainer. Agents do not need this file: `SPEC.md` and the tickets already hold what they need.

## Open points for the maintainer
- #110: the design proposal (icons and light theme), step 1 of the issue.

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
- No forcing: no action overwrites a version of the repository changed by someone else. A conflict on one same version offers to keep the repository version or to publish as a new version. Another member's version is not publishable: "Make my own version" is a shortcut to its duplication (label asked, owner = current member). A version never published can be published by the local member whatever its owner; in a library with members, a version without owner is refused until it gets one (SPEC §5.5; #19, #26).
- Release only frees space in the workspace, for a version or a whole title, and only when everything is in the repository; the repository is unchanged, nothing goes to the trash, no confirmation lets unpublished files be lost. UI name EN "Remove local copy" / FR « Retirer la copie locale » (`release` in the code), always after a confirmation saying that the repository copy stays intact (SPEC §5.5; #20, #21).
- Node file merge: `tags` merged tag by tag, each tag once (SPEC §5.5; #18).
- One action makes a new version of the current member from another version, in the repository or local: EN "Make my own version" / FR « En faire ma propre version », label asked (formerly "Recover as my version" and "Save as my own version"; SPEC §5.5; #18, #26, #74).

## Decisions (2026-11-23)
- Preparing, then normal work: while a collaboration folder is being prepared, everything is done on the repository, `.library.json` included; once the library is ready, every change is made in the workspace, `.library.json` included, and reaches the repository only by publishing (SPEC §3.0, §6.5).
- `.library.json` is merged at each checkout and publish: members by `memberId`, known values value by value, the other fields from the repository (SPEC §5.5; #18, #19).
- Publish and Remove local copy apply to one version or to a whole title (#21).
- Two versions created with the same folder name: no choice offered; the second publish renames its copy automatically and notifies its author (SPEC §5.5; #38).
- A version renamed or deleted by its owner is followed by the other workspaces once a scan of the repository tells them; the same title created on both sides is merged into one title with several versions (SPEC §5.5; #38).
- What is left in "To sort" of the repository once the library is ready: its creator reopens the organization (`ready` back to false), the library read only for the other members meanwhile, then finishes it again. The workspace copy of `.library.json` is made as soon as normal work starts (SPEC §3.0; #191).
- The Microsoft Store study moves to the Backlog; M2 delivers the installer route (#31).
- Release: the version of `pubspec.yaml` is the only source (tag, About page, update feed); a portable zip holds a `portable` marker; the update feed is signed and published with each release; the members get a short EN/FR summary written by an agent for non-technical readers, GitHub keeps the technical changelog (SPEC §5.1, §8; #31).
- Icons: Lucide replaces the Material icons (#110).
- Collab journals: appended directly in the repository, each installation in its own `.collab/` folder; the only direct write of normal work; the synchronization never touches `.collab/` (SPEC §3.0, §6.3; #24).
- Remote collab changes found by polling the journal files every 15 s; file watching moves to the Backlog (#25). No special rule for clocks far ahead: timestamps in absolute UTC (SPEC §10 points 3 and 14).
- "Check for updates" also merges the node files of the checked-out titles and `.library.json` when they changed in the repository (SPEC §10 point 15; #161).
- Activity feed: plain words for non-technical members, consecutive similar events grouped into one line (#29).
- Asset files: a tab always shown in the title detail, read only for a repository title not checked out; built-in preview for images and `.txt` only, any other file (PDF, Guitar Pro…) opened with the system application (SPEC §5.9; #52). Their description, author and version are shared in `collab` mode (#28).
- Rename a title: essential (a title often starts with a temporary name); its folder only, identity by `nodeId`, followed by the other workspaces, the last rename published wins (SPEC §5.4, §5.5; #194).
- UI labels of checkout: EN "Get" / FR « Récupérer », EN "Get all" / FR « Tout récupérer » (SPEC §2).

## Decisions (2026-11-23, review of every open ticket of M1 to M3)
SPEC.md and the tickets are updated with every point; each changed ticket has a comment "Review of every open ticket (2026-11-23)".
- Move of a title ("Move…", #156): in `cloud` and `collab` libraries it is published and followed like a rename, found by its `nodeId` (SPEC §5.2, §5.4, §5.5; #194).
- Asset files have several writers: merged file by file against their base, never overwritten; a deletion on one side goes to the `.trash/` of the other unless changed there; a file changed on both sides keeps both (SPEC §5.5; #18, #19, #52).
- `Unsorted/` is never synchronized: it stays in the repository, handled by the creator while preparing (SPEC §5.5; #180).
- "Keep only these versions" (UI « Garder uniquement ces versions »): a selection of one or more versions; every other version goes to the trash. In `cloud` and `collab` libraries it applies to every member, any member can run it, on the workspace and the repository in one action, versions not checked out included; the other workspaces follow it, unpublished changes go to the local trash; a version in the repository trash is never published again (SPEC §3.0, §5.4, §5.5; #156, #197, #19, #38). Moving one version to the trash or renaming it stays reserved to its owner in `collab` mode (#26).
- Automatic synchronization (#161) runs in the background like the scan; checkout and publish started by the user, and the publish on quit, run in the foreground (SPEC §5.2, §5.5).
- "Get all" (« Tout récupérer ») checks out every version of one title (SPEC §2, §5.5; #18, #74); no checkout of several titles at once.
- While a collaboration folder is prepared, every action that is not work applies to the repository; the read-only state of the repository titles applies once the library is ready (SPEC §3.0; #181, #191).
- FR label of the asset files: « Fichiers joints » (SPEC §2; #52, #106).
- New activity kind `titleRenamed` (SPEC §5.9; #29).
- Collab entities: `member`, `titleMeta` and `versionMeta` are dropped; members live in `.library.json` (SPEC §6.2; #24).
- Budget B8, copies of the synchronization: checkout and publish at least 80 % of the throughput of a plain copy of the same files (60 % on the CI), measured on 100 GB of media; written in `docs/performance.md` by #199.
- New tickets: #197 (keep only these versions for every member), #198 (rebuild an unreadable sync state, split from #83), #199 (benchmark of the synchronization copies on 100 GB).
- Advised models raised to Opus: #149, #181, #191, #194, #198; reviewed by the largest model before merge: #70, #84, #197.
- Dependencies fixed: #74 is blocked by #18 (not the other way round); #184 after #121, #185 after #184, #150 after #186, #180 after #181 and #182; #110 after every interface ticket of M2.

## Decisions (2026-11-23, review of the Backlog)
SPEC.md and the tickets are updated with every point; each changed ticket has a comment "Review of the Backlog (2026-11-23)". The dependencies and advised models of M1 to M3 were checked against their plans: no gap.
- New title (#200, M2): no issue of M1 to M3 let a member start a song in the application. The minimal creation (level values, label, blank or template, known values) goes into M2, wave 3; #83 moves to wave 8. Patching the project values at creation (title, author, render metadata) stays in #14, a comfort feature after M3 (SPEC §5.6).
- Removing a library unregisters it: no file deleted anywhere, the confirmation gives the paths and leaves the cleanup to the user; in `cloud` and `collab` modes a checkbox frees the workspace like "Remove local copy" (SPEC §5.1; #46).
- Until #47, every library uses the provided status list (SPEC §5.9).
- #78 is folded into #160 and closed. #35 is split: player (#35), on-demand render (#201), render publication (#202).
- Backlog tickets realigned with the decisions since 2026-11-14: #53 (node files untouched by a mode change), #133 (no bulk checkout nor title status, foreground, nothing unpublished lost), #43 (`local` only, plus the free tree → layout conversion), #22, #34, #45, #58, #113, #134, #32 (macOS only).
- Backlog plan in waves with advised models: `progress/Backlog.md`. The tickets stay `needs-refinement` and get their implementation details when scheduled.
- Later the same day: #46 (unregister a library) moves to M2, wave 2, beside #191: the maintainer needs it for the M2 tests. Its sync state is removed with it (#107); the confirmation of a `cloud` or `collab` library says in plain words that unpublished changes stay only in the local folder and that using the library again needs an empty folder. The checkbox freeing the local folder moves to #21, with `releaseTitle` of #20 (SPEC §5.1).
