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
- Also manage purely personal projects (local, or local with cloud backup) in the same application, through libraries with different modes (§3.0).
- Fast, modern, intuitive application.

Platforms: **Windows and macOS first**, Linux secondary (must build and work, without dedicated optimization effort).
Public release considered in the long run: no hard dependency on Google Drive, on a cloud provider or on a specific backend.

---

## 2. Glossary

| Term | Definition |
|---|---|
| Library | Set of projects managed by the application, with a mode (local, local + cloud, collaboration), a layout and its folders. Has a `libraryId`. |
| Mode | Sharing and feature level of a library (§3.0). |
| Repository | Cloud root folder of a library in local + cloud or collaboration mode (e.g. mounted Drive). Source of truth for project files. |
| Workspace | Local folder of a library, where titles are created, checked out and modified. |
| Group | Set of members sharing a library in collaboration mode. Has a `groupId`. Not to be confused with the "Artist" level of a layout. |
| Layout | Ordered sequence of levels that fixes the folder structure of a repository (e.g. `artist/album/title`). See §3. |
| Level / tag | Element of a layout. Each level maps to a folder and to a tag (key + value) used for search and navigation. |
| Node | Folder matching a layout level. Has a stable `nodeId`. |
| Title (leaf node) | Last level of the layout, whatever its displayed name (title, scene…). Folder holding the media pool, the assets and the versions. Its `nodeId` serves as `titleId`. |
| Version | A `.RPP` file in a title folder. Has a stable `versionId`, an owner, a label. |
| Media pool | `Media/` folder of the title, shared by all its versions, append-only. |
| Checkout (UI: « Récupérer ») | Copy repository → workspace. |
| Publish (UI: « Publier ») | Copy workspace → repository. |
| Release (UI: « Libérer ») | Deletion of the local copy of a title. |
| Asset | Auxiliary file of a title, outside the REAPER project (score, tab, image, PDF, text…). |
| Collab store | Storage of shared data (statuses, tasks, notes, lyrics, asset metadata). Two implementations: journal and PocketBase. |

---

## 3. Libraries, modes and organization

### 3.0 Libraries and modes

The user configures **one or more libraries**. Each has its own mode, layout and folders. All are presented in a **unified view**, filterable by library and by mode (§5.2).

| Mode | Folders | Features | Use case |
|---|---|---|---|
| **`local`** | Workspace only | Organization (layout), navigation, versions (with owner = local member), detail view, creation, opening in REAPER. No synchronization, no collaboration | Personal projects on a single machine |
| **`cloud`** (local + cloud) | Workspace + cloud repository | `local` + Checkout / Publish / Release, conflict detection (useful between several machines of the same user), backup. Single user: no ownership check and no forcing | Personal projects backed up and accessible from several machines |
| **`collab`** (collaboration) | Workspace + shared cloud repository | `cloud` + members, version ownership and forcing, collab store (statuses, tasks, notes, lyrics, shared assets, activity, notifications) | Group projects |

Rules:
- Work always happens **in the local workspace**; the repository is never a place to work in.
- **Mode change** possible at any time, through a wizard:
  - `local` → `cloud`: choice of the repository, initial publish;
  - `cloud` → `collab`: group creation, member invitation, adoption of versions (owner assignment);
  - downgrades: `collab` → `cloud` (export of the collab store as a snapshot kept in the repository), `cloud` → `local` (the repository is left intact, simply detached).
- A given folder can belong to only one library (checked at configuration).

**Cloud providers.** The MVP relies on a **folder mounted or synchronized by the provider's client**: the application only sees a file system path. The following are therefore covered, with no specific code: Google Drive for desktop, Dropbox, OneDrive, iCloud Drive, Nextcloud, Syncthing, network share (NAS/SMB), rclone mount (Linux). Common constraints to handle:
- on-demand files (not present locally): never read or hash them needlessly, rely on size and mtime;
- provider-specific conflict copies (e.g. `file (1).RPP`, `conflicted copy`): detected and reported as anomalies, never silently adopted **[TO VALIDATE: naming patterns per provider]**.

Providers accessible through an API only (without a mounted folder) are **outside the MVP**. Repository access goes through a `RepositoryStorage` port whose MVP implementation is `MountedFolderStorage`, to allow other adapters later.

