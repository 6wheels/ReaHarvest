# ReaHarvest — Specification

> Collaborative REAPER project manager.
> Technical name: `reaharvest` (repository, Dart packages prefixed `reaharvest_`, application identifier `reaharvest`).

> Reference document for implementation (Claude Code sessions).
> Code identifiers, technical file names and comments are in English.
> Items marked **[TO VALIDATE]** must be verified before implementing the related feature.
> The user interface is in French (i18n-ready): French UI labels are given as (UI: « … »).

---

## 1. Context and goals

A group of 3 musicians (only one with a technical profile) working on REAPER projects shared through a mounted Google Drive folder (streaming mode).

Problems to solve:
1. Diverging projects and manual reintegration of parts.
2. Massive duplication (media copied per person and per version, up to ×5).
3. Lack of discipline (folder structure not followed, duplication out of fear of deleting, loss of the "right" version).

Goals:
- Enforce an organization that requires no effort from non-technical users.
- Never duplicate media.
- Work on a local copy (performance, offline), the Drive acting as the shared repository.
- Share statuses, tasks, notes and lyrics between members.
- Also manage purely personal projects (local, or local with a cloud copy) in the same application, through libraries with different modes (§3.0).
- Fast, modern, intuitive application.

Platforms: **Windows and macOS first**, Linux secondary (must build and work, without dedicated optimization effort).
Public release considered in the long run: no hard dependency on Google Drive, on a cloud provider or on a specific backend.

---

## 2. Glossary

| Term | Definition |
|---|---|
| Library | Set of projects managed by the application, with a mode (local, local + cloud, collaboration), a layout and its folders. Has a `libraryId`. |
| Mode | Sharing and feature level of a library (§3.0). |
| Repository | Cloud counterpart of a library in `cloud` or `collab` mode: its root folder in the cloud (e.g. mounted Drive). Source of truth for project files. |
| Workspace | Local folder of a library, where titles are created, checked out and modified. |
| Group | Set of members sharing a library in collaboration mode. Has a `groupId`. Not to be confused with the "Artist" level of a layout. |
| Layout | Ordered sequence of levels that fixes the folder structure of a library (e.g. `artist/album/title`). See §3. |
| Level / tag | Element of a layout. Each level maps to a folder and to a tag (key + value) used for search and navigation. |
| Node | Folder matching a layout level. Has a stable `nodeId`. |
| Title (leaf node) | Last level of the layout, whatever its displayed name (title, scene…). Folder holding the media pool, the assets and the versions. Its `nodeId` serves as `titleId`. |
| Version | A distinct `.RPP` file in a title folder (variant of the title, e.g. another arrangement, or the version of another member). Has a stable `versionId`, an owner, a label. |
| Backup (UI: « Point de sauvegarde ») | Copy of a version at a given time, kept in the title's `.history/` folder: the history of a version. Distinct from REAPER's own backups (`.rpp-bak`, `Backups/`). |
| Media pool | `Media/` folder of the title, shared by all its versions, append-only. |
| Checkout (UI: « Récupérer ») | Copy repository → workspace. |
| Publish (UI: « Publier ») | Copy workspace → repository. |
| Release (UI: « Libérer ») | Deletion of the local copy of a title. |
| Asset | Auxiliary file of a title, outside the REAPER project (score, tab, image, PDF, text…). |
| Collab store | Storage of shared data in `collab` mode (statuses, tasks, notes, lyrics, asset metadata, activity). Two implementations: journal and PocketBase. |

---

## 3. Libraries, modes and organization

### 3.0 Libraries and modes

The user configures **one or more libraries**. Each has its own mode, layout and folders. All are presented in a **unified view**, filterable by library and by mode (§5.2).

| Mode | Folders | Features | Use case |
|---|---|---|---|
| **`local`** | Workspace only | Organization (layout), navigation, versions (with owner = local member), statuses, assets (files only), detail view, creation, opening in REAPER. No synchronization, no collaboration | Personal projects on a single machine |
| **`cloud`** (local + cloud) | Workspace + cloud repository | `local` + Checkout / Publish / Release, conflict detection (useful between several machines of the same user), cloud copy. Single user: no ownership check; forcing only to resolve a conflict (§5.5) | Personal projects copied to the cloud and accessible from several machines |
| **`collab`** (collaboration) | Workspace + shared cloud repository | `cloud` + members, version ownership and forcing, collab store (statuses, tasks, notes, lyrics, shared asset metadata, activity) | Group projects |

Rules:
- Work always happens **in the local workspace**; the repository is never a place to work in.
- **Mode change** possible at any time, through a wizard:
  - `local` → `cloud`: choice of the repository, initial publish;
  - `cloud` → `collab`: group creation, member invitation, adoption of versions (owner assignment), import of the statuses from the `.node.json` files into the collab store, then removal of the statuses from the `.node.json` files, with a message to the user (§5.9);
  - downgrades: `collab` → `cloud` (full export of the collab store kept in the repository, statuses written back into the `.node.json` files), `cloud` → `local` (the repository is left intact, simply detached).
- A given folder can belong to only one library (checked at configuration).

**Cloud providers.** The MVP relies on a **folder mounted or synchronized by the provider's client**: the application only sees a file system path. The following are therefore covered, with no specific code: Google Drive for desktop, Dropbox, OneDrive, iCloud Drive, Nextcloud, Syncthing, network share (NAS/SMB), rclone mount (Linux). Common constraints to handle:
- on-demand files (not present locally): never read or hash them needlessly, rely on size and mtime;
- provider-specific conflict copies (e.g. `file (1).RPP`, `conflicted copy`): detected and reported as anomalies, never silently adopted **[TO VALIDATE: naming patterns per provider]**.

Providers accessible through an API only (without a mounted folder) are **outside the MVP**. Repository access goes through a `RepositoryStorage` port whose MVP implementation is `MountedFolderStorage`, to allow other adapters later.

### 3.1 Layouts

The folder structure is defined by a **layout**: an ordered sequence of levels. Each level is a **placeholder targeting a tag**. The tag value is the folder name; it feeds search, filters and navigation in the interface.

Provided templates:
| Template | Levels (tag keys) | Displayed labels (UI, en / fr) |
|---|---|---|
| **Classic (recommended)** | `<artist> / <album> / <title>` | Artist / Album / Title — Artiste / Album / Titre |
| Project-oriented (no album) | `<artist> / <title>` | Artist / Title — Artiste / Titre |
| Film-oriented | `<project> / <chapter> / <scene>` | Project / Chapter / Scene — Projet / Chapitre / Scène ou titre |

Layout rules:
- The last level is always the **leaf node** (title): it holds `Media/` and the versions.
- A layout has 1 to 4 levels. Each level is a **token** (placeholder, written `<key>`, e.g. `<album>`): a language-independent tag key (technical identifier, in English), so that a configuration can be reproduced as is. Labels are never stored as plain text: the displayed label is the translation of the key (key → value per language). Keys of the provided templates are translated by the application; custom keys carry their own translations in `.library.json` (`labels`, by language code), with fallback to English, then to the key itself.
- All levels are mandatory. Each intermediate level has a reserved value (`_Unassigned`, UI: « Non classé ») for items that are not attached.
- **Known values** of the intermediate levels (e.g. classic: the artists, and the albums of each artist), stored in `.library.json` (`knownValues`, §6.5) as a tree that follows the levels; the leaf level (title) is never listed. The depth of a folder alone cannot tell an artist from a title placed too high: the scan uses the known values to recognize each level and to report precisely what is wrong (§5.8). They are asked when a library is added on a folder that already holds projects (§5.1) and during the migration (§5.8), pre-filled with the folders found at each depth: at least one value per intermediate level, each value of a non-last intermediate level having at least one child (`_Unassigned` allowed, e.g. a band without albums). A value created in the application (new title under a new artist or album) is added to the tree. They are editable in the library settings; a value still used by a folder cannot be removed. Not used by the free tree (§3.3).
- In `local` mode only, a layout can be replaced by the **free tree** (§3.3).
- The layout is defined **per library**, in `.library.json`. It is **frozen as soon as the first title is created** (derived from the presence of titles, not stored): changing it afterwards is a migration (outside the MVP).
- Each layout declares a **tags → render metadata mapping** (e.g. classic: `artist` → artist, `album` → album, `title` → title). The mapping can be modified by the user.

