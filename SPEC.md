# ReaHarvest — Specification

> Collaborative REAPER project manager.
> Technical name: `reaharvest` (repository, Dart packages prefixed `reaharvest_`, application identifier `reaharvest`).

> Reference document for implementation (Claude Code sessions).
> Code identifiers, technical file names and comments are in English.
> Items marked **[TO VALIDATE]** must be verified before implementing the related feature.
> The user interface is in English (default) and French (§8): French UI labels are given as (UI: « … »).

---

## 1. Context and goals

A group of 3 musicians (only one with a technical profile) working on REAPER projects shared through a mounted Google Drive folder (streaming mode).

Problems to solve:
1. Diverging projects and manual reintegration of parts.
2. Massive duplication (media copied per person and per version, up to ×5).
3. Lack of discipline (folder structure not followed, duplication out of fear of deleting, loss of the "right" version).

Goals:
- Enforce an organization that requires no effort from non-technical users.
- Each version is self-contained (its project and its media in one folder); its size is shown and space is freed by hand (trash, purge).
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
| Level | Element of a layout. Each level maps to a folder; its value (the folder name) is used for search, filters and navigation. |
| Tag | Free word or words attached to a title (e.g. `live`, `standard tuning`, `rehearsal`), shared by the members, used by search and filters (§5.9). Not a layout level, in any mode. |
| Node | Folder matching a layout level. Has a stable `nodeId`. |
| Title (leaf node) | Last level of the layout, whatever its displayed name (title, scene…). Folder holding its `.node.json`, the assets, the trash and one folder per version. Its `nodeId` serves as `titleId`. |
| Version | A self-contained REAPER project: a folder of the title holding a single `.RPP` with its own `Media/`, `Renders/` and `.history/` (variant of the title, e.g. another arrangement, or the version of another member). Has a stable `versionId`, an owner, a label. |
| Backup (UI: « Point de sauvegarde ») | Copy of a version's `.RPP` at a given time, kept in the version's `.history/` folder: the history of a version. Distinct from REAPER's own backups (`.rpp-bak`, `Backups/`). |
| Media | `Media/` folder of a version, its record path. Never shared with another version. |
| Checkout (UI: « Récupérer ») | Copy repository → workspace, version by version. |
| Publish (UI: « Publier ») | Copy workspace → repository of a version folder. |
| Release (UI: EN "Remove local copy", FR « Retirer la copie locale ») | Removal of the local copy of a version or of a title, once all of it is in the repository, to free space in the workspace. Not a deletion: the repository is unchanged. |
| Asset | Auxiliary file of a title, outside the REAPER project (score, tab, image, PDF, text…). |
| Collab store | Storage of shared data in `collab` mode (statuses, tasks, notes, lyrics, asset metadata, activity). Two implementations: journal and PocketBase. |

---

## 3. Libraries, modes and organization

### 3.0 Libraries and modes

The user configures **one or more libraries**. Each has its own mode, layout and folders. All are presented in a **unified view**, filterable by library and by mode (§5.2).

| Mode | Folders | Features | Use case |
|---|---|---|---|
| **`local`** | Workspace only | Organization (layout), navigation, versions, statuses, assets (files only), detail view, creation, opening in REAPER. No synchronization, no collaboration | Personal projects on a single machine |
| **`cloud`** (local + cloud) | Workspace + cloud repository | `local` + Checkout / Publish / Release, conflict detection (useful between several machines of the same user), cloud copy. Single user: no ownership check; no forcing (§5.5) | Personal projects copied to the cloud and accessible from several machines |
| **`collab`** (collaboration) | Workspace + shared cloud repository | `cloud` + members, version ownership, collab store (statuses, tasks, notes, lyrics, shared asset metadata, activity) | Group projects |

Rules:
- Work always happens **in the local workspace**; the repository is never a place to work in. Single exception: organizing a collaboration folder (§5.8) is done in place, on the repository, by the member who created the library, since it is the source of truth and this avoids downloading the whole library; the other members join once it is ready.
- **Mode change** possible at any time, through a wizard (outside the MVP, §9):
  - `local` → `cloud`: choice of the repository, initial publish;
  - `cloud` → `collab`: group creation, member invitation, adoption of versions (owner assignment);
  - downgrades: `collab` → `cloud` (full export of the collab store kept in the repository), `cloud` → `local` (the repository is left intact, simply detached).
  - Statuses, version labels and owners stay in the `.node.json` files in every mode (§5.9): a mode change moves none of them.
- A given folder can belong to only one library (checked at configuration).