### 3.1 Layouts

The folder structure is defined by a **layout**: an ordered sequence of levels. Each level is a **placeholder targeting a tag**. The tag value is the folder name; it feeds search, filters and navigation in the interface.

Provided templates:
| Template | Levels (tag keys) | Displayed labels (UI) |
|---|---|---|
| **Classic (recommended)** | `artist / album / title` | Artiste / Album / Titre |
| Project-oriented (no album) | `artist / title` | Artiste / Titre |
| Film-oriented | `project / chapter / scene` | Projet / Chapitre / Scène ou titre |

Layout rules:
- The last level is always the **leaf node** (title): it holds `Media/` and the versions.
- A layout has 1 to 4 levels. Custom templates define, for each level, a tag key (technical identifier, in English) and a displayed label.
- All levels are mandatory. Each intermediate level has a reserved value (`_Unassigned`, UI: « Non classé ») for items that are not attached.
- In `local` mode only, a layout can be replaced by the **free tree** (§3.3).
- The layout is defined **per library**, in `_library.json`. It is **frozen as soon as the first title is created**: changing it afterwards is a migration (outside the MVP).
- Each layout declares a **tags → render metadata mapping** (e.g. classic: `artist` → artist, `album` → album, `title` → title). The mapping can be modified by the user.

### 3.2 Physical structure

Example with the classic template:
```
<libraryRoot>/                   # repository root (modes cloud/collab) or workspace root (mode local)
  _library.json                   # libraryId, mode, layout, collab settings (cf. §6.5)
  _collab/                        # collab mode with journal store only (cf. §6.3)
  <artist>/
    .node.json                    # { nodeId, level: "artist" }
    <album>/
      .node.json                  # { nodeId, level: "album" }
      <title>/                    # leaf node
        .node.json                # { nodeId, level: "title" }
        Media/                    # shared, append-only pool
        Renders/                  # default render folder; publication optional (cf. §5.3)
        Assets/                   # attached files: scores, tabs, images, docs (cf. §5.9)
        <any name>.RPP            # versions (flat list)
        _versions/                # snapshots of overwritten versions (history)
        _trash/                   # deleted versions and assets
```

Rules:
- The **path** defines the tag values. `.node.json` files only carry **stable identifiers** and the level, so that moving or renaming a folder does not break collaborative data.
- Any folder or `.RPP` whose position does not match the layout appears in the "To sort" section (UI: « À ranger », §5.2).
- The name of a `.RPP` is free: the identity of a version does not depend on its name (cf. §4.2).
- Extension comparisons are **case-insensitive** (`.rpp` and `.RPP` coexist in real projects).
- Files excluded from any synchronization and from indexing (surveyed on a real repository):
  - REAPER: `*.reapeaks`, `*.rpp-bak` (including timestamped ones: `<name>-YYYY-MM-DD_HHMM.rpp-bak`), the title's `Backups/` subfolder (timestamped backups), `*.rpp-undo`, `*.rpp-prox`, `*.reapindex`. REAPER backups remain a **local** safety net: shared history is provided by `_versions/` (§5.4) and by the cloud provider's history;
  - system: `.DS_Store`, `._*` (macOS AppleDouble), `desktop.ini`, `Thumbs.db`;
  - cloud provider: Google Drive shortcuts (`*.gdoc`, `*.gsheet`…).

### 3.3 Free tree (`local` mode only)

Option for users who do not want to reorganize their folders: the application **leaves the folder tree intact**. The interface nevertheless recommends a frozen layout, and the migration wizard (§5.8) allows switching to one later.

Principle: the library watches **one or more root folders** and behaves like a large indexed library. Any folder containing at least one `.rpp` is a title; its `.rpp` files are its versions.