### 3.2 Physical structure

Example with the classic template:
```
<libraryRoot>/                   # repository root (modes cloud/collab) or workspace root (mode local)
  .library.json                   # libraryId, mode, layout, known values, statuses, collab settings (cf. §6.5)
  .collab/                        # collab mode: joined members (cf. §5.1), journal store (cf. §6.3)
  .migration/                     # migration inventories, original projects and reports (cf. §5.8)
  <artist>/
    .node.json                    # { nodeId, level: "artist" }
    <album>/
      .node.json                  # { nodeId, level: "album" }
      <title>/                    # leaf node
        .node.json                # { nodeId, level: "title", status, versionStatuses } (cf. §5.9)
        Media/                    # shared, append-only pool
        Renders/                  # default render folder; published in phase 3 (cf. §5.3)
        Assets/                   # attached files: scores, tabs, images, docs (cf. §5.9)
        <any name>.RPP            # versions (flat list)
        .history/                 # backups of the versions (history), cf. §5.4
        .trash/                   # deleted versions and assets
```

Rules:
- Scaffolding: the library initialization only writes `.library.json`. Creating or adopting a title creates its folders (`Media/`, `Renders/`, `Assets/`, `.history/`, `.trash/`) and its `.node.json`.
- Nodes: a layout folder is a node (and gets a `.node.json` on scan) only if an `.RPP` lies in it or below it, outside the reserved title folders (`Media/`, `Renders/`, `Assets/`, `Backups/`, `.history/`, `.trash/`), which are never nodes. A title whose versions are all in its `.trash/` or `.history/` stays a title. A `.node.json` found in a folder that is not a node is neither used nor deleted: it is listed in the "To sort" page, where the user can delete it after confirmation (the statuses it stores are lost). Unreadable application files are listed there too.
- In `cloud` and `collab` modes, the workspace mirrors the repository tree for checked-out titles. The repository's `.library.json` is authoritative; the workspace keeps a copy of it to work offline.
- Application files and folders (`.library.json`, `.node.json`, `.collab/`, `.migration/`, `.history/`, `.trash/`) start with a dot, and are also given the hidden attribute on Windows when the application creates them. They stay reachable from the application (title card, detail view). Their subfolders take no prefix (e.g. `.collab/exports/`). Validated (2026-11-07, Google Drive for desktop, streaming mode, Windows): dot-prefixed files and folders, with or without the hidden attribute, and hidden folders without a dot are all synchronized; the hidden attribute is kept locally after synchronization. Other cloud clients **[TO VALIDATE]** (e.g. Box Sync is reported to ignore dot-prefixed files).
- `.RPP` files in `.history/` and `.trash/` are never listed as versions, nor in the "To sort" or "To adopt" sections, nor treated as duplicates (§4.2). They are not shown in the main library view; they enrich the title card and the detail view (history, trash).
- The **path** defines the tag values. `.node.json` files only carry **stable identifiers** and the level, so that moving or renaming a folder does not break collaborative data.
- Any folder or `.RPP` whose position does not match the layout appears in the "To sort" section (UI: « À ranger », §5.2).
- The name of a `.RPP` is free: the identity of a version does not depend on its name (cf. §4.2).
- Extension comparisons are **case-insensitive** (`.rpp` and `.RPP` coexist in real projects).
- Files excluded from any synchronization and from indexing (surveyed on a real repository):
  - REAPER: `*.reapeaks`, `*.rpp-bak` (including timestamped ones: `<name>-YYYY-MM-DD_HHMM.rpp-bak`), the title's `Backups/` subfolder (timestamped backups), `*.rpp-undo`, `*.rpp-prox`, `*.reapindex`. REAPER backups remain a **local** safety net: shared history is provided by the backups in `.history/` (§5.4) and by the cloud provider's history;
  - system: `.DS_Store`, `._*` (macOS AppleDouble), `desktop.ini`, `Thumbs.db`;
  - cloud provider: Google Drive shortcuts (`*.gdoc`, `*.gsheet`…).

### 3.3 Free tree (`local` mode only)

Option for users who do not want to reorganize their folders: the application **leaves the folder tree intact**. The interface nevertheless recommends a frozen layout, and the migration wizard (§5.8) allows switching to one later.

Principle: the library watches **one or more root folders** and behaves like a large indexed library. The topmost folder containing at least one `.rpp` is a title; all the `.rpp` files below it, at any level, are its versions.

Rules:
1. **Tags**: derived from the names of the parent folders, relative to the root; usable in search, without per-level filters.
2. **Title identity**: a `.node.json` is written in each title folder (stable identity, eases a later migration to a layout). This is the application's only write in the tree outside explicit actions.
3. **Project files untouched**: `.rpp` files are never modified nor moved, except an explicit deletion (rule 5). No `EXTSTATE`, hence no `versionId` nor owner: a version is identified by its path relative to the title folder (a rename outside the application loses its status). No "To adopt" section.
4. **Media pool**: no `Media/` constraint, no path normalization, no "To sort" section. Only missing media are reported.
5. **Creation, deletion**: new titles created in a folder chosen by the user. Deletion (explicit, confirmed) moves the `.rpp` to a `.trash/` placed in its folder, created on first use. No backups (`.history/`).
6. **Nested folders** containing `.rpp` files, on one or several levels (real case: `title/member/v2/…`): they belong to the title of the topmost folder, and their `.rpp` files are its versions.
7. **Configuration**: watched roots and the library configuration are stored in the application configuration, not in the folders. A root located under an already declared root (in any library) is refused, to avoid duplicates.
8. **Mode change**: switching to `cloud` or `collab` is impossible without a prior migration to a layout.

---

## 4. File-side data model

This data does **not** depend on the collab store: the application must work (navigation, versions, synchronization) even without an available store.

### 4.1 Nodes and title
- `nodeId`: ULID generated on creation or adoption of each node, stored in its `.node.json`.
- The `nodeId` of the leaf node serves as `titleId`.
- The tags of a title (e.g. `artist=X`, `album=Y`, `title=Z`) are derived from its path and indexed.

### 4.2 Version
Metadata stored **in the `.RPP`**, through a dedicated `EXTSTATE` section named `ReaHarvest` (kept by REAPER on every save):
- `versionId` (ULID)
- `owner` (memberId) — mandatory in **all modes**, from milestone A (in `local` and `cloud` modes: the local member), to avoid any later change of the model
- `label` (free text, e.g. "chorus B")

The date is the file modification date.