**Cloud providers.** The MVP relies on a **folder mounted or synchronized by the provider's client**: the application only sees a file system path. The following are therefore covered, with no specific code: Google Drive for desktop, Dropbox, OneDrive, iCloud Drive, Nextcloud, Syncthing, network share (NAS/SMB), rclone mount (Linux). Common constraints to handle:
- on-demand files (not present locally): never read or hash them needlessly, rely on size and mtime;
- copies of a project or of a version folder, made by a cloud client after a conflict or by hand (e.g. `file (1).RPP`, `file (conflicted copy …).RPP`, `file.sync-conflict-….RPP`, `<version> (1)/`): detected with these generic patterns, whatever the provider, and reported as anomalies, never silently adopted (#23).

Providers accessible through an API only (without a mounted folder) are **outside the MVP**. Repository access goes through a `RepositoryStorage` port whose MVP implementation is `MountedFolderStorage`, to allow other adapters later.

### 3.1 Layouts

The folder structure is defined by a **layout**: an ordered sequence of levels. Each level is a **placeholder** whose value is the folder name; it feeds search, filters and navigation in the interface. Levels are not tags (§2, §5.9).

Provided templates:
| Template | Levels (keys) | Displayed labels (UI, en / fr) |
|---|---|---|
| **Classic** | `<artist> / <album> / <title>` | Artist / Album / Title — Artiste / Album / Titre |
| Project-oriented | `<artist> / <title>` | Artist / Title — Artiste / Titre |
| Film-oriented | `<project> / <chapter> / <scene>` | Project / Chapter / Scene — Projet / Chapitre / Scène ou titre |

Layout rules:
- The last level is always the **leaf node** (title): it holds the version folders.
- A layout has 1 to 4 levels. Each level is a **token** (placeholder, written `<key>`, e.g. `<album>`): a language-independent level key (technical identifier, in English), so that a configuration can be reproduced as is. Labels are never stored as plain text: the displayed label is the translation of the key (key → value per language). Keys of the provided templates are translated by the application; custom keys carry their own translations in `.library.json` (`labels`, by language code), with fallback to English, then to the key itself.
- All levels are mandatory. Each intermediate level has a reserved value (`_Unassigned`, UI: « Non classé ») for items that are not attached.
- **Known values** of the intermediate levels (e.g. classic: the artists, and the albums of each artist), stored in `.library.json` (`knownValues`, §6.5) as a tree that follows the levels; the leaf level (title) is never listed. The depth of a folder alone cannot tell an artist from a title placed too high: the scan uses the known values to recognize each level and to report precisely what is wrong (§5.8). They are asked when a library is added on a folder that already holds projects (§5.1) and during the migration (§5.8), pre-filled with the folders found at each depth: at least one value per intermediate level, each value of a non-last intermediate level having at least one child (`_Unassigned` allowed, e.g. a band without albums). A value created in the application (new title under a new artist or album) is added to the tree. They are editable in the library settings; a value still used by a folder cannot be removed. Not used by the free tree (§3.3).
- In `local` mode only, a layout can be replaced by the **free tree** (§3.3).
- The layout is defined **per library**, in `.library.json`. It is **frozen as soon as the first title is created** (derived from the presence of titles, not stored): changing it afterwards is a migration (outside the MVP).
- Each layout declares a **levels → render metadata mapping** (e.g. classic: `artist` → artist, `album` → album, `title` → title). The mapping can be modified by the user.

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
        .node.json                # { nodeId, level: "title", versionStatuses, versionLabels, versionOwners, tags } (cf. §4.2, §5.9)
        <version>/                # one self-contained REAPER project (flat list of versions)
          <version>.RPP           # a single project file
          Media/                  # its own media (record path)
          Renders/                # its own renders; default render folder (cf. §5.3)
          .history/               # its own backups (history), cf. §5.4
        Assets/                   # attached files of the title: scores, tabs, images, docs (cf. §5.9)
        Unsorted/                 # files found outside any title by the migration, attached to it until the user trashes or deletes them (cf. §5.2, §5.8)
        .trash/                   # deleted versions (whole folders), deleted assets and unsorted files
```

Rules:
- A **version folder** is a subfolder of a title holding a `.RPP` (outside its reserved folders). A version never refers to the media of another version: duplicate media between versions are accepted everywhere (migration, daily work, every mode), and nothing is ever de-duplicated.
- Scaffolding: the library initialization only writes `.library.json`. Creating a title in the application creates its `.node.json`; creating a version creates its folder with `Media/` and `Renders/`. A scan creates no folder: each other folder (`Assets/`, `Unsorted/`, `.trash/`, `.history/`) is created by the first operation that needs it.
- Node files are written by the scan only where the library is worked in (the root of a `local` library, a workspace). The scan of a repository (`cloud`, `collab`) never writes: its node files come from the organization fixes (§5.8) and from publications (§5.5), and a folder without node file is not a title there: it is reported in "To sort" (added by hand in the shared folder).
- Nodes: a layout folder is a node (and gets a `.node.json` on scan, under the rule above) only if an `.RPP` lies in it or below it, outside the reserved folders, which are never nodes: those of a title (`Assets/`, `Unsorted/`, `.trash/`) and those of a version (`Media/`, `Renders/`, `Backups/`, `.history/`). A title whose versions are all in its `.trash/` stays a title. A `.node.json` found in a folder that is not a node is neither used nor deleted: it is listed in the "To sort" page, where the user attaches it to a title, into its `Unsorted/` folder (§5.8); the statuses, version labels, owners and tags it stores are not used. Unreadable application files are listed there too.
- In `cloud` and `collab` modes, the workspace mirrors the repository tree for checked-out versions (with the `.node.json` and `Assets/` of their title). The repository's `.library.json` is authoritative; the workspace keeps a copy of it to work offline.
- Application files and folders (`.library.json`, `.node.json`, `.collab/`, `.migration/`, `.history/`, `.trash/`) start with a dot, and are also given the hidden attribute on Windows when the application creates them. They stay reachable from the application (title card, detail view). Their subfolders take no prefix (e.g. `.collab/exports/`). Validated (2026-11-07, Google Drive for desktop, streaming mode, Windows): dot-prefixed files and folders, with or without the hidden attribute, and hidden folders without a dot are all synchronized; the hidden attribute is kept locally after synchronization. Other cloud clients **[TO VALIDATE]** (e.g. Box Sync is reported to ignore dot-prefixed files).
- `.RPP` files in `.history/` and `.trash/` are never listed as versions, nor in the "To sort" or "To adopt" sections, nor treated as duplicates (§4.2). They are not shown in the main library view; they enrich the title card and the detail view (history, trash).
- The **path** defines the tag values. `.node.json` files only carry **stable identifiers** and the level, so that moving or renaming a folder does not break collaborative data.
- Any folder or `.RPP` whose position does not match the layout appears in the "To sort" section (UI: « À ranger », §5.2), in particular three cases, each with a fix that creates the version folder and moves or copies the media into it (§5.8): a `.RPP` placed directly in the title folder, several `.RPP` in one version folder (e.g. after a *Save As* in place), media outside the version folder.
- The names of a version folder and of its `.RPP` are free and kept identical by the application (a rename renames both, §5.4), except after the migration, which keeps the file name of a project (§5.8): the identity of a version does not depend on its name (cf. §4.2). The names of the reserved folders (`Assets`, `Unsorted`, `.trash`, `Media`, `Renders`, `Backups`, `.history`, in any case) are kept for the application: they cannot name a version, and such a folder is never a version. Until a version folder holding several `.RPP` is sorted, the actions on its whole folder (rename, trash, keep only this version) are refused.
- Extension comparisons are **case-insensitive** (`.rpp` and `.RPP` coexist in real projects).
- Files excluded from any synchronization and from indexing (surveyed on a real repository):
  - REAPER: `*.reapeaks`, `*.rpp-bak` (including timestamped ones: `<name>-YYYY-MM-DD_HHMM.rpp-bak`), the version's `Backups/` subfolder (timestamped backups), `*.rpp-undo`, `*.rpp-prox`, `*.reapindex`. REAPER backups remain a **local** safety net: shared history is provided by the backups in `.history/` (§5.4) and by the cloud provider's history;
  - system: `.DS_Store`, `._*` (macOS AppleDouble), `desktop.ini`, `Thumbs.db`;
  - cloud provider: Google Drive shortcuts (`*.gdoc`, `*.gsheet`…).

### 3.3 Free tree (`local` mode only)

Option for users who do not want to reorganize their folders: the application **leaves the folder tree intact**. The interface nevertheless recommends a frozen layout, and the migration wizard (§5.8) allows switching to one later.

Principle: the library watches **one or more root folders** and behaves like a large indexed library. The topmost folder containing at least one `.rpp` is a title; all the `.rpp` files below it, at any level, are its versions.

Rules:
1. **Path values**: derived from the names of the parent folders, relative to the root; usable in search, without per-level filters.
2. **Title identity**: a `.node.json` is written in each title folder (stable identity, eases a later migration to a layout). This is the application's only write in the tree outside explicit actions.
3. **Project files untouched**: `.rpp` files are never modified nor moved, except an explicit deletion (rule 5). No `EXTSTATE`, hence no `versionId`, label nor owner: a version is identified by its path relative to the title folder (a rename outside the application loses its status). No "To adopt" section.
4. **Media**: no `Media/` constraint, no path normalization, no "To sort" section. Only missing media are reported.
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
- The level values of a title (e.g. `artist=X`, `album=Y`, `title=Z`) are derived from its path and indexed. Its tags (§5.9) are stored in its `.node.json`.

### 4.2 Version
Identity stored **in the `.RPP`**, through a dedicated `EXTSTATE` section named `ReaHarvest` (kept by REAPER on every save):
- `versionId` (ULID), written once, on adoption. It travels with the file: renames outside the application, backups (§5.4), trash, publication (§5.5). A version is adopted when its file holds one.

Label and owner are stored **outside the `.RPP`**, in the title's `.node.json`, keyed by `versionId` (`versionLabels`, `versionOwners`, next to `versionStatuses`, §5.9). Like the statuses, they would be overwritten by REAPER on the next save of an open project (§5.7), and changing them must not rewrite a project nor change its date. They stay in `.node.json` in every mode; in `collab` mode their changes are also activity events of the collab store, never its source (§5.9). Entries of versions that no longer exist are kept.
- `label` (free text, e.g. "chorus B"), required. A version without entry shows its folder name. The label and the folder name are independent: the folder name is pre-filled from the label at creation, and only changes through a rename (§5.4).
- `owner` (memberId), stored only when the library declares members (§6.5): the member chosen at adoption, at creation or in a migration fix. A library without declared members stores no owner, and a version is never required to have one.

`OWNER` and `LABEL` keys found in a `.RPP` are neither read nor removed.

The date is the modification date of the `.RPP`. Members rely on it (also outside ReaHarvest) to tell the latest project, and the versions are ordered by it: only REAPER or an action outside ReaHarvest changes it. Every write of the application keeps it: adoption, migration (rewrites and copies), checkout and backup keep the date of the file or of its source; a restore gives the version the date of the backup. Only a new version (duplicate, blank or from a template) takes the current date. This rule applies to `.RPP` files only.

Observed format (REAPER 7.84, `test/fixtures/reference-metadata.rpp`): `<EXTSTATE` chunk at the end of the root `<REAPER_PROJECT` chunk, after `<EXTENSIONS`, one subchunk per section, one `KEY value` line per key, section and key in uppercase:
```
  <EXTSTATE
    <REAHARVEST
      VERSIONID 01JC...
    >
  >
```
Rules validated by test (`SetProjExtState` then save, REAPER 7.84, with test keys such as `OWNER` and `LABEL`; the application itself only writes `VERSIONID`):
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
| Manual duplication (*Save As*) | Two files with the same `versionId` | Offer to make it a new version (new ID in the file; the label is copied to the new ID); when both files are in one version folder, the fix also gives the copy its own version folder (§3.2) |
| Unknown file | `.RPP` without `versionId` | "To adopt" section (UI: « À adopter »): choice of the label (required, and cannot be emptied afterwards) and, when the library declares members, of the owner; `versionId` written in the file, label and owner in `.node.json` |

A version adopted in batch (§5.8) takes its file name without the extension as label, unless one is given in the fix, editable afterwards.

Versions form a **flat list** (no tree, no parent version).

### 4.3 Media
- Any media referenced by a version must reside in **its own** `Media/` (the version folder's), as a **relative path**. There is no media shared between versions: a reference to the media of another version, or to a file outside the version folder, is reported in "To sort" and fixed by a copy (moved when no other project uses it, §5.8). Media referenced through an absolute path outside the library are tolerated but reported: they cannot be shared in `cloud` and `collab` modes until fixed manually in REAPER (§5.5).
- Observed references: `<SOURCE WAVE` / `<SOURCE MIDI` … `FILE ".\audio-files\x.wav"` or `FILE "audio-files\x.wav"`, `\` separator on Windows. Existing projects use `RECORD_PATH "audio-files"`: the migration (§5.8) rewrites these paths to `Media/` **[TO VALIDATE: reading by REAPER macOS of a relative path with `\`]**.
- Duplicate media between versions are accepted; nothing is de-duplicated, by hash or otherwise. Space is managed by hand: the size of each version is shown, every file of its folder included, with its share by kind (project, media, renders, backup points, REAPER backups, other), and deleted versions are freed by a purge of the trash (§5.4).
- MIDI embedded in the `.RPP` (the drummer's case) does not generate media.
- References outside `SOURCE` chunks: a file whose name appears elsewhere in a project (plain text, or decoded base64 plugin states, as UTF-8 or UTF-16: sampler files, impulse responses) is used by this project. It is never moved automatically (reported for a manual decision, §5.8).

---

## 5. Features

### 5.1 Configuration
- **Libraries** (0..n), each with: display name, mode (§3.0), workspace root, repository root (`cloud` and `collab` modes), layout, optional templates folder specific to the library.
- Adding a library: creation of a new one (choice of mode and layout) or attachment to an existing repository (reading its `.library.json`, case of a member joining a group). When the folder already holds projects and the layout has intermediate levels, the form asks their **known values** (§3.1), pre-filled with the folders found at each depth, before the first scan; an attached library keeps the values of its `.library.json` (asked once if it has none).
  - Form order: name, folder, mode, layout, known values. Choosing the folder fills its field at once; the discovery of the level values that follows shows a progress animation. In the known values, each value offers to remove all its children at once.
- **Removing a library** from the application, whatever its mode, after confirmation:
  - removed: the library from the application configuration and from the index; in the local folder (workspace, or free tree roots), the application files `.library.json`, `.node.json` and `.collab/`. The confirmation states that the statuses, version labels and owners stored in the `.node.json` files are lost;
  - kept: all REAPER and audio content (`.RPP`, `Media/`, `Renders/`, `Assets/`, REAPER backups, peaks…), `.history/` and `.trash/` (project data), and the `ReaHarvest` `EXTSTATE` section of the `.RPP` files (version identity, reused if the folder is added again);
  - in `cloud` and `collab` modes, the repository is never touched. Deleting the application data from the repository is a separate critical action (outside the MVP);
  - goal: the folder can be added again later, with any layout, without leftovers from the previous library.
- First-run wizard: technical settings first (member name, REAPER executable and resource folder, templates folder, peaks preference check), then three choices for the library (also offered later by "Add a library" in the settings):
  - **Join my band's library** (UI: « Rejoindre la bibliothèque de mon groupe »): choice of the repository folder (e.g. the Drive folder), reading of its `.library.json`.
    - Collab repository whose organization is finished (`ready`, §5.8): the members declared in `.library.json` (§6.5) are listed; the user picks who they are (UI: « Qui suis-je ? »). Members who never joined come first; those who did are offered apart ("I already joined from another computer", after a reinstallation or on a second computer), with a confirmation. The settings of the installation store the member it acts as in this library; its own identity is unchanged and still used in `local` and `cloud` libraries. Then choice of the workspace, which must be an **empty** folder (a non-empty folder is refused in the MVP). Joining writes `.collab/<memberId>/<clientId>/client.json` (computer name, date; one writer per folder, no cloud synchronization conflict). The claim is checked again just before writing. Then offer to check out titles (§5.5).
    - Folder without `.library.json`, not in `collab` mode, or whose organization is not finished: clear message (the folder is not set up yet, ask the person who manages it); nothing is written.
  - **Organize a collaboration folder** (UI: « Organiser un dossier de collaboration »): creates a `collab` library on the band's folder and organizes it in place (§5.8).
  - **Create a new library**.
- **Portable mode**: a `settings.json` and/or an `index.sqlite` placed next to the executable are used first, instead of the user application data folder. Used by the demo mode and local tests, and to run two members on one machine (two copies of the application folder).
- Local member identity (`memberId`, display name), created on first run: it is the current member in `local` and `cloud` libraries (a version owner is stored only when the library declares members, §4.2); in a `collab` library, the installation acts as the declared member picked when joining. Each installation also has a client identifier (`clientId`, ULID), which names its folder in `.collab/` (§6.3). Later (outside the MVP): one identity shared by all the machines of a user, linked through a confirmed email.
- Unreadable settings: when `settings.json` cannot be read, the application starts on a recovery screen naming the file, and offers to start with new settings (the file is first kept aside; libraries are to add again, their folders are untouched), to open its folder or to quit. A file written by a newer version is never overwritten: message, then open its folder or quit.
- Path of the REAPER executable and of the REAPER resource folder (defaults per OS). Executable detection: first the location reported by the OS (Windows: default value of `HKLM\SOFTWARE\REAPER` = install folder, validated; macOS: Spotlight `mdfind "kMDItemCFBundleIdentifier == 'com.cockos.reaper'"`; Linux: `which reaper`), then the usual install locations (Windows: `%ProgramFiles%\REAPER (x64)`, `%ProgramFiles%\REAPER`; macOS: `/Applications/REAPER.app`, `/Applications/REAPER64.app`, `~/Applications/REAPER.app`; Linux: `~/opt/REAPER/reaper`, `/opt/REAPER/reaper`). Resource folder: `%APPDATA%\REAPER`, `~/Library/Application Support/REAPER`, `~/.config/REAPER`. macOS and Linux values **[TO VALIDATE]**.
- Project templates folder (default: `ProjectTemplates` in the REAPER resource folder).
- **Settings pages**: the settings popup has a menu on the left, one page per part, each with its sections: Appearance (theme, accent color, zoom from 75 % to 150 %, language, tags display §5.9), Profile, Libraries, System (REAPER, window and tray, logs), About (version, licenses, the REAPER attribution of §8).
- **Window and tray**: closing the window keeps the application in the system tray (notification area), with the usual options (close to tray or quit, start minimized, tray menu to open or quit; quitting while a task runs or waits asks first, listing the tasks: "Cancel the tasks and quit" or "Keep running"). Both are installation-level settings: "Show in the system tray" (off by default; closing the window then hides it and background tasks go on) and "When a project opens in REAPER": do nothing (default), minimize, or close (hide to the tray when enabled, otherwise quit; minimize instead while a task runs). Implemented with `window_manager` and `tray_manager`; on Linux the tray is best effort (it needs an appindicator library). When a project is opened in REAPER, the window is minimized, sent to the tray or left as is, according to this option.
- **Preferences** kept with the settings: "Open in REAPER after duplicating" (§5.4); the synchronization preference of checked-out versions (§5.5).
- Check of a recommended REAPER preference, with a non-blocking warning: peaks centralized outside the project (avoids thousands of `.reapeaks` in the workspace). Validated keys: `altpeaks` bit `0x1` = "Store all peak caches (.reapeaks) in alternate path" (General > Paths), `altpeakspath` = path.
- No check of REAPER backup options: all backups (`.rpp-bak`, timestamped, `Backups/`) are excluded from synchronization (§3.2), whatever option is chosen.

### 5.2 Navigation
Principle: **no imposed tree navigation**. Titles are reached first through search and filters, to minimize the number of clicks.

Main window: the application opens directly on the library. Clean but functional layout, **no side navigation**: search bar at the top, filter chips below it, then the titles (cards by default). Settings are reached through a **gear icon at the top right** and open as a **popup over a blurred backdrop** (glass pane over the rest of the application), with an opening and closing animation. Every other popup (overview, To sort, dialogs, reports) uses the same acrylic glass pane.

While a scan runs, the library keeps showing the current titles of every library (never the empty-library message), and its content is refreshed at the end of the scan.

- **Main search bar**, always visible and focused on startup:
  - instant, typo-tolerant search, served by the local index;
  - covers level values, tags, version names, labels, owners and, in `collab` mode, notes and lyrics;
  - a × button at the right of the field clears it, like the Escape key;
  - with a single result: Enter opens its title detail, Ctrl+Enter opens in REAPER the latest version of the current member. These shortcuts are written under the field, in small italic, only when the action is possible.
- **Display modes**, chosen by the user and remembered:
  - **cards** (default view): **square** cards, like a record sleeve. Generated "aurora borealis" visual, with colors derived from the `titleId` (stable for a given title, different between titles). Content: title, with the parent level values (e.g. artist, album) placed a bit higher and in a larger font (the title the largest), BPM and sample rate in small just below them on the right; number of versions, last modification date, status as a progress trail (below), tags when their display is enabled (§5.9); quick action buttons without outline; sync state of the title in `cloud` and `collab` modes (not published, not checked out, up to date, locally modified, remotely updated, in conflict, cf. §5.5); later also version owners. Quick actions shown on hover or selection: "Open in REAPER" (latest version of the current member, else the latest version; in `collab` mode, opening another member's version asks for a confirmation), "open detail", and a "…" menu (new version, backup point, change status, show in the file explorer);
  - **list**: dense table, sortable by column, status as a progress trail; the card quick actions are shown at the end of a row on hover. Columns in this order: Title (header "Title", not "Name"), one column per layout level below it (title level + 1, + 2…), Version (wider, right-aligned), BPM (right-aligned), Status, Modified (right-aligned); tags when their display is enabled;
  - **tree**: grouping by layout levels (e.g. Artist → Album → Title), offered as one view among others. The right-hand data (version, status) are aligned on every row; the status is shown as in the list; each level row shows its count (e.g. "12 titles", "3 albums").
- **Combinable filters** (chips or side panel), built from the known data. A filter is shown only when it offers at least 2 values:
  - one filter per layout level (e.g. `artist`, `album`); `_Unassigned` (UI: « Non classé ») is a value like the others. Libraries with different layouts expose their own filters; a common level key (e.g. `artist`) is filtered across all of them;
  - tags (§5.9);
  - library, and mode (`local`, `cloud`, `collab`);
  - source: **repository (cloud)**, **local**, or both (`cloud` and `collab` modes);
  - sync state: not checked out, up to date, locally modified, remotely updated, in conflict;
  - status (all modes, cf. §5.9);
  - version owner;
  - missing plugins, missing media (items whose file is missing), titles without a version (every version in the trash).
- Filters and search are combined and kept between sessions; **saved views** (e.g. "My titles in progress", UI: « Mes titres en cours ») are possible.
- Access to a title's versions from any display mode, without changing view:
  - **overview** (UI: « Aperçu »), dock at the bottom of the library opened by a click on a card or row (no double click): crucial data only (identity: name, parent level values, library, status, BPM, last modification; alerts: missing plugins, duplicated or not adopted versions, leading to the detail; the four most recent versions, **one line each**: label (else the file name, greyed), owner when known, date, BPM, icons only for what needs attention (missing plugins, duplicate, not adopted), the badge of the version status, "Open in REAPER" and "Play" (its render, phase 3); the status shown for the title is the most advanced one of its versions). It floats over the titles with an acrylic background (blur and slight transparency, a single blur clipped to the dock) and closes on a click outside; it cannot be pinned. While it is open, the content of the library stays fully scrollable: its end can be scrolled above the dock;
  - **title detail**: opened by Enter in the search bar (title of the overview) or the "open detail" icon (same icon on the card and in the overview). A page over the library (decided 2026-11-20). Back to the library, with search, filters and scroll kept, through the back button, Escape or the mouse back button. Header: large title name with the first parent level value (e.g. artist) on the same line in a smaller font, the other values (e.g. album) and the library below; on the right, length, BPM, number of tracks and number of items of the selected version (indexed at scan, like the tempo); below, the status progress trail across the width. Above the versions and trash panels, a **"Move…"** action opens a popup giving a value to every layout level of the title, each field with suggestions (known values) or free input; a value outside the known values says that the level will be created. The title folder is moved within the library; a target folder that already exists is refused (nothing is overwritten). Master-detail layout: versions on the left (label only, a generic "Not adopted" or "No label" otherwise, followed by the folder name in italic; icon and color by adoption; status when set), selected version on the right:
    - heading: its label with a pencil button right next to it (edit the label), or its folder name in italic and a "Not adopted" badge when not adopted; "Open in REAPER" on the right of the heading, a bit larger than the other actions;
    - summary: details, absolute path of its `.RPP` file, selectable, with a "Show in file explorer" button opening its folder with the file selected (Windows only for now), its size; adoption when not adopted;
    - actions, outside any menu, below the summary and in a small size, in this order: Duplicate, Change status, Create a backup point, Move to trash, Keep only this version. The last two are styled as dangerous and always ask for a confirmation;
    - the detailed view of §5.3 (tempo, signatures, tracks and FX), missing plugins, duplicates;
    - at the bottom, the history (§5.4) with its own smaller buttons.
    Title assets, unsorted files and trash come as title-level tabs. An unsorted file (§5.8) is moved to the `.trash/` of the title (default action) or deleted permanently after an explicit confirmation; it is never deleted otherwise. Until the assets view exists (§5.9, milestone M3), a button opens the `Assets/` folder of the title in the file explorer.
- **Status progress trail**: one segment per status, passed ones green, the current one orange, the next ones grey; "done" reached shows the whole trail green. Only the current status shows its label; hovering the trail reveals the other labels, with an animation. Labels are centered on their segment, with or without hover. The title's trail shows its status derived from its versions (§5.9). A status outside the list is shown as a plain label. Display only (status changes come with the version actions).
- "To sort" section (UI: « À ranger »): `.RPP` or folders outside the convention. Opened from its counter in the filter bar, as a page over the library (same back navigation as the title detail). The page is **title-oriented** (§5.8): one card per title found (an existing title or a group of projects detected together), with its versions, what is wrong and the fixes proposed for it (create the version folders, attach versions to one another or to an existing title, move the title to its layout position, move a project to another title, album or group). Each version of a card gets a label and, when the library declares members, a member (owner). Level fields work with suggestions or free input, a free value saying that the level will be created. Cards have a checkbox, with a "select all" box and a counter; "Fix…" previews the selected cards, or all of them when none is selected. The selection is kept through a rescan for the items still there.
- "To adopt" (UI: « À adopter », cf. §4.2): a filter (titles having a version to adopt), with its counter of titles in the filter bar; adoption is done in the title detail, on the selected version. The card, the overview and the title detail show the number of versions to adopt of the title.
- **Long and sensitive actions in the foreground**: every long or sensitive action (migration fixes and their undo, move of a title, duplicate, move to trash, keep only this version, purge, restore; later checkout and publish) blocks the interface and shows its progress in the foreground, in a popup over the glass pane; no other action is possible meanwhile, and the library cannot be browsed. Leaving the popup cancels the action (a fix already started is completed first, §5.8). Only the scan runs in the background, without blocking: an action asked during a scan of its library waits for its end, shown in its popup. Quick version actions (adoption, label, status, backup) block the same way while they run.
- **Notification zone** at the bottom of the application (following the theme; the overview dock sits above it), the only place for notifications (no separate toast): the running scan or task with its progress, the outcome of every action and of every finished task, expandable list. The state is an icon on the same principle: green check (done), orange warning, red error; no "Done" text. "Task N" is shown only when there is more than one task. A button on the collapsed bar clears the finished tasks without opening it. An unexpected error opens an error popup with its detail.
- **Reports**: every long action (scan, migration fix, checkout, publish, purge…) produces a report **structured in sections by kind of problem or conflict** (done, skipped, warnings, errors; each item with its path), shown in a popup at the end and reachable from the notification zone. Every section is collapsed by default; the scanned folder is shown under the title of the report (no section for it). Reports are also written to the log (§8).

### 5.3 Version detail view
Parsing of the `.RPP`, without REAPER. Shown in the title detail below the actions of the selected version (§5.2):
- sample rate, tempo and its changes, time signatures and their changes, length of the song. Tempo and signature changes come from the tempo envelope (`<TEMPOENVEX` chunk of the root, one `PT` line per point). Validated (REAPER 7.85, `test/fixtures/tracks.rpp`: 128 BPM in 3/4, 140 BPM at 8.9 s, 4/4 at 14.9 s): `PT <position in seconds> <BPM> <shape> [<signature> …]`; the 4th value is the time signature of the point, `numerator + 65536 × denominator` (`262147` = 3/4, `262148` = 4/4), `0` or absent when the point does not change it; the following values (selection, flags, metronome pattern) are ignored. The initial values are on the `TEMPO <BPM> <numerator> <denominator>` line;
- tracks of the first and second levels (depth 0 and 1), each with its name (`NAME`), color (`PEAKCOL`, bit `0x1000000` = custom color) and its FX listed inline; at most 20 tracks in all, then a "Show more" button unfolds the rest. Depth computed through `ISBUS <type> <delta>` (validated on the corpus): `ISBUS 0 0` normal track, `ISBUS 1 1` folder start, `ISBUS 2 -n` last track of a folder, closes `n` levels;
- plugins used per track, deduplicated. Observed forms: `<VST "VST3: Name (Vendor)" file.vst3 0 "" uid{guid} ""`, `<VST "VSTi: …" file.dll …`, `<VST "VST: …" file.dll …`, `<JS relative/path ""`. CLAP and AU absent from the corpus **[TO VALIDATE]**;
- **plugins missing** on the machine, by comparison with the REAPER plugin caches, discovered by pattern (`reaper-vstplugins*.ini`, `reaper-clap-*.ini`, `reaper-auplugins*.ini`) rather than by exact name:
  - VST (validated on Windows, `reaper-vstplugins64.ini`): `[vstcache]` section, lines `file=timestamp,uid,Name (Vendor)`; in the key, every character of the file name other than a letter, digit, `.` or `_` is replaced by `_` (`"TDR Kotelnikov.vst3"` → `TDR_Kotelnikov.vst3`, `SS-11X.vst3` → `SS_11X.vst3`, `"Darkglass Ultra(x64).dll"` → `Darkglass_Ultra_x64_.dll`); also merged: other `reaper-vstplugins*.ini` files (32-bit). Shell plugins (e.g. Waves) have a `file=timestamp,0,<SHELL>` line plus one `file<id=…` line per sub-plugin; matching is done on the shell file only. Lines with only a timestamp (no plugin name) are treated as not installed;
  - JS (validated, `reaper-jsfx.ini`): lines `NAME relative/path "JS: Name"` (path quoted when it contains spaces); `REV` lines are ignored;
  - formats without validated cache (CLAP, AU, LV2, DX) are reported with an unknown status, never as missing. CLAP (all OS), AU (macOS) and LV2 (all OS, mostly Linux) are to be covered (#40); DX is not covered (32-bit REAPER only, obsolete);
  - CLAP, AU, macOS and Linux names **[TO VALIDATE]**;
- REAPER version;
- owner, label, modification date;
- referenced media, with local presence and size; size of the version folder (project, `Media/`, `Renders/`, `.history/`).

**Listening to a sample and renders** *(outside the MVP — phase 3)*
- A faithful preview **without rendering is impossible**: the final sound depends on plugins, automation and routing, which only REAPER can compute. A simple mix of the raw media files would be misleading; it is not retained.
- **Existing renders**: the application reads the render folder defined in the project (`RENDER_FILE` line, resolved relative to the version folder), lists the audio files present (date, length, format) and plays them in a built-in player (play, position, loop).
- **On-demand render** (optional): background render launched through the REAPER command line (`-renderproject`), with the project's render settings. Constraints: REAPER installed, plugins present on the machine, duration proportional to the song.
  Validated (Windows, REAPER 7.84, REAPER already open): `reaper.exe -renderproject <file>.rpp` launches a separate instance that renders then exits (exit code 0), without disturbing the open instance; a relative `RENDER_FILE` is resolved from the project folder. The render instance rewrites `REAPER.ini` when it exits, with identical content. Residual risk: a preference modified in the main instance during a render could be overwritten by this rewrite (lead: `-cfgfile` option with a copy of `REAPER.ini`, to be evaluated in phase 3).
  Observed `RENDER_FILE` forms: `""` (project folder), relative folder (`.\render`), relative file path (`".\render\Drums 3.mp3"`) or absolute (`"C:\Users\…\x.mp3"`, often from another machine). Combined with `RENDER_PATTERN` (e.g. `$project-ending`) when it denotes a folder.
- Default convention for new projects (from the MVP): render folder `Renders/` in the version folder (cf. §5.6).
- **Render publication**, two independent targets, enabled at repository level and overridable per title:
  - **repository**: `Renders/` published with its version, so that members can listen without REAPER or plugins. Option can be disabled to save Drive space;
  - **export folders** (0..n): copy of renders to a configured external folder (e.g. Drive folder synchronized to a streaming server such as Navidrome). Each target defines a path and name pattern based on the layout levels (e.g. `{artist}/{album}/{title}.{ext}`), accepted formats and a replacement policy (overwrite, version).
  - Metadata embedded in the files comes from the levels → render metadata mapping (§3.1); the application does not rewrite audio tags **[TO VALIDATE: whether the metadata written by REAPER is sufficient for Navidrome indexing]**.

### 5.4 Version management
Actions performed from the title detail (§5.2).
- **Create a version** (a new version folder holding its `.RPP`, `Media/` and `Renders/`): blank, from a template or by duplicating an existing version. New ID and a required label; when the library declares members, the owner is the current user by default (§4.2). In `collab` mode, the owner can be chosen at creation (e.g. a version prepared for another member) or changed afterwards by its current owner only. The name of the folder and of its `.RPP` matters (it identifies the version for the members): pre-filled as `<title> - <label>`, followed by the owner's name when the owner is not the current user, and editable.
  - Blank: REAPER's default template for new projects when one is set, otherwise a minimal project (`<REAPER_PROJECT` chunk only, REAPER fills in its defaults on save). Validated (REAPER 7.85, Windows): the minimal project (root header, `RECORD_PATH`, `RENDER_FILE`, `EXTSTATE`) opens without error, records into `Media/` (relative `FILE "Media\…"`), and keeps the render folder and the version metadata when saved. Validated (REAPER 7.84, Windows): Preferences > Project > "Default template for new projects" is stored in `REAPER.ini` as `newprojtmpl=<path>`, empty when unset, relative to the resource folder when the template is inside it (`newprojtmpl=ProjectTemplates\default.rpp`). macOS and Linux **[TO VALIDATE]**.
  - Blank or from a template: version metadata written, record path `Media`, render folder `Renders`; the other §5.6 values are filled in by project creation only.
  - **Duplicate**: copies the version folder (the project and its `Media/`, without `.history/`; `Renders/` created empty) into a new version folder, with a new `versionId`. Done in the local workspace, it costs nothing on the cloud side until published. A checkbox "Open in REAPER afterwards" opens the new version right after; its state is a user preference (§5.1).
- **Rename** the version and/or modify the label (required: it cannot be emptied). A rename renames both the version folder and its `.RPP`, with REAPER closed (§5.7). Modifying the label never rewrites the project (§4.2). A rename made in the application is tracked through the `versionId`, and published as a rename of the remote folder (§5.5).
- **Delete** (UI: « Mettre à la corbeille »): moves the whole version folder into the title's `.trash/` (` (n)` suffix on a name clash), after confirmation.
- **Keep only this version**: moves every other version of the title into `.trash/`, after confirmation.
- **Purge**: permanent deletion of version folders and assets from `.trash/`, with confirmation: it frees their space. Available in every mode; in `cloud` and `collab` modes, a purged version is removed from the repository by the publish of its owner (§5.5). Sensitive, destructive feature.
- **Back up a version** (UI: « Créer un point de sauvegarde »): copies the `.RPP` of the version into its own `.history/` (flat), named `<version name> <yyyy-MM-dd HHmmss>.<ext>` (` (n)` suffix on a name clash), keeping its date (§4.2). The version itself is unchanged. Backups follow their version (rename, trash, publish) and are linked to it by their folder and by the `versionId` of the copy.
- **Paths of backups**: the copy has its relative paths rebased so that it opens in REAPER from `.history/` (`FILE "Media\x.wav"` → `"..\Media\x.wav"`, `RECORD_PATH "Media"` → `"..\Media"`, empty record path → `".."`, relative `RENDER_FILE` → `..\…`); absolute paths are left as is. Restoring rebases them back to the version folder.
  Validated (REAPER 7.85, Windows): a project in `.history/` with `..\` paths opens without missing media, records into the `Media/` of the folder above and renders into its `Renders/`. But REAPER resolves a relative media path against the record path first and does not normalize it: on each save, an existing media reference grows by one `..\Media\` (`..\Media\kick.wav` → `..\Media\..\Media\kick.wav`), still valid. Hence the application normalizes the paths of a backup before opening it in REAPER (UI: « Ouvrir dans REAPER »), and on restore. Projects in the version folder are not affected (`Media\Media\x` does not exist, so REAPER falls back to the project folder).
- **History**: browsing, opening in REAPER and restoring the backups of a version (manual backups). Restoring first backs up the current state of the version, then replaces its content.

### 5.5 Synchronization
Synchronization works **version by version**: nobody checks out every version nor every title. The `.node.json` and `Assets/` of a title follow the title (checked out with its first version, published with any of them).

A version folder has a **single writer**, its owner. Publishing copies the version folder; there is no media collision and no project rewrite during the synchronization. A conflict is only possible on one same version (the same member on two machines). No action overwrites a version of the repository changed by someone else: there is no forcing.

**Checkout**
- Unit: one version folder (its `.RPP`, `Media/`, `Renders/`, `.history/`), plus the `.node.json` and `Assets/` of its title.
- **Recover as my version** (UI: « Récupérer comme ma version »): from a version not checked out, the application copies it once from the repository into a new version of the current member, in the workspace (new `versionId`, owner = current member). Neither the source version nor the title needs to be checked out.
- Option (outside the MVP): exclude `Renders/`. User preference per library, persisted client-side.
- Local storage of the hash (cf. §7.1) of each checked-out file, used as the comparison base. A checked-out `.RPP` keeps its remote date (§4.2).

**Publish**
1. Check of the media: a version whose media are not all in its own `Media/` (§4.3) is not published; the report points to its fix in "To sort". Media referenced through an absolute path (other machine) are left as is, with a warning stating that a manual action in REAPER is needed for the project to be shared.
2. Copy of the changed files of the version folder, media before the project.
3. For the `.RPP`:
   - **conflict** if the remote hash differs from the base hash: refusal, conflict display, user choice (keep the repository version, or publish as a new version);
   - **version of another member**: refused, with "Save as my own version" (UI: « Enregistrer comme ma propre version »), a shortcut to the duplication of the version (§5.4): label asked, owner = current member. Exception: a version never published (absent from the repository, so only in the workspace of the member who made it) can be published by the local member, whatever its owner (e.g. a version prepared for another member). In a library with members, a version without owner is refused, with an offer to take it (owner = current member) before publishing;
4. Renames, moves to `.trash/` and purges of the owner's versions are applied to the repository.
5. Update of the base hashes; in `collab` mode, emission of an activity event ("X published Y", UI: « X a publié Y »).

**Release**
- Frees space in the workspace, and only there: removes the local copy of a version folder, or of a whole title (every checked-out version, its `.node.json` and `Assets/`). The repository is unchanged. It is not a deletion of the version (§5.4: Delete).
- Only when everything is in the repository: every file identical to its base and to the repository. Otherwise it is refused, the files listed (to publish first); no confirmation lets the user go on. Excluded files (§3.2: peaks, REAPER backups) are removed with the folder.
- The title's `.node.json` and `Assets/` are released with its last checked-out version.
- Always after a confirmation that says what happens: the local copy is removed from this computer, the copy in the repository stays intact and can be checked out again.

**Synchronization preference** of the checked-out versions (§5.1): when to check for updates and to publish one's own versions: manual (default), when REAPER closes, while REAPER is open, periodically; automatic publish; check on the startup of ReaHarvest; publish only when ReaHarvest closes (the closing waits for the end of the publish). Details in its ticket (M2).

**No conflict from the owner's actions**: a version deleted (or purged) by its owner is released from the other workspaces at their next synchronization; a local copy holding unpublished changes goes into the local `.trash/` of the title instead, with a notification. Two versions created with the same folder name in one title: the second publish renames its folder and `.RPP` to a free name (`name (2)`) and notifies its author, who may rename it (§5.4).

**Cancellation, failure, interruption**: a checkout or a publish that did not reach its end is simply started again and copies only what is missing or incomplete (size and hash checked; each file is written atomically). A version counts as checked out only once complete, and is shown as incomplete meanwhile. A publish copies the media before the project, so that the repository never holds a project without its media, and updates the base hashes file by file.

**Node files**: a `.node.json` (statuses, version labels and owners, tags, §4.2, §5.9) is never in conflict. Checkout and publish merge it key by key against its last common content, kept in the sync state (§7.1): an entry changed on one side takes that side; changed on both sides, the local value wins and the report says so. `tags` are merged tag by tag: a tag added on one side is kept, a tag removed on one side is removed, each tag appears once. `nodeId` and `level` are never merged.

**Other members' versions locally**: readable, openable, importable (later phase), but not publishable ("Save as my own version", above).

### 5.6 Project creation
- Input of a value for each layout level (with autocompletion on existing values; folders created if needed), choice of the template and of the version label.
- Copy of the template into a new version folder `<title>/<version>/<version>.RPP`, with its `Media/` and `Renders/`, then filling in of:
  - project title and author;
  - render metadata, according to the layout's levels → metadata mapping (§3.1);
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
- Any modification of a `.RPP` by the application (adoption, path rewrite, track import) requires the project to be closed in REAPER: in the MVP, it is refused while REAPER runs.
  - `REAPER.ini` (`projecttabs`, `projecttab1..n`) is not reliable: it is only rewritten occasionally and keeps stale entries (observed: `projecttabs=1` with `projecttab2..9` still present).
  - MVP: the application cannot tell which projects are open. If a REAPER process is running, the modification waits: a dialog asks to quit REAPER, with "Retry" (detects again) and "Cancel"; nothing lets the user go on anyway. Detection: Windows `tasklist /FI "IMAGENAME eq reaper.exe"`, macOS and Linux `pgrep -ix reaper` **[TO VALIDATE on macOS and Linux]**. Later: REAPER companion script publishing the list of open projects.
  - Validated: REAPER **does not lock** the open `.rpp` (exclusive write open and rename succeeded while the project was open). No lock-based detection is possible, and REAPER will overwrite the modification on the next save of the project: the dialog must say so clearly.
- After opening a project, the application window is minimized, sent to the tray or left as is, according to the window option (§5.1).
- REAPER's "Clean current project directory" only works in the version folder: it never touches the other versions. Known limit, stated in the documentation: it can delete media used only by an old backup (`.history/`) of the version.

### 5.8 Adoption of existing projects (migration)
MVP milestone M1 (§9). The migration organizes a folder **in place**, through the `RepositoryStorage` port: for the band, directly the shared Drive folder (first a copy holding a sample, then the real folder, e.g. `proaudio/reaper/projects/<group>/<title>[/<member>]`); later, for `local` libraries, a local folder first (then published, `local` → `cloud`). A folder that is not migrated can be kept as a free tree (§3.3, `local` only).

Flow (wizard "Organize a collaboration folder", §5.1):
1. **Library**, in this order: its name; the repository folder (the band's folder) and the workspace folder of the creator; the members (§6.5), at least one: the local member, required, who joins at once; the target layout and the **known values** of the intermediate levels (§3.1: e.g. the artists and their albums, pre-filled with the folders found at each depth, the user checks or corrects them). Nothing is written before the last step. A repository folder that already holds a `.library.json` is refused, nothing written, with a message saying that a manual action is needed. The wizard then writes `.library.json` in `collab` mode (`groupId`, store `journal`, `createdBy`, `ready: false`, §6.5) and the client folder of the creator (§6.3), then starts the full scan of the repository. Nothing is copied into the workspace: a title comes there through a checkout (§5.5). A workspace that is not empty is scanned like a `local` root: its folders become title candidates in "To sort".
2. **Inventory** before each batch of fixes (relative path, size, XXH3 hash of every file), stored in a new `.migration/<timestamp>/` (to the millisecond), so that files changed or added between two batches are covered. Hashing reads every file: on a streaming cloud folder, the whole folder is downloaded once; the next inventories reuse the hashes of the previous one for the files whose size and modification date are unchanged (following its moves), and an interrupted inventory is resumed from the already hashed stamps (background task, cancellable). `.library.json` is left out: the application rewrites it during the migration (known values).
3. **Title-oriented scan**. The scan looks for the `.rpp` files under the root folder (the repository, for a band's library). A `.rpp`, its siblings and its children are in every case versions of one same title: each group found is a title candidate, matched to an existing title when one of its `versionId` is known. Projects added, moved or changed by hand in the folder (by mistake or not) are detected the same way, at any later scan. For each title, the "To sort" page (§5.2) lists what is wrong:
   - position against the layout, through the known values (§3.1): title placed too high or too deep, folder named after a known value of another level, unknown value; each one with the expected level and the proposed target;
   - the three cases of §3.2: `.RPP` directly in the title folder, several `.RPP` in one version folder, media outside the version folder (another version, the title folder, a member or status subfolder);
   - member and status subfolders (`<title>/<member>/…`, `<title>/<status>/…`, `<title>/<member>/<status>/…`, e.g. `mix`, `demo`);
   - media referenced through an absolute path, missing media, `RECORD_PATH` other than `Media` (e.g. `audio-files`), `RENDER_FILE` forms (§5.3);
   - other files to move into `Assets/`, or blocked because a project references them;
   - versions not adopted, duplicated `versionId` (§4.2);
   - copies of projects and of version folders (cloud conflict or hand copy, e.g. `x (1).rpp`, §3.0), reported only.
   - files outside any title (e.g. an orphan `.node.json`, a document beside the titles).
4. **Fixes in the interface**, proposed per title, each with a preview (dry run) and a report (§5.2):
   - **organize the title**: each project becomes a version folder named after its version (its label, pre-filled from the file name; `name (2)` when taken) with its own `Media/` and `Renders/`; the project keeps its file name, and a project alone in a subfolder of the title moves with that folder (decided 2026-11-18, #148); its media are moved into its `Media/` when no other project uses them (the last one of the title to use it), copied otherwise (audio, video, MIDI, subprojects `<SOURCE RPP_PROJECT` with their `.rpp-PROX`); references rewritten, `RECORD_PATH` set to `Media` (targeted patch, §7.3); a media named by a plugin state (§4.3) is left where it is and reported. The preview lists the operations planned (folders created, moves, copies, rewrites, blocked projects);
   - **member and status subfolders**: one version per project (e.g. `Alice/` with 2 projects and `live/` with 4 projects give 6 versions of the title); owner from the member folder, version status (§5.9) from the status folder through a proposed mapping to the statuses of the library, confirmed by the user (unmatched names: no status, folder name kept in the report);
   - **label and member of each version**: the fix lets the user set the label (pre-filled from the file name, §4.2) and, when the library declares members, the member who owns the version (pre-filled from the member subfolder when there is one); the versions are adopted in the same fix;
   - **move the title** to its layout position (target proposed from the known values; a free value says that the level will be created), `_Unassigned` value for a missing level (e.g. the album);
   - **attach versions** to one another or to an existing title (e.g. the same song found at the root and under its album): the version folders join the target title, their node entries (statuses, labels, owners) are added to its `.node.json`; a version folder name already taken gets a free name (`name (2)`);
   - **move a project** to another title, album or group (it becomes a version folder there, with its media copied or moved as above);
   - **any other file** (neither a project, nor a media, nor a REAPER file such as `.rpp-bak`, `Backups/`, peaks) is moved into the title's `Assets/`. Before moving it, the application looks for its name in the projects of the title, in plain text and in the decoded base64 plugin states: a referenced file (e.g. impulse response, sampler file) is not moved automatically, it is reported for a manual decision;
   - **files outside any title**: each one is attached to an existing title chosen by the user and moved into its `Unsorted/` folder (`name (2)` on a clash). Nothing is deleted during the migration: the user trashes or deletes them afterwards, from the title detail (§5.2).
   - fix impossible (media not found, absolute path from another machine): reported, `.rpp` left intact, unless the user forces the fix of the title: its projects are then organized anyway, those references left as written (REAPER asks for them when it opens the project);
   - no `.rpp` rewrite while REAPER is running (§5.7);
   - a fix runs in the foreground and blocks the interface (§5.2).
5. **No file is ever deleted.** Every change is a move or a targeted rewrite; before rewriting a `.rpp`, its raw original is copied into `.migration/<timestamp>/`. After each batch of fixes and at the end, the inventory is checked: same number of files, every original hash still present, every move accounted for. Any gap is reported and blocks the end of the organization. A batch is cancellable at every step (inventory, between two fixes, check): a fix already started is completed, the fixes done are kept and shown in the report, then the library is rescanned. The values of the folders moved (or declared in place) join the known values.
   - **Journal**: every operation of a fix (move, rewrite, file created), with the start and the end of the fix, is appended to `.migration/<timestamp>/journal.jsonl`, before the operation it describes; the inventory is appended line by line to `inventory.jsonl` (append operation of the `RepositoryStorage` port). A last line cut by a crash is ignored. A project rewritten by the migration keeps its modification date (its version date, §4.2); as its size and date may then be unchanged, the next scan reads again every project the journal records as rewritten since the last scan.
   - **Failed fix** (read or write error in the middle of its operations, drive unmounted): undone at once, then reported as failed with its reason; the other fixes of the batch go on, and its items stay listed in "To sort", ready to be fixed again. If the undo fails too (drive still unmounted), the batch stops and the fix is offered to be undone like an interrupted one.
   - **Interrupted fix** (the application stopped: crash, power cut): detected from the journal when the application starts and before any new batch on the library. The application offers to undo it, and runs no other batch on that library meanwhile. An undo that started and did not end leaves its fix to undo, even a completed one. The batches, the undos and this detection run one after the other on a library: a fix being applied is never taken for an interrupted one; a batch asked meanwhile is shown at once as a waiting task. The detection reads the journal only, not the inventory.
   - **Undo** of a fix: operations reversed from the last one, rewritten files restored with their date from the copy taken before each rewrite (the original in `originals/` for the first rewrite of an inventoried file, else a copy of that fix under `.migration/<timestamp>/fixes/<n>/`), files created by the fix moved to `.migration/<timestamp>/undone/` (nothing is deleted), then inventory check and rescan. The content a restored copy replaces (it may hold work saved since the fix) is kept first under `.migration/<timestamp>/replaced/`, unless it is already the content of the copy. Every line of the fix is checked before the first change: an undo missing a copy, or whose journal names a path outside the library (a copy outside the migration folder), changes nothing and leaves the fix to undo. A move whose source exists again (created back by REAPER or a sync client) stops the undo, the fix left to undo, until one of the two is set aside. On a resumed undo, a file moved back where the fix had created one is left in place. The undo launched by the user goes through the REAPER warning (§5.7). A move is refused before it is journaled when its source is missing or its target exists. The undo is journaled and can itself be resumed.
   - **Cancelled batch**: as a cancellation only takes effect between two fixes, every fix is complete or not started; the remaining ones stay listed in "To sort" and can be started again.
6. **End of the organization**: "Finish the organization" (UI: « Terminer l'organisation ») checks the inventory, then sets `ready: true` in `.library.json`: the other members can now join (§5.1); following the process (members join once the folder is clean) is up to the creator. Refused while a fix is left to undo or the inventory shows a gap. The items left stay in "To sort" and the application goes back to the main view, which lists the titles of the repository, read only until they are checked out (§5.5). Until the end, the application reopens "To sort" with this button, even after a restart. Before and after the end, the fixes in place on the repository are reserved to the member who created the library (`createdBy`): for the other members, "To sort" of the repository is read only.

### 5.9 Statuses, assets and collaboration
Statuses and asset files are available in **all modes**; the other features require the `collab` mode and the collab store (§6).
- **Status** per version; the status of a title is not stored: it is the highest status of its versions, in the order of the library's list (none when no version has one). Available in **all modes** (key feature):
  - the list of statuses is free, defined per library in `.library.json` (`statuses`, §6.5), started from 2 or 3 provided templates (e.g. `idea`, `writing`, `recording`, `mixing`, `done`). Like layout levels (§3.1), template values are language-independent keys translated by the application; custom values carry their own translations (`labels`);
  - stored in the title's `.node.json` in every mode (`versionStatuses`: map `versionId` → status; in free tree, keyed by the path relative to the title folder), synchronized with the title in `cloud` and `collab` modes (§5.5). Never stored in the `.RPP` (REAPER would overwrite it on the next save of an open project, §5.7);
  - `collab` mode: every change of a status, a version label or an owner is also written as an `activity` event in the collab store, which gives its history and the activity feed to every member, without a checkout. The store is never the source of these values. How the other members get the changes before real-time notifications: open point (§10).
- **Tags** per title, in **all modes**: one or more free words or phrases attached to a title, to qualify it (e.g. `live`, `standard tuning`, `rehearsal`; anything). A tag is never a layout level. Stored in the title's `.node.json` (`tags`, a list), hence shared by the members with the title (§5.5). Used by search and filters (§5.2); a setting (Appearance, §5.1) shows them on the cards, in the list and in the tree.
- **Tasks** per title: text, assignee, optional due date, state.
- **Notes** per title or per version, written by the members in ReaHarvest. Distinct from the REAPER project notes (`<NOTES` chunk, visible in REAPER's project settings, §5.6).
- **Lyrics** per title, with modification history.
- **Shared assets** per title (scores, tabs, images, PDF, other files):
  - files are stored in the title's `Assets/` and synchronized with the title (§5.5). They are **not versioned** (no backups in `.history/`); a deleted asset is moved to the title's `.trash/`, beside the deleted version folders;
  - metadata (description, author, optional associated version) is in the collab store (`asset` entity);
  - built-in preview for images and PDF, opening with the system application otherwise;
  - in `local` and `cloud` modes, `Assets/` is available without collaborative metadata.
- **Activity feed** (history of changes, per title and global): publications, changes of statuses, version labels and owners, new tasks. Available with any store (journal or PocketBase).
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
entity     "member" | "task" | "note" | "lyrics" | "asset" | "activity"
author     memberId
hlc        Hybrid Logical Clock timestamp of the last write
deleted    boolean (tombstone)
```
Entity-specific fields: to be defined in code (shared types generated once).
Conflict resolution: **last-writer-wins per field**, ordered by `hlc`, then by `author`, then by client (§6.3) on ties.
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
<repositoryRoot>/.collab/<memberId>/<clientId>/client.json        # written when this installation joins (§5.1)
<repositoryRoot>/.collab/<memberId>/<clientId>/<yyyy-mm>.jsonl    # append-only, one writer per directory
<repositoryRoot>/.collab/exports/<timestamp>.json                 # full exports of the store, optional baselines
```
- Each installation (`clientId`) writes **only** in its own folder: no Drive synchronization conflict possible, even when a member uses two computers.
- One line = one operation: `{ v, opId, groupId, author, client, hlc, entity, uid, op: "upsert"|"delete", fields }`.
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
    "backendUrl": "https://...",
    "createdBy": "<memberId>",     // the member who organizes the folder (§5.8)
    "ready": false                 // true once the organization is finished: the library can be joined (§5.1)
  },
  "members": [                     // declared by the organization wizard (§5.8)
    { "memberId": "...", "name": "..." }
  ]
}
```
Members are declared by the person who prepares the library, before the others install the application, so that versions get their owner during the migration. A member joins by picking their entry (§5.1); a client folder in `.collab/<memberId>/` marks a joined member.
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
  - Light and dark themes (both mandatory); theme setting: light, dark or follow the system. Accent color setting: teal (default), blue or neutral (near white on the dark theme, near black on the light one). Adjustable font size.
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
- **Hash**: requirements: negligible collision probability outside an adversarial context (no security use), throughput at least the disk's, streamed computation on large files. A 64-bit fingerprint is enough: hashes are only ever compared together with name and size, between a few files (same path), never across the whole corpus (~3·10⁻⁶ collision probability even for 10 million files compared pairwise). Chosen: **XXH3-64**, pure Dart (`xxh3` package, streaming API), stored as 16 lowercase hex digits. The hash is computed only if size or mtime changed.
  Benchmark (Windows x64, AOT executable, 1 GB file in the OS cache read by 1 MB blocks, read alone ~7.5 GB/s): pure Dart `xxh3` XXH3-64 ~1.9 GB/s; `hashlib` XXH3-128 ~90 MB/s, BLAKE2b/MD5 ~170 MB/s, `crypto` SHA-256 ~160 MB/s; no pure Dart BLAKE3. Native through `dart:ffi`: XXH3-128 ~6.1 GB/s (SSE2) / ~7.0 GB/s (AVX2), BLAKE3 single-threaded ~3.0 GB/s. Pure Dart XXH3-64 is faster than real disk reads (HDD, SATA SSD, most NVMe, streaming cloud folders) and needs no native toolchain; the native path stays available behind the same hasher function if ever needed.
- **Concurrency**: all long tasks (scan, bulk parsing, hash, copies) run in **isolates**, never on the UI isolate. The hash is computed in the background, in batches (one title and its versions).
- **Local data**: the index is a cache of the file system, rebuilt from scratch when its schema changes; it is written by the background isolate that scans, the UI isolate only reads it (read-only connection). Besides the indexed project data (tempo, length, tracks, items, plugins), it stores the sample rate and the size of each version folder, by kind of file (§4.3). The sync state (base hash of each checked-out file and last common content of the node files, §5.5) is not a cache: it lives in its own database, whose schema changes by step-by-step migrations and is never dropped.

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
  index/           # local SQLite index (rebuildable cache): titles, versions, files, issues, collab projection
  sync/            # checkout / publish / release / conflict detection, durable sync state (base hashes)
  reaper/          # launching, resource path, plugin cache parsing, prefs checks
apps/
  desktop/         # Flutter desktop app: UI, state management, wiring of adapters
  mobile/          # (later) Flutter mobile app
```
Packages are created at the milestone that uses them (`sync` with M2, `collab` with M3, §9). Package name: `reaharvest_<folder>`.

Decoupling rules:
- `domain` and `rpp` are **pure Dart** (no Flutter or `dart:io` dependency), hence testable in isolation and reusable on mobile.
- Other packages depend on `domain` through **interfaces** (abstract classes), never on concrete implementations.
- No PocketBase- or journal-specific type leaves its adapter.
- The UI layer knows neither the collaborative mode nor the file system: it consumes services exposed by the state layer.
- Implementations are injected at the application entry point only.

Responsibilities (one role per class or module, each testable alone):
- **Business rules live in the packages**, tested without Flutter. The state layer of the app only wires: a service method resolves the library, runs one package operation in an isolate, logs it and asks for the rescan. One service per role: library catalog, scans, version actions, migration actions, REAPER actions.
- **Long operations** (a batch of migration fixes) are orchestrated in a package, in one isolate, and report their steps, progress and cancellation through a small port of `domain`; the app maps the steps to its labels.
- **File changes are planned, then applied**: reads gather the facts, a pure function computes the operations (unit-tested on in-memory data, shown as the preview), and the application of the plan goes through the storage.
- **One module per concern**: library paths and media references; reading and writing project files (one encoding policy, §7.3); in a migration, the inventory, the journal and the guarded storage are three classes.
- **Interface**: one file per page or component. What the interface proposes (the fixes of an issue, their targets) is computed by a package function; widgets show proposals and collect choices.

### 7.3 Writing RPP files
- The writer modifies the **original text through targeted patches**, and never re-emits the complete file from a model, to guarantee fidelity.
- Atomic write: temporary file, then rename.
- Encoding: a project is read as UTF-8 when its bytes are valid UTF-8, as Windows-1252 otherwise (older projects), and written back in the encoding it was read in, so that the bytes outside a patch never change. Such a project is a project like the others: nothing is reported. A value the application cannot write in Windows-1252 leaves the project untouched, with a message. Validated (REAPER 7.85, Windows, `test/fixtures/windows-1252.rpp`): REAPER opens a project written in Windows-1252 and saves it without converting it.
- Non-regression tests on a corpus of real `.RPP` files (write then read back without loss, opening in REAPER).

### 7.4 Mobile applications (later)
Goal: notifications, notes, tasks, lyrics, statuses; no REAPER project management.
- Direct reuse of `domain` and of the `CollabStore` port.
- **Constraint**: journal mode assumes a mounted Drive folder, unavailable on mobile. Mobile applications will require **PocketBase mode** (or a journal adapter through the Google Drive API, to be evaluated when the time comes).
- Mobile push notifications: third-party service required (FCM / APNs), outside the current scope.

---

## 8. Non-functional requirements

- **Performance** (measurable budgets and benchmarks: `docs/performance.md`):
  - startup to a usable main view in less than one second, served from the index;
  - no blocking operation in the interface;
  - long tasks in the background with progress and cancellation;
  - incremental scan (mtime + size, hash only when needed); after an action on a title, only this title is scanned again;
  - indicative target: 1,000 `.RPP` and 100 GB of media without perceptible degradation.
- **Reliability**: no data loss possible without explicit confirmation; all destructive operations go through the trash or the backups.
- **Usability**: usable by non-technical people; musical rather than technical vocabulary; main actions reachable in one click.
- **Distribution**: entirely free and open source tooling; build and publication by CI (GitHub Actions), artifacts published as GitHub Releases.
  - **Windows** (MVP, milestone M2: the members are not technical, they install once and receive the later versions without any manual step): installer (Inno Setup), per-user install without administrator rights; settings, index, sync state and logs stay in the user data folder, kept by an update and by an uninstall unless asked otherwise. A portable zip (portable mode, §5.1) is attached to each release. The installer is not signed in the MVP: an installation guide explains the SmartScreen warning shown at the first installation. Signing comes after the MVP, for free through **SignPath Foundation** (open source program: public repository, OSI license, signing from CI; the certificate is issued to SignPath Foundation, shown as the publisher). **[TO VALIDATE at the start of M2]** the Microsoft Store as another route: free for individual developers, the MSIX package is signed, hosted and updated by Microsoft, which would replace the installer and the update mechanism; to check: where the application data is stored and whether it survives an uninstall, access to the library folders and to REAPER, certification delay, portable mode outside the Store.
  - **macOS**: **non-notarized** DMG (no paid Apple membership). The Gatekeeper warning on first launch is accepted; the authorization procedure is documented. No test machine available: macOS is built by CI, tested on a "best effort" basis.
  - **Automatic update** (`auto_updater`, WinSparkle / Sparkle, signed appcast feed): check at startup then periodically → "update available" notification (UI: « mise à jour disponible ») → one click → download, installation → restart if needed. Never in portable mode; no update is installed while a background task runs. Windows in the MVP, with the installer.
- **License**: GPL-3.0 (`LICENSE`).
- **REAPER logo**: used for the "Open in REAPER" buttons, with the permission of Cockos given to the maintainer for ReaHarvest.
  - Attribution: the sentence "REAPER is a registered trademark of Cockos Incorporated, used with permission." is written as is in the README and in the About page of the application, together with the non-affiliation notice ("ReaHarvest is an independent project, not affiliated with or endorsed by Cockos Incorporated."), which keeps the use from being misleading.
  - Isolation: the PNG logo lives in its own folder (`apps/desktop/assets/third_party/reaper/`), with a `NOTICE` file stating that this file is not covered by the GPL-3.0 and is used with the permission of Cockos; under REUSE/SPDX it is declared as `LicenseRef-Cockos-Permission`.
  - Forks: the permission is granted to the maintainer for ReaHarvest only and does not pass to derived works. The `NOTICE` says so: a fork must get its own permission or remove the logo.
- **Application identifier**: `io.github.6wheels.reaharvest` (Windows, macOS); `io.github._6wheels.reaharvest` on Linux (freedesktop rule: a segment cannot start with a digit; format compatible with Flathub verification).
- **Internationalization**: interface in **English and French** (ARB files, `gen-l10n`); system language on startup, English (the default language) if it is not supported; language can be changed in the settings. Other translations will come later.
- **Logging**: `package:logging` with a file sink next to the settings (one file per day, the last ones kept), reachable from the settings; reports (§5.2) are written to it.
- **Tests**: line coverage measured and enforced in CI (the build fails below the threshold): 95 to 100 % for the core packages, the widget tests and the integration tests. Any uncovered line carries a written justification (`// coverage:ignore-…` with the reason).
- **Footprint**: stay light, in the spirit of REAPER (16 MB installer for a full DAW). Measured (2026-11-06, Flutter 3.47.9, empty app, Windows x64 release): 24.7 MB on disk (Flutter engine 20.3 MB, compiled Dart 3.3 MB, ICU data 0.8 MB), 10.3 MB zipped. With the app shell (#9: Riverpod, localizations, Inter subset to Latin ~114 KB, SQLite 1.7 MB): 28.9 MB on disk, 12.2 MB zipped. With the system tray (#135, `window_manager` and `tray_manager`, 2026-11-18): 32.6 MB on disk for the whole release folder, of which `tray_manager_plugin.dll` 104 KB and `window_manager_plugin.dll` 128 KB.

---

## 9. Scope and delivery order

Scope, state, order and dependencies of the tickets live in the GitHub issues; `PROGRESS.md` and `progress/` hold the lanes and advised models only, `DECISIONS.md` the dated decisions. This section gives the scope.

| Phase | Content |
|---|---|
| **1 — MVP** | Libraries and modes (`local`, `cloud`, `collab`), mode change, configuration, layouts (provided templates + custom), folder conventions, scan and index, navigation, detail view, version management, Checkout / Publish / Release (conflicts), creation from template, opening in REAPER, adoption wizard. Full `collab` mode: members, ownership, `CollabStore` port + `JournalStore`, statuses, tasks, notes, lyrics, shared assets, activity |
| **2 — Backend** | `PocketBaseStore`, one-click switch, authentication, real-time notifications; prerequisite for mobile applications |
| **3 — Tools** | Renders: built-in player, on-demand render, render publication (repository and export folders); track import between versions; companion Lua scripts (for example audio render of tracks whose plugins are missing) |

**Re-oriented MVP** (decided 2026-11-09). The primary goal is to move the band onto a structured shared Drive folder, Windows only (macOS best effort). Milestones, delivered and tested in this order, each usable on its own:
1. **M0 — Foundations**: portable mode (§5.1), background tasks zone and structured reports (§5.2), logging and coverage gate (§8).
2. **M1 — Migration**: in-place organization of the band folder (§5.8): "Organize a collaboration folder" wizard (§5.1), inventory, typed issues in "To sort", fixes in the interface, members (§6.5), end of the organization, read-only list of the repository titles. Every mode change is in the Backlog. Before the last features, the core is hardened along the responsibilities of §7.2, then reworked after the first test of the application (2026-11-14): one folder per version (§3.2), title-oriented scan and "To sort" (§5.8), dates of the projects kept (§4.2), the interface changes of §5.1 to §5.3, tags (§5.9) and statistics.
3. **M2 — Join and synchronize**: first-run wizard with "Join my band's library" (§5.1), member identity per library, durable sync state (§7.1), repository view, Checkout / Publish / Release with conflicts and ownership (§5.5), versions in `collab` mode, Windows installer with auto-update published by CI (§8), design direction of the interface (§7.1).
4. **M3 — Shared statuses and activity**: `JournalStore` (§6.3), then, in this order: activity events of the statuses, version labels and owners (`activity`), assets view with their shared metadata (`asset`), activity feed (`activity`), tasks, notes and lyrics (`task`, `note`, `lyrics`) (§5.9).

Everything else waits in the **Backlog**, the only milestone besides M0 to M3: phases 2 and 3 of the table above, creation from template, mode change wizards, code signing of the releases, macOS and Linux packages and validation, CLAP / AU / LV2 caches, library removal, configurable statuses, custom layout editor, checkout option (exclude `Renders/`).

Present from the start: local `memberId` and version `owner`, `libraryId`, `.library.json` (including the `collab` block), `groupId`, ULID `uid`, HLC, configurable backend URL, `RepositoryStorage` and `CollabStore` ports.

---

## 10. Open points and risks

1. ~~Format of project and render metadata lines, `EXTSTATE`~~ (validated, §4.2, §5.6).
2. Detection of an open project: neither `REAPER.ini` nor file lock; MVP through process detection, companion script later (§5.7).
3. Reliability of file watching on the streaming Drive volume (§6.3).
4. ~~`reaper.ini` preference keys~~ (validated: peaks only, backups without check, §5.1).
5. Plugin caches: VST and JS validated on Windows; CLAP, AU, LV2, macOS and Linux remaining (§5.3, #40). Linux can be validated under WSL2 + WSLg (available on the dev machine) with the Linux REAPER build and a Linux Dart SDK installed inside WSL: the `dart` reached through Windows interop runs as Windows.
6. Opening in the existing instance on macOS (§5.7).
7. ~~Naming patterns of conflict copies per cloud provider~~ (decided 2026-11-20: generic patterns, whatever the provider, §3.0).
8. ~~License and SignPath~~ (GPL-3.0, SignPath retained, §8).
9. ~~`RENDER_FILE` form, command-line render with REAPER open~~ (validated, §5.3).
10. ~~Choice of the hash algorithm by benchmark~~ (validated: XXH3-64, pure Dart, §7.1).
11. Relative paths with `\` read by REAPER macOS (§4.3).
12. ~~Project that is not valid UTF-8~~ (validated: REAPER 7.85 keeps its bytes when saving it; read as Windows-1252 and written back as read, §7.3).
13. ~~Purge in `cloud` and `collab` modes~~ (no longer relevant: no shared media; a purge empties the trash and is published by the owner of the version, §5.4).
14. Collab timestamp far ahead of the local clock (wrong clock on a computer): behavior to decide, so that it does not win every later write (§6.2).
15. Propagation to the other members, before real-time notifications: the `.node.json` files (statuses, version labels, owners), `.collab/` and `.library.json` of the repository must be read again regularly (scan, update, push), so that every member sees the changes (§5.9). To refine.

## 11. Out of scope

- Version tree and automatic project merging.
- Change of layout of an existing repository (structure migration).
- Working directly in the Drive folder, except the organization of a collaboration folder (§3.0, §5.8).
- Peer-to-peer mode.
- Cloud providers accessible only through an API (without a mounted folder).
- macOS notarization.