Rules:
1. **Tags**: derived from the names of the parent folders, relative to the root; usable in search, without per-level filters.
2. **Title identity**: a `.node.json` is written in each title folder (stable identity, eases a later migration to a layout). This is the application's only write in the tree outside explicit actions.
3. **Version metadata** (`EXTSTATE`): written only on explicit adoption of a version; `.rpp` read-only otherwise.
4. **Media pool**: no `Media/` constraint, no path normalization, no "To sort" section. Only missing media are reported.
5. **Creation, deletion, history**: new titles created in a folder chosen by the user; `_trash/` and `_versions/` placed in the folder of the `.rpp` concerned, created on first use.
6. **Nested folders** each containing `.rpp` files (real case: `title/member/v2/…`): each folder is a distinct title.
7. **Configuration**: watched roots and the library configuration are stored in the application configuration, not in the folders. A root located under an already declared root (in any library) is refused, to avoid duplicates.
8. **Mode change**: switching to `cloud` or `collab` is impossible without a prior migration to a layout.

The local workspace mirrors the same tree for checked-out titles. In `cloud` and `collab` modes, the repository's `_library.json` is authoritative; the workspace keeps a copy of it to work offline.

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
| Rename | Same `versionId`, new name | Transparent tracking |
| Manual duplication (*Save As*) | Two files with the same `versionId` | Offer to make it a new version (new ID, owner = current user) |
| Unknown file | `.RPP` without `versionId` | "To adopt" section (UI: « À adopter »): choice of owner and label, metadata written |

Versions form a **flat list** (no tree, no parent version).