Observed format (REAPER 7.84, `test/fixtures/reference-metadata.rpp`): `<EXTSTATE` chunk at the end of the root `<REAPER_PROJECT` chunk, after `<EXTENSIONS`, one subchunk per section, one `KEY value` line per key, section and key in uppercase:
```
  <EXTSTATE
    <REAHARVEST
      VERSIONID 01JC...
      OWNER 01JC...
      LABEL "chorus B"
    >
  >
```
Rules validated by test (`SetProjExtState` then save, REAPER 7.84):
- REAPER puts section and keys **in uppercase** and **sorts them alphabetically**;
- an empty value is not written (absent key = deleted key);
- simple value: raw (`VERSIONID 01JC…`); with spaces: between `"` (`LABEL "chorus B"`); Unicode written as is in UTF-8;
- value containing `"`: between `'` (`DQUOTE 'say "hi"'`), same delimiter rule as project lines (§5.6);
- value containing all three delimiters (`"`, `'`, `` ` ``) or a line break: base64 subchunk `<BIN KEY` / base64 line(s) / `>`.

The reader handles all these forms. The writer emits: raw if no space or delimiter, `"…"` if the value contains neither `"` nor a line break, `<BIN` otherwise (form accepted by REAPER, simpler than reproducing the delimiter cascade). Keys always written in uppercase, like REAPER.

Validated by test (hand-written file, opened by REAPER, values read back through `GetProjExtState`): REAPER correctly reads raw values, `"…"`, `<BIN` base64 and Unicode; key lookup is case-insensitive (a key written `owner` is read through `OWNER`). If `<EXTSTATE` is absent, the writer inserts it at the end of the root chunk; if the section is absent, it adds it to the existing `<EXTSTATE` chunk.

Automatic detection during the scan:
| Case | Detection | Behavior |
|---|---|---|
| Rename | Same `versionId`, new name | Transparent tracking; warning when the rename was made outside the application |
| Manual duplication (*Save As*) | Two files with the same `versionId` | Offer to make it a new version (new ID, owner = current user) |
| Unknown file | `.RPP` without `versionId` | "To adopt" section (UI: « À adopter »): choice of owner and label, metadata written |

Versions form a **flat list** (no tree, no parent version).

### 4.3 Media
- Any media referenced by a version must reside in the title's `Media/`, as a **relative path**. Media referenced through an absolute path outside the title folder are tolerated but reported: they cannot be shared in `cloud` and `collab` modes until fixed manually in REAPER (§5.5).
- Observed references: `<SOURCE WAVE` / `<SOURCE MIDI` … `FILE ".\audio-files\x.wav"` or `FILE "audio-files\x.wav"`, `\` separator on Windows. Existing projects use `RECORD_PATH "audio-files"`: the migration (§5.8) rewrites these paths to `Media/` **[TO VALIDATE: reading by REAPER macOS of a relative path with `\`]**.
- The pool is **append-only**: a published file is never modified or deleted, except on explicit purge (cf. §5.4).
- Name collision on publish (same name, different content according to the hash): rename with a suffix and rewrite of the references in the `.RPP`.
- MIDI embedded in the `.RPP` (the drummer's case) does not generate media.

---

## 5. Features

### 5.1 Configuration
- **Libraries** (0..n), each with: display name, mode (§3.0), workspace root, repository root (`cloud` and `collab` modes), layout, optional templates folder specific to the library.
- Adding a library: creation of a new one (choice of mode and layout) or attachment to an existing repository (reading its `.library.json`, case of a member joining a group). When the folder already holds projects and the layout has intermediate levels, the form asks their **known values** (§3.1), pre-filled with the folders found at each depth, before the first scan; an attached library keeps the values of its `.library.json` (asked once if it has none).
- **Removing a library** from the application, whatever its mode, after confirmation:
  - removed: the library from the application configuration and from the index; in the local folder (workspace, or free tree roots), the application files `.library.json`, `.node.json` and `.collab/`. The confirmation states that the statuses stored in the `.node.json` files are lost;
  - kept: all REAPER and audio content (`.RPP`, `Media/`, `Renders/`, `Assets/`, REAPER backups, peaks…), `.history/` and `.trash/` (project data), and the `ReaHarvest` `EXTSTATE` section of the `.RPP` files (version identity, reused if the folder is added again);
  - in `cloud` and `collab` modes, the repository is never touched. Deleting the application data from the repository is a separate critical action (outside the MVP);
  - goal: the folder can be added again later, with any layout, without leftovers from the previous library.
- First-run wizard: technical settings first (member name, REAPER executable and resource folder, templates folder, peaks preference check), then three choices for the library (also offered later by "Add a library" in the settings):
  - **Join my band's library** (UI: « Rejoindre la bibliothèque de mon groupe »): choice of the repository folder (e.g. the Drive folder), reading of its `.library.json`.
    - Collab repository: the members declared in `.library.json` (§6.5) and **not yet joined** are listed; the user picks who they are (UI: « Qui suis-je ? »), and the local identity takes that `memberId`. Then choice of the workspace, which must be an **empty** folder (a non-empty folder is refused in the MVP). Joining writes `.collab/<memberId>/member.json` (one writer per folder, no cloud synchronization conflict); a member who has this file is no longer offered to the others. The claim is checked again just before writing. Then offer to check out titles (§5.5).
    - Folder without `.library.json`, or not in `collab` mode: clear message (the folder is not set up yet, ask the person who manages it); nothing is written.
  - **Organize my band's folder** (UI: « Organiser le dossier de mon groupe »): migration wizard (§5.8).
  - **Create a new library**.
- **Portable mode**: a `settings.json` and/or an `index.sqlite` placed next to the executable are used first, instead of the user application data folder. Used by the demo mode and local tests, and to run two members on one machine (two copies of the application folder).
- Local member identity (`memberId`, display name), created on first run and used in all modes (version owner). In the MVP, one identity per installation. Later (outside the MVP): one identity shared by all the machines of a user, linked through a confirmed email, each machine identified by its own client identifier.
- Path of the REAPER executable and of the REAPER resource folder (defaults per OS). Executable detection: first the location reported by the OS (Windows: default value of `HKLM\SOFTWARE\REAPER` = install folder, validated; macOS: Spotlight `mdfind "kMDItemCFBundleIdentifier == 'com.cockos.reaper'"`; Linux: `which reaper`), then the usual install locations (Windows: `%ProgramFiles%\REAPER (x64)`, `%ProgramFiles%\REAPER`; macOS: `/Applications/REAPER.app`, `/Applications/REAPER64.app`, `~/Applications/REAPER.app`; Linux: `~/opt/REAPER/reaper`, `/opt/REAPER/reaper`). Resource folder: `%APPDATA%\REAPER`, `~/Library/Application Support/REAPER`, `~/.config/REAPER`. macOS and Linux values **[TO VALIDATE]**.
- Project templates folder (default: `ProjectTemplates` in the REAPER resource folder).
- Check of a recommended REAPER preference, with a non-blocking warning: peaks centralized outside the project (avoids thousands of `.reapeaks` in the workspace). Validated keys: `altpeaks` bit `0x1` = "Store all peak caches (.reapeaks) in alternate path" (General > Paths), `altpeakspath` = path.
- No check of REAPER backup options: all backups (`.rpp-bak`, timestamped, `Backups/`) are excluded from synchronization (§3.2), whatever option is chosen.

### 5.2 Navigation
Principle: **no imposed tree navigation**. Titles are reached first through search and filters, to minimize the number of clicks.

Main window: the application opens directly on the library. Clean but functional layout, **no side navigation**: search bar at the top, filter chips below it, then the titles (cards by default). Settings are reached through a **gear icon at the top right** and open as a **popup over a blurred backdrop** (glass pane over the rest of the application), with an opening and closing animation.

- **Main search bar**, always visible and focused on startup:
  - instant, typo-tolerant search, served by the local index;
  - covers tag values, version names, labels, owners and, in `collab` mode, notes and lyrics.
- **Display modes**, chosen by the user and remembered:
  - **cards** (default view): **square** cards, like a record sleeve. Generated "aurora borealis" visual, with colors derived from the `titleId` (stable for a given title, different between titles). Content: title, number of versions, tempo (BPM), last modification date, status as a progress trail (below), tags; sync state of the title in `cloud` and `collab` modes (not published, not checked out, up to date, locally modified, remotely updated, in conflict, cf. §5.5); later also version owners. Quick actions shown on hover or selection: "Open in REAPER" (latest version of the current member, else the latest version; in `collab` mode, opening another member's version asks for a confirmation), "open detail", and a "…" menu (new version, backup point, change status, show in the file explorer);
  - **list**: dense table, sortable by column, status as a progress trail; the card quick actions are shown at the end of a row on hover;
  - **tree**: grouping by layout levels (e.g. Artist → Album → Title), offered as one view among others.
- **Combinable filters** (chips or side panel):
  - tags, one filter per layout level (e.g. `artist`, `album`); `_Unassigned` (UI: « Non classé ») is a value like the others. Libraries with different layouts expose their own filters; a common tag key (e.g. `artist`) is filtered across all of them. A filter offering a single value is hidden;
  - library and mode (`local`, `cloud`, `collab`);
  - source: **repository (cloud)**, **local**, or both (`cloud` and `collab` modes);
  - sync state: not checked out, up to date, locally modified, remotely updated, in conflict;
  - status (all modes, cf. §5.9);
  - version owner;
  - missing plugins.
- Filters and search are combined and kept between sessions; **saved views** (e.g. "My titles in progress", UI: « Mes titres en cours ») are possible.
- Access to a title's versions from any display mode, without changing view:
  - **overview** (UI: « Aperçu »), dock at the bottom of the library opened by a click on a card or row (no double click): crucial data only (identity: name, parent tags, library, status, BPM, last modification; alerts: missing plugins, duplicated or not adopted versions, leading to the detail; the 3 most recent versions, each with "Open in REAPER"). It can be **pinned**: opaque, the titles end above it, it stays open and follows the selection; unpinned, it floats over the titles with an acrylic background (blur and slight transparency, a single blur clipped to the dock) and closes on a click outside. The pinned state is kept between sessions;
  - **title detail**: full page over the library, opened by Enter in the search bar (title of the overview) or the "open detail" icon (same icon on the card and in the overview). Back to the library, with search, filters and scroll kept, through the back button, Escape or the mouse back button. Header: large title name with the first parent tag (e.g. artist) on the same line in a smaller font, the other tags (e.g. album) and the library below; on the right, length, BPM, number of tracks and number of items of the selected version (indexed at scan, like the tempo); below, the status progress trail across the width. Master-detail layout: versions on the left, selected version on the right (details, adoption, actions, missing plugins, duplicates, history; then §5.3 data). Title assets and trash come as title-level tabs.
- **Status progress trail**: one segment per status, passed ones green, the current one orange, the next ones grey; "done" reached shows the whole trail green. Only the current status shows its label; hovering the trail reveals the other labels, with an animation. A status outside the list is shown as a plain label. Display only (status changes come with the title actions).
- "To sort" section (UI: « À ranger »): `.RPP` or folders outside the convention, with guided move. Opened from its counter in the filter bar, as a page over the library (same back navigation as the title detail). Issues are grouped by kind, with a counter per kind. The kinds fixed in batch (§5.8 step 4) have a checkbox on each card, a "select all" box and a counter of the selected items per section; "Fix…" previews the selected items of its section, or all of them when none is selected. The selection is kept through a rescan for the items still there.
- "To adopt" (UI: « À adopter », cf. §4.2): a filter (titles having a version to adopt), with its counter of titles in the filter bar; adoption is done in the title detail, on the selected version. The card, the overview and the title detail show the number of versions to adopt of the title.
- **Background tasks zone** at the bottom of the application (following the theme; the overview dock sits above it): running tasks with progress and cancellation, finished tasks with their outcome, expandable list.
- **Reports**: every long action (scan, migration fix, checkout, publish, purge…) produces a report **structured in sections by kind of problem or conflict** (done, skipped, warnings, errors; each item with its path), shown in a popup at the end and reachable from the tasks zone. Reports are also written to the log (§8).

### 5.3 Version detail view
Parsing of the `.RPP`, without REAPER:
- top-level tracks (depth 0), with name (`NAME`) and color (`PEAKCOL`, bit `0x1000000` = custom color). Depth computed through `ISBUS <type> <delta>` (validated on the corpus): `ISBUS 0 0` normal track, `ISBUS 1 1` folder start, `ISBUS 2 -n` last track of a folder, closes `n` levels;
- plugins used per track, deduplicated. Observed forms: `<VST "VST3: Name (Vendor)" file.vst3 0 "" uid{guid} ""`, `<VST "VSTi: …" file.dll …`, `<VST "VST: …" file.dll …`, `<JS relative/path ""`. CLAP and AU absent from the corpus **[TO VALIDATE]**;
- **plugins missing** on the machine, by comparison with the REAPER plugin caches, discovered by pattern (`reaper-vstplugins*.ini`, `reaper-clap-*.ini`, `reaper-auplugins*.ini`) rather than by exact name:
  - VST (validated on Windows, `reaper-vstplugins64.ini`): `[vstcache]` section, lines `file=timestamp,uid,Name (Vendor)`; in the key, every character of the file name other than a letter, digit, `.` or `_` is replaced by `_` (`"TDR Kotelnikov.vst3"` → `TDR_Kotelnikov.vst3`, `SS-11X.vst3` → `SS_11X.vst3`, `"Darkglass Ultra(x64).dll"` → `Darkglass_Ultra_x64_.dll`); also merged: other `reaper-vstplugins*.ini` files (32-bit). Shell plugins (e.g. Waves) have a `file=timestamp,0,<SHELL>` line plus one `file<id=…` line per sub-plugin; matching is done on the shell file only. Lines with only a timestamp (no plugin name) are treated as not installed;
  - JS (validated, `reaper-jsfx.ini`): lines `NAME relative/path "JS: Name"` (path quoted when it contains spaces); `REV` lines are ignored;
  - formats without validated cache (CLAP, AU, LV2, DX) are reported with an unknown status, never as missing. CLAP (all OS), AU (macOS) and LV2 (all OS, mostly Linux) are to be covered (#40); DX is not covered (32-bit REAPER only, obsolete);
  - CLAP, AU, macOS and Linux names **[TO VALIDATE]**;
- tempo, time signature, length, sample rate, REAPER version;
- owner, label, modification date;
- referenced media, with local presence and size.

**Listening to a sample and renders** *(outside the MVP — phase 3)*
- A faithful preview **without rendering is impossible**: the final sound depends on plugins, automation and routing, which only REAPER can compute. A simple mix of the raw media files would be misleading; it is not retained.
- **Existing renders**: the application reads the render folder defined in the project (`RENDER_FILE` line, resolved relative to the title folder), lists the audio files present (date, length, format) and plays them in a built-in player (play, position, loop).
- **On-demand render** (optional): background render launched through the REAPER command line (`-renderproject`), with the project's render settings. Constraints: REAPER installed, plugins present on the machine, duration proportional to the song.
  Validated (Windows, REAPER 7.84, REAPER already open): `reaper.exe -renderproject <file>.rpp` launches a separate instance that renders then exits (exit code 0), without disturbing the open instance; a relative `RENDER_FILE` is resolved from the project folder. The render instance rewrites `REAPER.ini` when it exits, with identical content. Residual risk: a preference modified in the main instance during a render could be overwritten by this rewrite (lead: `-cfgfile` option with a copy of `REAPER.ini`, to be evaluated in phase 3).
  Observed `RENDER_FILE` forms: `""` (project folder), relative folder (`.\render`), relative file path (`".\render\Drums 3.mp3"`) or absolute (`"C:\Users\…\x.mp3"`, often from another machine). Combined with `RENDER_PATTERN` (e.g. `$project-ending`) when it denotes a folder.
- Default convention for new projects (from the MVP): render folder `Renders/` in the title folder (cf. §5.6).
- **Render publication**, two independent targets, enabled at repository level and overridable per title:
  - **repository**: `Renders/` published with the title, so that members can listen without REAPER or plugins. Option can be disabled to save Drive space;
  - **export folders** (0..n): copy of renders to a configured external folder (e.g. Drive folder synchronized to a streaming server such as Navidrome). Each target defines a path and name pattern based on the layout tags (e.g. `{artist}/{album}/{title}.{ext}`), accepted formats and a replacement policy (overwrite, version).
  - Metadata embedded in the files comes from the tags → render metadata mapping (§3.1); the application does not rewrite audio tags **[TO VALIDATE: whether the metadata written by REAPER is sufficient for Navidrome indexing]**.

### 5.4 Version management
Actions performed from the title detail (§5.2).
- **Create a version** (a new, distinct `.RPP`): blank, from a template or by duplicating an existing version. New ID; the owner is the current user by default. In `collab` mode, the owner can be chosen at creation (e.g. a version prepared for another member) or changed afterwards by its current owner only. The file name matters (it identifies the version for the members): pre-filled as `<title> - <label>.RPP`, followed by the owner's name when the owner is not the current user, and editable.
  - Blank: REAPER's default template for new projects when one is set, otherwise a minimal project (`<REAPER_PROJECT` chunk only, REAPER fills in its defaults on save). Validated (REAPER 7.85, Windows): the minimal project (root header, `RECORD_PATH`, `RENDER_FILE`, `EXTSTATE`) opens without error, records into `Media/` (relative `FILE "Media\…"`), and keeps the render folder and the version metadata when saved. Validated (REAPER 7.84, Windows): Preferences > Project > "Default template for new projects" is stored in `REAPER.ini` as `newprojtmpl=<path>`, empty when unset, relative to the resource folder when the template is inside it (`newprojtmpl=ProjectTemplates\default.rpp`). macOS and Linux **[TO VALIDATE]**.
  - Blank or from a template: version metadata written, record path `Media`, render folder `Renders`; the other §5.6 values are filled in by project creation only. Duplicate: same content, new version metadata.
- **Rename** the file and/or modify the label. A rename made in the application is tracked through the `versionId`, and published as a rename of the remote file, together with any modification of its content (§5.5).
- **Delete**: move to `.trash/`.
- **Purge**: permanent deletion from `.trash/`, with confirmation. Then, list of pool media referenced by no version nor backup (`.history/`; the trash does not count), then purge on confirmation. Nothing is listed if a project cannot be read. Purging unreferenced media only applies to `Media/`: `Assets/` is never concerned. Purge acts on the workspace only; the repository follows through the synchronization of the mode (§5.5). Sensitive, destructive feature.
- **Back up a version** (UI: « Créer un point de sauvegarde »): copies the `.RPP` of the version into `.history/` (flat), named `<version name> <yyyy-MM-dd HHmmss>.<ext>` (` (n)` suffix on a name clash). The version itself is unchanged. Backups are linked to their version by the `versionId` of the copy (robust to renames).
- **Paths of backups**: the copy has its relative paths rebased so that it opens in REAPER from `.history/` (`FILE "Media\x.wav"` → `"..\Media\x.wav"`, `RECORD_PATH "Media"` → `"..\Media"`, empty record path → `".."`, relative `RENDER_FILE` → `..\…`); absolute paths are left as is. Restoring rebases them back to the title folder.
  Validated (REAPER 7.85, Windows): a project in `.history/` with `..\` paths opens without missing media, records into the title's `Media/` and renders into its `Renders/`. But REAPER resolves a relative media path against the record path first and does not normalize it: on each save, an existing media reference grows by one `..\Media\` (`..\Media\kick.wav` → `..\Media\..\Media\kick.wav`), still valid. Hence the application normalizes the paths of a backup before opening it in REAPER (UI: « Ouvrir dans REAPER »), and on restore. Versions in the title folder are not affected (`Media\Media\x` does not exist, so REAPER falls back to the project folder).
- **History**: browsing, opening in REAPER and restoring the backups of a version (manual backups, and versions overwritten by a forced publish, §5.5). Restoring first backs up the current state of the version, then replaces its content.

### 5.5 Synchronization
**Checkout**
- By default: full title folder (all versions, `Media/`, `Renders/`, `Assets/`, `.history/`, `.trash/`).
- Options (outside the MVP): exclude versions (media referenced only by the excluded versions are then not copied) or `Renders/`. User preference per library or per title, persisted client-side.
- Local storage of the hash (cf. §7.1) of each checked-out file, used as the comparison base.

**Publish**
1. Media normalization:
   - media referenced through a path relative to the title folder but outside `Media/`: moved into `Media/`, then the references are rewritten (strong non-regression test required, so as not to break projects);
   - media referenced through an absolute path (outside the title folder, other machine): left as is; warning stating that a manual action in REAPER is needed for the project to be shared.
2. Copy of media missing from the remote pool (comparison by name + size + hash).
3. For each modified `.RPP`:
   - **conflict** if the remote hash differs from the base hash: refusal, conflict display, user choice (keep remote, publish as new version, or force);
   - **version of another member**: refused by default, with an offer to save it as a new version under one's own name. Exception: a version never published (absent from the repository) can be published by the member who created it, whatever its owner (e.g. a version prepared for another member);
   - **forcing**: overwrites the remote version with the local one, after explicit confirmation and a warning when a conflict was detected. In `collab` mode it bypasses the ownership check or the conflict; in `cloud` mode, the conflict only. The overwritten remote version is first backed up into `.history/`; in `collab` mode, an activity event is sent to the owner.
4. Update of the base hashes; in `collab` mode, emission of an activity event ("X published Y", UI: « X a publié Y »).

**Release**
- Refused if local modifications are not published, unless explicitly confirmed.

**Other members' versions locally**: readable, openable, importable (later phase), but not publishable without forcing.

### 5.6 Project creation
- Input of a value for each layout level (with autocompletion on existing values; folders created if needed), choice of the template and of the version label.
- Copy of the template, then filling in of:
  - project title and author;
  - render metadata, according to the layout's tags → metadata mapping (§3.1);
  - render file name pattern;
  - relative record path `Media`;
  - relative render folder `Renders`;
  - version metadata (§4.2).

  Lines validated on the corpus (root chunk):
  - `TITLE <value>`, `AUTHOR <value>`;
  - `<NOTES 0 2` then one `|text` line per note line, then `>`;
  - `RECORD_PATH "<primary>" "<secondary>"`;
  - `RENDER_FILE <path>`, `RENDER_PATTERN <pattern>` (REAPER wildcards: `$project`, `$title`, `$author`…);
  - `<RENDER_METADATA` then one `TAG <SCHEMA:FIELD> <value>` line per field (e.g. `TAG ID3:TIT2 $title`, `TAG ID3:TPE1 $author`, `TAG VORBIS:ARTIST $author`), then `>`.

  - "Metadata" checkbox of the render dialog (actual writing of the metadata): bit `512` of `RENDER_STEMS`; the writer enables it as soon as it writes tags.

  Validated (REAPER 7.84, Windows): a project patched by the writer (title, author, notes, `RECORD_PATH`, `RENDER_FILE`, `RENDER_PATTERN`, `<RENDER_METADATA`, `FILE "Media\…"`, `EXTSTATE`) opens without error, relative media are resolved, all values are read, then kept identical when REAPER saves (it only reorders `TITLE` before `AUTHOR` and puts `RECORD_PATH` between `"`).

  Values are quoted only when needed. Validated quoting: raw without space (`TITLE coffeetime`), `"…"` with spaces (`TITLE "Dancing on a line"`), `'…'` if the value contains `"` (`TITLE 'My "quoted" title'`), then `` `…` `` if it also contains `'`. The writer reproduces these rules; the reader accepts all three delimiters.
- Immediate opening in REAPER.

### 5.7 Opening in REAPER
- Opening in the existing instance (`-nonewinst` on Windows, validated: `reaper.exe -nonewinst <file>.rpp` opens the project in a new tab of the already open instance, without launching a second one; if REAPER is closed, it starts it) **[TO VALIDATE: macOS equivalent]**. Implemented without validation: macOS `open -a <REAPER.app> <file>.rpp`, Linux `reaper -nonewinst <file>.rpp`.
- Any modification of a `.RPP` by the application (adoption, path rewrite, track import) requires the project to be closed in REAPER: warning and confirmation in the MVP.
  - `REAPER.ini` (`projecttabs`, `projecttab1..n`) is not reliable: it is only rewritten occasionally and keeps stale entries (observed: `projecttabs=1` with `projecttab2..9` still present).
  - MVP: if a REAPER process is running, warning and confirmation. Detection: Windows `tasklist /FI "IMAGENAME eq reaper.exe"`, macOS and Linux `pgrep -ix reaper` **[TO VALIDATE on macOS and Linux]**. Later: REAPER companion script publishing the list of open projects.
  - Validated: REAPER **does not lock** the open `.rpp` (exclusive write open and rename succeeded while the project was open). No lock-based detection is possible, and REAPER will overwrite the modification on the next save of the project: the warning must say so clearly.

### 5.8 Adoption of existing projects (migration)
MVP milestone M1 (§9). The migration organizes a folder **in place**, through the `RepositoryStorage` port: for the band, directly the shared Drive folder (first a copy holding a sample, then the real folder, e.g. `proaudio/reaper/projects/<group>/<title>[/<member>]`); later, for `local` libraries, a local folder first (then published, `local` → `cloud`). A folder that is not migrated can be kept as a free tree (§3.3, `local` only).

Flow (wizard "Organize my band's folder", §5.1):
1. Choice of the folder and of the target layout, declaration of the **known values** of the intermediate levels (§3.1: e.g. the artists and their albums, pre-filled with the folders found at each depth, the user checks or corrects them), declaration of the members (§6.5).
2. **Inventory** before the first change (relative path, size, XXH3 hash of every file), stored in `.migration/<timestamp>/`. Hashing reads every file: on a streaming cloud folder, the whole folder is downloaded once (background task, cancellable, resumable from the already hashed stamps).
3. Scan against the layout. Every inconsistency is an **issue**, listed by kind in the "To sort" page (§5.2) with a counter per kind:
   - project too deep (e.g. `<title>/<member>/x.rpp`, or a status subfolder such as `<title>/mix/x.rpp`) or too shallow (`.rpp` at an intermediate level), folder outside the layout;
   - level recognition through the known values (§3.1): unknown folder at an intermediate level holding projects = title placed too high (target `<parent>/_Unassigned/<folder>`); folder named after a known value of another level = skipped or misplaced level (target given by the tree, e.g. an album found at the artist level goes under its artist); other unknown folder = value to declare or folder to move. Each issue names the expected level and the proposed target;
   - media outside `Media/` (relative), media referenced through an absolute path, missing media, `RECORD_PATH` other than `Media` (e.g. `audio-files`), `RENDER_FILE` forms (§5.3);
   - other files to move into `Assets/`, or blocked because a project references them;
   - versions not adopted, duplicated `versionId` (§4.2);
   - cloud provider conflict copies (e.g. `x (1).rpp`), reported only.
4. **Fixes in the interface**, each with a preview (dry run) and a report (§5.2):
   - move of a folder or project to its layout position (the target proposed from the known values), `_Unassigned` value for a missing level (e.g. the album);
   - **merge** when the target folder already exists (e.g. the same song found at the root and under its album), announced in the preview: each entry of the moved folder goes to the same place in the target; subfolders present on both sides (artist, album, title, `Media/`…) are merged recursively; any other name collision gets a free name (`name (2).ext`) and the references of the moved projects are rewritten to follow it, so the projects of both titles become versions of one title (identical media are merged with the pool, see below). Node files are merged: version statuses are added, the target's title status wins (the dropped one is reported). What is left of the moved folder (its node files, empty folders) goes into `.migration/<timestamp>/merged/`. No merge of a folder into itself (paths equal ignoring case) or into its parent or child;
   - **member subfolder** (`<title>/<member>/…`): its projects are moved up into the title, owner = that member, names de-duplicated;
   - **status subfolder** (`<title>/<status>/…` or `<title>/<member>/<status>/…`, e.g. `mix`, `demo`): reported as projects too deep; its projects are moved up into the title, with a version status (§5.9) deduced from the folder name through a proposed mapping to the statuses of the library, confirmed by the user (unmatched names: no status, folder name kept in the report); names de-duplicated;
   - media (audio, video, MIDI, subprojects `<SOURCE RPP_PROJECT` with their `.rpp-PROX`) moved into `Media/`, references rewritten, `RECORD_PATH` set to `Media` (targeted patch, §7.3); per-member media merged into the single pool; identical media (same hash) share one pool file and the duplicate is **moved** into `.trash/`; name collision: suffix and reference rewrite;
   - **any other file** (neither a project, nor a media, nor a REAPER file such as `.rpp-bak`, `Backups/`, peaks) is moved into `Assets/`. Before moving it, the application looks for its name in the projects of the title, in plain text and in the decoded base64 plugin states: a referenced file (e.g. impulse response, sampler file) is not moved automatically, it is reported for a manual decision;
   - fix impossible (media not found, absolute path from another machine): reported, `.rpp` left intact;
   - adoption of the `.RPP` files in batch, owner chosen among the declared members (deduced from the member subfolder when there is one);
   - warning before any `.rpp` rewrite when REAPER is running (§5.7).
5. **No file is ever deleted.** Every change is a move or a targeted rewrite; before rewriting a `.rpp`, its raw original is copied into `.migration/<timestamp>/`. After each batch of fixes and at the end, the inventory is checked: same number of files, every original hash still present, every move accounted for. Any gap is reported and blocks the conversion.
6. **Conversion to a collab repository**: final inventory check, then the `collab` block (`groupId`, store `journal`) is written into `.library.json`. The folder is now the repository; the user joins it with an empty workspace, like the other members (§5.1).

### 5.9 Statuses, assets and collaboration
Statuses and asset files are available in **all modes**; the other features require the `collab` mode and the collab store (§6).
- **Status** per title and per version. Available in **all modes** (key feature):
  - the list of statuses is free, defined per library in `.library.json` (`statuses`, §6.5), started from 2 or 3 provided templates (e.g. `idea`, `writing`, `recording`, `mixing`, `done`). Like layout levels (§3.1), template values are language-independent keys translated by the application; custom values carry their own translations (`labels`);
  - `local` and `cloud` modes: stored in the title's `.node.json` (`status`, and `versionStatuses`: map `versionId` → status; in free tree, keyed by the path relative to the title folder), synchronized with the title in `cloud` mode. Never stored in the `.RPP` (REAPER would overwrite it on the next save of an open project, §5.7);
  - `collab` mode: the collab store is authoritative (history, activity, LWW). Mode change: import from the `.node.json` files then removal from them on `cloud` → `collab`, written back on `collab` → `cloud` (§3.0).
- **Tasks** per title: text, assignee, optional due date, state.
- **Notes** per title or per version, written by the members in ReaHarvest. Distinct from the REAPER project notes (`<NOTES` chunk, visible in REAPER's project settings, §5.6).
- **Lyrics** per title, with modification history.
- **Shared assets** per title (scores, tabs, images, PDF, other files):
  - files are stored in the title's `Assets/` and synchronized with the title (§5.5). They are **not versioned** (no backups in `.history/`); a deleted asset is moved to the title's `.trash/`;
  - metadata (description, author, optional associated version) is in the collab store (`asset` entity);
  - built-in preview for images and PDF, opening with the system application otherwise;
  - in `local` and `cloud` modes, `Assets/` is available without collaborative metadata.
- **Activity feed** (history of changes, per title and global): publications, forced publishes, status changes, new tasks. Available with any store (journal or PocketBase).
- **Notifications** (phase 2): real-time, in the application and as OS system notifications, with the PocketBase store only.

---

## 6. Collab store

### 6.1 Principles
- A **single canonical model**, independent of the implementation.
- Two interchangeable adapters behind the same port: `JournalStore` (serverless, MVP) and `PocketBaseStore` (phase 2).
- **One-click switch** between the two, without data loss.
- The rest of the application only knows the port.

### 6.2 Canonical model
All entities share these fields:
```
uid        ULID, generated client-side (canonical identity, never backend-generated)
groupId    ULID
libraryId  ULID
entity     "member" | "titleMeta" | "versionMeta" | "task" | "note" | "lyrics" | "asset" | "activity"
author     memberId
hlc        Hybrid Logical Clock timestamp of the last write
deleted    boolean (tombstone)
```
Entity-specific fields: to be defined in code (shared types generated once).
Conflict resolution: **last-writer-wins per field**, ordered by `hlc`, then by `author` on ties.
`activity` is an append-only journal: entries are never modified nor deleted (no tombstone).

Port (pseudo-signature):
```
CollabStore
  upsert(entity, uid, fields)
  delete(entity, uid)
  query(entity, filter)
  subscribe(filter) -> stream of changes
  exportAll() -> CanonicalExport
  importAll(CanonicalExport)             # idempotent upsert by uid, LWW applied
```

### 6.3 Journal adapter (`JournalStore`)
```
<repositoryRoot>/.collab/<memberId>/<yyyy-mm>.jsonl     # append-only, one writer per directory
<repositoryRoot>/.collab/exports/<timestamp>.json       # full exports of the store, optional baselines
```
- Each member writes **only** in their own folder: no Drive synchronization conflict possible.
- One line = one operation: `{ v, opId, groupId, author, hlc, entity, uid, op: "upsert"|"delete", fields }`.
- Reading: merge of all journals, then local projection into SQLite (incremental replay by file offset).
- Detection of remote changes: file watching, with **fallback to periodic polling of mtimes** (file events on a virtual Drive volume are not reliable) **[TO VALIDATE]**.
- Known limitation: propagation latency depending on the Drive client.

### 6.4 PocketBase adapter (`PocketBaseStore`, phase 2)
- One collection per entity. The `uid` field has a unique index and serves as canonical identity; the internal PocketBase `id` is never exposed outside the adapter.
- Writes: upsert by `uid`, with per-field LWW applied on the adapter side.
- Subscriptions: PocketBase realtime.
- Access rules filtered by `groupId` (multi-tenant possible).
- Authentication: one account per member, linked to their `memberId`.

### 6.5 Library configuration and store switch
`.library.json` (at the library root; in `cloud` and `collab` modes, in the repository, hence shared by all members):
```json
{
  "libraryId": "...",
  "schemaVersion": 1,
  "mode": "local" | "cloud" | "collab",
  "layout": {
    "levels": [
      { "key": "artist" },
      { "key": "album" },
      { "key": "title" }
      // custom key: { "key": "take", "labels": { "en": "Take", "fr": "Prise" } }
    ],
    "renderMetadata": { "artist": "artist", "album": "album", "title": "title" }
  },
  "knownValues": [                 // intermediate levels only, as a tree (§3.1)
    { "value": "Band", "children": [ { "value": "First album" }, { "value": "_Unassigned" } ] }
  ],
  "statuses": [
    { "key": "idea" }, { "key": "writing" }, { "key": "recording" }, { "key": "mixing" }, { "key": "done" }
    // custom value: { "key": "demo", "labels": { "en": "Demo", "fr": "Maquette" } }
  ],
  "collab": {                      // present in collab mode only
    "groupId": "...",
    "store": "journal" | "pocketbase",
    "backendUrl": "https://..."
  },
  "members": [                     // declared during the migration (§5.8)
    { "memberId": "...", "name": "..." }
  ]
}
```
Members are declared by the person who prepares the library, before the others install the application, so that versions get their owner during the migration. A member joins by picking their entry (§5.1); `.collab/<memberId>/member.json` marks a joined member.
Switch procedure (single action in the settings):
1. `exportAll()` from the current adapter.
2. `importAll()` into the target adapter, then verification by count per entity.
3. Writing of `.library.json` with the new store.
4. The other members' applications detect the change of `.library.json` and switch automatically.
5. PocketBase → journal switch: the export is written into `.collab/exports/` as the starting baseline.

---

## 7. Technical architecture

### 7.1 Stack
- **Flutter (desktop) + Dart**, native AOT compilation. Targets: Windows and macOS first, Linux secondary; Android and iOS considered later (§7.4).
- A single language for everything: interface, business logic, input/output.
- Interface: **Material as a minimal foundation only** (text fields, menus, tooltips, focus, accessibility), under the application's own design system: own tokens (colors, spacing, radii, motion durations and curves) through `ThemeExtension`, own key components (title card, search bar, filter chips, settings popup) and own animations. No dependency on Material 3 Expressive (status in Flutter uncertain; Material moved to the `material_ui` package in Flutter 3.47).
  - Visual direction: refined and modern, aimed at artists, beautiful without being flashy; polished animations kept light (built-in Flutter animations only, no Lottie/Rive, no heavy shaders).
  - Light and dark themes (both mandatory); theme setting: light, dark or follow the system. Adjustable font size.
  - Embedded font: **Inter** (variable, SIL OFL). Alternatives shortlisted by the user if Inter does not fit: Martel, Fira Sans, Poppins; more characterful: Poiret One, DM Mono.
- State management: **Riverpod 3** (`flutter_riverpod`), **without code generation**. Decided (2026-11-06) over plain `ChangeNotifier`/`InheritedWidget` (async loading/error states, dependencies between states and disposal would have to be hand-written) and over `provider` (superseded) or Bloc (verbose). Only `Provider`, `FutureProvider`, `StreamProvider`, `Notifier` and `AsyncNotifier` are used. Ports are exposed as providers and overridden with the concrete adapters in `main()` (`ProviderScope(overrides: …)`), and with fakes in tests.
- Indicative packages:
  - `sqlite3` / `drift`: local index;
  - `watcher`: file watching;
  - `path`;
  - `pocketbase`: official Dart SDK (phase 2);
  - `ulid`: identifiers;
  - `window_manager`, `file_selector`, `local_notifier`: desktop integration;
  - `auto_updater` (Sparkle / WinSparkle): automatic update.
- **Hash**: requirements: negligible collision probability outside an adversarial context (no security use), throughput at least the disk's, streamed computation on large files. A 64-bit fingerprint is enough: hashes are only ever compared together with name and size, between a few files (same path, media pool), never across the whole corpus (~3·10⁻⁶ collision probability even for 10 million files compared pairwise). Chosen: **XXH3-64**, pure Dart (`xxh3` package, streaming API), stored as 16 lowercase hex digits. The hash is computed only if size or mtime changed.
  Benchmark (Windows x64, AOT executable, 1 GB file in the OS cache read by 1 MB blocks, read alone ~7.5 GB/s): pure Dart `xxh3` XXH3-64 ~1.9 GB/s; `hashlib` XXH3-128 ~90 MB/s, BLAKE2b/MD5 ~170 MB/s, `crypto` SHA-256 ~160 MB/s; no pure Dart BLAKE3. Native through `dart:ffi`: XXH3-128 ~6.1 GB/s (SSE2) / ~7.0 GB/s (AVX2), BLAKE3 single-threaded ~3.0 GB/s. Pure Dart XXH3-64 is faster than real disk reads (HDD, SATA SSD, most NVMe, streaming cloud folders) and needs no native toolchain; the native path stays available behind the same hasher function if ever needed.
- **Concurrency**: all long tasks (scan, bulk parsing, hash, copies) run in **isolates**, never on the UI isolate. The hash is computed in the background, in batches (one title and its versions).

### 7.2 Package layout
Monorepo of Dart packages (workspace):
```
packages/
  domain/          # pure Dart: entities, rules, sync states, canonical collab model,
                   # ports (abstract classes: RepositoryStorage, CollabStore)
  rpp/             # pure Dart: RPP parser/writer (read: tracks, FX, metadata; write: targeted line/chunk patches only)
  collab/          # CollabStore adapters
    journal/       # JournalStore adapter (dart:io)
    pocketbase/    # PocketBaseStore adapter (phase 2, no dart:io dependency)
  library/         # libraries, modes, configuration, mode transitions
  repository/      # repository and workspace scanning, layout conventions, adoption (dart:io)
                   # MountedFolderStorage adapter (RepositoryStorage)
  index/           # local SQLite index: files, hashes, checkout bases, collab projection
  sync/            # checkout / publish / release / conflict detection
  reaper/          # launching, resource path, plugin cache parsing, prefs checks
apps/
  desktop/         # Flutter desktop app: UI, state management, wiring of adapters
  mobile/          # (later) Flutter mobile app
```
Packages are created at the milestone that uses them (milestone A: `domain`, `rpp`, `library`, `repository`, `index`, `reaper`; milestone B: `sync`; milestone C: `collab`). Package name: `reaharvest_<folder>`.

Decoupling rules:
- `domain` and `rpp` are **pure Dart** (no Flutter or `dart:io` dependency), hence testable in isolation and reusable on mobile.
- Other packages depend on `domain` through **interfaces** (abstract classes), never on concrete implementations.
- No PocketBase- or journal-specific type leaves its adapter.
- The UI layer knows neither the collaborative mode nor the file system: it consumes services exposed by the state layer.
- Implementations are injected at the application entry point only.

### 7.3 Writing RPP files
- The writer modifies the **original text through targeted patches**, and never re-emits the complete file from a model, to guarantee fidelity.
- Atomic write: temporary file, then rename.
- Non-regression tests on a corpus of real `.RPP` files (write then read back without loss, opening in REAPER).

### 7.4 Mobile applications (later)
Goal: notifications, notes, tasks, lyrics, statuses; no REAPER project management.
- Direct reuse of `domain` and of the `CollabStore` port.
- **Constraint**: journal mode assumes a mounted Drive folder, unavailable on mobile. Mobile applications will require **PocketBase mode** (or a journal adapter through the Google Drive API, to be evaluated when the time comes).
- Mobile push notifications: third-party service required (FCM / APNs), outside the current scope.

---

## 8. Non-functional requirements

- **Performance**:
  - startup to a usable main view in less than one second, served from the index;
  - no blocking operation in the interface;
  - long tasks in the background with progress and cancellation;
  - incremental scan (mtime + size, hash only when needed);
  - indicative target: 1,000 `.RPP` and 100 GB of media without perceptible degradation.
- **Reliability**: no data loss possible without explicit confirmation; all destructive operations go through the trash or the backups.
- **Usability**: usable by non-technical people; musical rather than technical vocabulary; main actions reachable in one click.
- **Distribution**: entirely free and open source tooling; build and publication by CI (GitHub Actions), artifacts published as GitHub Releases.
  - **Windows**: installer (Inno Setup or MSIX) signed for free through **SignPath Foundation** (open source program: public repository, OSI license, signing from CI), to avoid the SmartScreen warning (retained; application to be submitted once the repository is public and the license chosen).
  - **macOS**: **non-notarized** DMG (no paid Apple membership). The Gatekeeper warning on first launch is accepted; the authorization procedure is documented. No test machine available: macOS is built by CI, tested on a "best effort" basis.
  - **Automatic update** (`auto_updater`, WinSparkle / Sparkle, signed appcast feed): check at startup then periodically → "update available" notification (UI: « mise à jour disponible ») → one click → download, installation → restart if needed.
- **License**: GPL-3.0 (`LICENSE`).
- **Application identifier**: `io.github.6wheels.reaharvest` (Windows, macOS); `io.github._6wheels.reaharvest` on Linux (freedesktop rule: a segment cannot start with a digit; format compatible with Flathub verification).
- **Internationalization**: interface in **English and French** (ARB files, `gen-l10n`); system language on startup, English if it is not supported; language can be changed in the settings.
- **Logging**: `package:logging` with a file sink next to the settings (one file per day, the last ones kept), reachable from the settings; reports (§5.2) are written to it.
- **Tests**: line coverage measured and enforced in CI (the build fails below the threshold): 95 to 100 % for the core packages, the widget tests and the integration tests. Any uncovered line carries a written justification (`// coverage:ignore-…` with the reason).
- **Footprint**: stay light, in the spirit of REAPER (16 MB installer for a full DAW). Measured (2026-11-06, Flutter 3.47.9, empty app, Windows x64 release): 24.7 MB on disk (Flutter engine 20.3 MB, compiled Dart 3.3 MB, ICU data 0.8 MB), 10.3 MB zipped. With the app shell (#9: Riverpod, localizations, Inter subset to Latin ~114 KB, SQLite 1.7 MB): 28.9 MB on disk, 12.2 MB zipped.

---

## 9. Phases

| Phase | Content |
|---|---|
| **1 — MVP** | Libraries and modes (`local`, `cloud`, `collab`), mode change, configuration, layouts (provided templates + custom), folder conventions, scan and index, navigation, detail view, version management, Checkout / Publish / Release (conflicts, forcing), creation from template, opening in REAPER, adoption wizard. Full `collab` mode: members, ownership and forcing, `CollabStore` port + `JournalStore`, statuses, tasks, notes, lyrics, shared assets, activity |
| **2 — Backend** | `PocketBaseStore`, one-click switch, authentication, real-time notifications; prerequisite for mobile applications |
| **3 — Tools** | Renders: built-in player, on-demand render, render publication (repository and export folders); track import between versions; companion Lua scripts (for example audio render of tracks whose plugins are missing) |

**Re-oriented MVP** (decided 2026-11-09). The primary goal is to move the band onto a structured shared Drive folder, Windows only (macOS best effort). Work already done (`local` mode, free tree, layouts, scan and index, navigation, detail view, version management) is kept as is. Internal milestones, delivered and tested in this order, each usable on its own:
1. **M0 — Foundations**: portable mode (§5.1), background tasks zone and structured reports (§5.2), logging and coverage gate (§8).
2. **M1 — Migration**: in-place organization of the band folder (§5.8): inventory, typed issues in "To sort", fixes in the interface, members (§6.5), conversion to a collab repository.
3. **M2 — Join and synchronize**: first-run wizard (§5.1), repository view, Checkout / Publish / Release with conflicts, ownership and forcing (§5.5), versions in `collab` mode, Windows distribution as a zip built by CI.
4. **M3 — Shared statuses and activity**: `JournalStore` limited to statuses (`titleMeta`, `versionMeta`) and `activity` (§6.3), activity feed (§5.9).

Parked until after the re-oriented MVP (milestone "Later"): version detail view beyond what M1 needs, creation from template, mode change wizards, file watching, tasks / notes / lyrics, shared asset metadata, installer and auto-update, macOS / Linux validation, CLAP / AU / LV2 caches, library removal, configurable statuses, custom layout editor, card actions menu, checkout options. Former milestones A (`local`), B (`cloud`) and C (`collab`) are superseded by this order.

Plan from milestone A: local `memberId` and version `owner`, `libraryId`, `.library.json` (including the `collab` block), `groupId`, ULID `uid`, HLC, configurable backend URL, `RepositoryStorage` and `CollabStore` ports.

---

## 10. Open points and risks

1. ~~Format of project and render metadata lines, `EXTSTATE`~~ (validated, §4.2, §5.6).
2. Detection of an open project: neither `REAPER.ini` nor file lock; MVP through process detection, companion script later (§5.7).
3. Reliability of file watching on the streaming Drive volume (§6.3).
4. ~~`reaper.ini` preference keys~~ (validated: peaks only, backups without check, §5.1).
5. Plugin caches: VST and JS validated on Windows; CLAP, AU, LV2, macOS and Linux remaining (§5.3, #40). Linux can be validated under WSL2 + WSLg (available on the dev machine) with the Linux REAPER build and a Linux Dart SDK installed inside WSL: the `dart` reached through Windows interop runs as Windows.
6. Opening in the existing instance on macOS (§5.7).
7. Naming patterns of conflict copies per cloud provider (§3.0).
8. ~~License and SignPath~~ (GPL-3.0, SignPath retained, §8).
9. ~~`RENDER_FILE` form, command-line render with REAPER open~~ (validated, §5.3).
10. ~~Choice of the hash algorithm by benchmark~~ (validated: XXH3-64, pure Dart, §7.1).
11. Relative paths with `\` read by REAPER macOS (§4.3).

## 11. Out of scope

- Continuous automatic bidirectional synchronization (synchronizations remain explicit).
- Version tree and automatic project merging.
- Change of layout of an existing repository (structure migration).
- Working directly in the Drive folder.
- Peer-to-peer mode.
- Cloud providers accessible only through an API (without a mounted folder).
- macOS notarization.