### 4.3 Media
- Any media referenced by a version must reside in the title's `Media/`, as a **relative path**.
- Observed references: `<SOURCE WAVE` / `<SOURCE MIDI` … `FILE ".\audio-files\x.wav"` or `FILE "audio-files\x.wav"`, `\` separator on Windows. Existing projects use `RECORD_PATH "audio-files"`: the migration (§5.8) rewrites these paths to `Media/` **[TO VALIDATE: reading by REAPER macOS of a relative path with `\`]**.
- The pool is **append-only**: a published file is never modified or deleted, except on explicit purge (cf. §5.4).
- Name collision on publish (same name, different content according to the hash): rename with a suffix and rewrite of the references in the `.RPP`.
- MIDI embedded in the `.RPP` (the drummer's case) does not generate media.

---

## 5. Features

### 5.1 Configuration
- **Libraries** (0..n), each with: display name, mode (§3.0), workspace root, repository root (`cloud` and `collab` modes), layout, optional templates folder specific to the library.
- Adding a library: creation of a new one (choice of mode and layout) or attachment to an existing repository (reading its `_library.json`, case of a member joining a group).
- First-run wizard: creation of the first library, REAPER detection.
- Local member identity (`memberId`, display name), created on first run and used in all modes (version owner).
- Path of the REAPER executable and of the REAPER resource folder (defaults per OS).
- Project templates folder (default: `ProjectTemplates` in the REAPER resource folder).
- Check of a recommended REAPER preference, with a non-blocking warning: peaks centralized outside the project (avoids thousands of `.reapeaks` in the workspace). Validated keys: `altpeaks` bit `0x1` = "Store all peak caches (.reapeaks) in alternate path" (General > Paths), `altpeakspath` = path.
- No check of REAPER backup options: all backups (`.rpp-bak`, timestamped, `Backups/`) are excluded from synchronization (§3.2), whatever option is chosen.

### 5.2 Navigation
Principle: **no imposed tree navigation**. Titles are reached first through search and filters, to minimize the number of clicks.

- **Main search bar**, always visible and focused on startup:
  - instant, typo-tolerant search, served by the local index;
  - covers tag values, version names, labels, owners and, in `collab` mode, notes and lyrics.
- **Display modes**, chosen by the user and remembered:
  - **cards** (default view): title, tags, status, sync state, version owners, last modification date;
  - **list**: dense table, sortable by column;
  - **tree**: grouping by layout levels (e.g. Artist → Album → Title), offered as one view among others.
- **Combinable filters** (chips or side panel):
  - tags, one filter per layout level (e.g. `artist`, `album`). Libraries with different layouts expose their own filters; a common tag key (e.g. `artist`) is filtered across all of them;
  - library and mode (`local`, `cloud`, `collab`);
  - source: **repository (cloud)**, **local**, or both (`cloud` and `collab` modes);
  - sync state: not checked out, up to date, locally modified, remotely updated, in conflict;
  - collab status (`collab` mode);
  - version owner;
  - missing plugins.
- Filters and search are combined and kept between sessions; **saved views** (e.g. "My titles in progress", UI: « Mes titres en cours ») are possible.
- Access to a title's versions from any display mode, without changing view (detail panel).
- "To sort" section (UI: « À ranger »): `.RPP` or folders outside the convention, with guided move.
- "To adopt" section (UI: « À adopter », cf. §4.2).

### 5.3 Version detail view
Parsing of the `.RPP`, without REAPER:
- top-level tracks (depth 0), with name (`NAME`) and color (`PEAKCOL`, bit `0x1000000` = custom color). Depth computed through `ISBUS <type> <delta>` (validated on the corpus): `ISBUS 0 0` normal track, `ISBUS 1 1` folder start, `ISBUS 2 -n` last track of a folder, closes `n` levels;
- plugins used per track, deduplicated. Observed forms: `<VST "VST3: Name (Vendor)" file.vst3 0 "" uid{guid} ""`, `<VST "VSTi: …" file.dll …`, `<VST "VST: …" file.dll …`, `<JS relative/path ""`. CLAP and AU absent from the corpus **[TO VALIDATE]**;
- **plugins missing** on the machine, by comparison with the REAPER plugin caches, discovered by pattern (`reaper-vstplugins*.ini`, `reaper-clap-*.ini`, `reaper-auplugins*.ini`) rather than by exact name:
  - VST (validated on Windows, `reaper-vstplugins64.ini`): `[vstcache]` section, lines `file=timestamp,uid,Name (Vendor)`; in the key, spaces in the file name are replaced by `_` (`"TDR Kotelnikov.vst3"` → `TDR_Kotelnikov.vst3`);
  - JS (validated, `reaper-jsfx.ini`): lines `NAME relative/path "JS: Name"`;
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
- **Create**: blank, from a template or by duplicating an existing version. New ID; the owner is the current user.
- **Rename** the file and/or modify the label.
- **Delete**: move to `_trash/`.
- **Purge**: permanent deletion from `_trash/`, with confirmation. Then, list of pool media referenced by no version, then purge on confirmation. Purging unreferenced media only applies to `Media/`: `Assets/` is never concerned.
- **History**: browsing and restoring `_versions/` snapshots.

### 5.5 Synchronization
**Checkout**
- By default: full title folder (all versions and referenced media).
- Option: exclude versions. Media referenced only by the excluded versions are then not copied.
- Local storage of the hash (cf. §7.1) of each checked-out file, used as the comparison base.

**Publish**
1. Media normalization: any media outside `Media/` (absolute path, other machine) is copied into it, then the reference is rewritten as relative.
2. Copy of media missing from the remote pool (comparison by name + size + hash).
3. For each modified `.RPP`:
   - **conflict** if the remote hash differs from the base hash: refusal, conflict display, user choice (keep remote, publish as new version, or force);
   - **version of another member**: refused by default, with an offer to save it as a new version under one's own name;
   - **forcing**: only bypasses the ownership check or the conflict after explicit confirmation. The overwritten remote version is first copied into `_versions/`, and a notification event is sent to the owner.
4. Update of the base hashes and emission of an activity event ("X published Y", UI: « X a publié Y »).

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
- Opening in the existing instance (`-nonewinst` on Windows, validated: `reaper.exe -nonewinst <file>.rpp` opens the project in a new tab of the already open instance, without launching a second one; if REAPER is closed, it starts it) **[TO VALIDATE: macOS equivalent]**.
- Any modification of a `.RPP` by the application (adoption, path rewrite, track import) requires the project to be closed in REAPER: warning and confirmation in the MVP.
  - `REAPER.ini` (`projecttabs`, `projecttab1..n`) is not reliable: it is only rewritten occasionally and keeps stale entries (observed: `projecttabs=1` with `projecttab2..9` still present).
  - MVP: if a REAPER process is running, warning and confirmation. Later: REAPER companion script publishing the list of open projects.
  - Validated: REAPER **does not lock** the open `.rpp` (exclusive write open and rename succeeded while the project was open). No lock-based detection is possible, and REAPER will overwrite the modification on the next save of the project: the warning must say so clearly.

### 5.8 Adoption of existing projects (migration)
Included in the MVP (milestone C). Wizard taking over the current folder tree (`proaudio/reaper/projects/<group>/<title>[/<member>]`):
- choice of the target layout, mapping of existing levels to its levels (`_Unassigned` value offered for a missing level, for example the album), then move of the titles into the new structure;
- reading of each `.rpp` to know its path configuration: `RECORD_PATH` (e.g. `audio-files`), `FILE` references of sources (relative, absolute, outside the title folder), `RENDER_FILE` (cf. forms in §5.3). For each case, the report states whether the application can fix it:
  - fix possible: offer to move the files into the right folder (`Media/`, `Renders/`) and to update the `.rpp` accordingly (targeted patch, cf. §7.3);
  - fix impossible (e.g. media not found, absolute path from another machine with no matching file): reported, `.rpp` left intact;
- merge of the per-member subfolders' media into the single pool, with collision handling by hash;
- adoption of each `.RPP` (owner deduced from the subfolder when it exists, asked otherwise);
- deduplication of identical media (same hash);
- dry-run mode with a report before execution.

### 5.9 Collaboration (`collab` mode, through the collab store, cf. §6)
- **Status** per title and per version: `idea`, `writing`, `recording`, `mixing`, `done` (configurable list).
- **Tasks** per title: text, assignee, optional due date, state.
- **Notes** per title or per version.
- **Lyrics** per title, with modification history.
- **Shared assets** per title (scores, tabs, images, PDF, other files):
  - files are stored in the title's `Assets/` and synchronized with the title (§5.5). They are **not versioned** (no `_versions/` history); a deleted asset is moved to the title's `_trash/`;
  - metadata (description, author, optional associated version) is in the collab store (`asset` entity);
  - built-in preview for images and PDF, opening with the system application otherwise;
  - in `local` and `cloud` modes, `Assets/` is available without collaborative metadata.
- **Activity feed**: publications, forced publishes, status changes, new tasks.
- **Notifications**: in the application and OS system notifications.

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
`activity` is append-only (never modified).

Port (pseudo-signature):
```
CollabStore
  upsert(entity, uid, fields)
  delete(entity, uid)
  query(entity, filter)
  subscribe(filter) -> stream of changes
  exportSnapshot() -> CanonicalSnapshot
  importSnapshot(CanonicalSnapshot)      # idempotent upsert by uid, LWW applied
```

### 6.3 Journal adapter (`JournalStore`)
```
<repositoryRoot>/_collab/<memberId>/<yyyy-mm>.jsonl     # append-only, one writer per directory
<repositoryRoot>/_collab/_snapshots/<timestamp>.json    # optional baselines
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
`_library.json` (at the library root; in `cloud` and `collab` modes, in the repository, hence shared by all members):
```json
{
  "libraryId": "...",
  "schemaVersion": 1,
  "mode": "local" | "cloud" | "collab",
  "layout": {
    "levels": [
      { "key": "artist", "label": "Artiste" },
      { "key": "album",  "label": "Album" },
      { "key": "title",  "label": "Titre" }
    ],
    "renderMetadata": { "artist": "artist", "album": "album", "title": "title" },
    "frozen": true
  },
  "collab": {                      // present in collab mode only
    "groupId": "...",
    "store": "journal" | "pocketbase",
    "backendUrl": "https://..."
  }
}
```
Switch procedure (single action in the settings):
1. `exportSnapshot()` from the current adapter.
2. `importSnapshot()` into the target adapter, then verification by count per entity.
3. Writing of `_library.json` with the new store.
4. The other members' applications detect the change of `_library.json` and switch automatically.
5. PocketBase → journal switch: the snapshot is written into `_collab/_snapshots/` as the starting baseline.

---

## 7. Technical architecture

### 7.1 Stack
- **Flutter (desktop) + Dart**, native AOT compilation. Targets: Windows and macOS first, Linux secondary; Android and iOS considered later (§7.4).
- A single language for everything: interface, business logic, input/output.
- Interface: Material 3 with a custom theme (the application's own design system).
- State management: **Riverpod** **[TO VALIDATE at project start]**.
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
  domain/          # pure Dart: entities, rules, sync states, canonical collab model, ports (abstract classes)
  rpp/             # pure Dart: RPP parser/writer (read: tracks, FX, metadata; write: targeted line/chunk patches only)
  collab/          # CollabStore port + adapters
    journal/       # JournalStore adapter (dart:io)
    pocketbase/    # PocketBaseStore adapter (phase 2, no dart:io dependency)
  library/         # libraries, modes, configuration, mode transitions
  repository/      # repository and workspace scanning, layout conventions, adoption (dart:io)
                   # RepositoryStorage port + MountedFolderStorage adapter
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
- **Reliability**: no data loss possible without explicit confirmation; all destructive operations go through the trash or the history.
- **Usability**: usable by non-technical people; musical rather than technical vocabulary; main actions reachable in one click.
- **Distribution**: entirely free and open source tooling; build and publication by CI (GitHub Actions), artifacts published as GitHub Releases.
  - **Windows**: installer (Inno Setup or MSIX) signed for free through **SignPath Foundation** (open source program: public repository, OSI license, signing from CI), to avoid the SmartScreen warning (retained; application to be submitted once the repository is public and the license chosen).
  - **macOS**: **non-notarized** DMG (no paid Apple membership). The Gatekeeper warning on first launch is accepted; the authorization procedure is documented. No test machine available: macOS is built by CI, tested on a "best effort" basis.
  - **Automatic update** (`auto_updater`, WinSparkle / Sparkle, signed appcast feed): check at startup then periodically → "update available" notification (UI: « mise à jour disponible ») → one click → download, installation → restart if needed.
- **License**: GPL-3.0 (`LICENSE`).
- **Application identifier**: `io.github.6wheels.reaharvest` (Windows, macOS); `io.github._6wheels.reaharvest` on Linux (freedesktop rule: a segment cannot start with a digit; format compatible with Flathub verification).
- **Internationalization**: interface in French, prepared for i18n (later publication).

---

## 9. Phases

| Phase | Content |
|---|---|
| **1 — MVP** | Libraries and modes (`local`, `cloud`, `collab`), mode change, configuration, layouts (provided templates + custom), repository conventions, scan and index, navigation, detail view, version management, Checkout / Publish / Release (conflicts, forcing), creation from template, opening in REAPER, adoption wizard. Full `collab` mode: members, ownership and forcing, `CollabStore` port + `JournalStore`, statuses, tasks, notes, lyrics, shared assets, activity, notifications |
| **2 — Backend** | `PocketBaseStore`, one-click switch, authentication; prerequisite for mobile applications |
| **3 — Tools** | Renders: built-in player, on-demand render, render publication (repository and export folders); track import between versions; companion Lua scripts (for example audio render of tracks whose plugins are missing) |

Internal MVP milestones, delivered and tested in this order, each usable on its own:
1. **Milestone A — `local` mode**: configuration and libraries, layouts and free tree, scan and index, navigation, detail view, version management, creation from template, opening in REAPER.
2. **Milestone B — `cloud` mode**: `RepositoryStorage` port + `MountedFolderStorage`, Checkout / Publish / Release, conflict detection, mode change `local` ↔ `cloud`.
3. **Milestone C — `collab` mode**: members, ownership and forcing, `CollabStore` + `JournalStore`, statuses, tasks, notes, lyrics, shared assets, activity, notifications, adoption wizard for existing projects.

Plan from milestone A: local `memberId` and version `owner`, `libraryId`, `_library.json` (including the `collab` block), `groupId`, ULID `uid`, HLC, configurable backend URL, `RepositoryStorage` and `CollabStore` ports.

---

## 10. Open points and risks

1. ~~Format of project and render metadata lines, `EXTSTATE`~~ (validated, §4.2, §5.6).
2. Detection of an open project: neither `REAPER.ini` nor file lock; MVP through process detection, companion script later (§5.7).
3. Reliability of file watching on the streaming Drive volume (§6.3).
4. ~~`reaper.ini` preference keys~~ (validated: peaks only, backups without check, §5.1).
5. Plugin caches: VST and JS validated on Windows; CLAP, AU, macOS and Linux remaining (§5.3).
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
