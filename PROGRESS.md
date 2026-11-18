# ReaHarvest — Progress

Re-oriented MVP (SPEC §9): move the band (3 members, Windows) onto a structured shared Drive folder, with a simple app to check out, publish and manage versions. Deliver the milestones in order; each one is usable on its own. Off-path work waits in the **Backlog** milestone on GitHub.

| Milestone | State | Tickets, order, lanes and advised models |
|---|---|---|
| M0 — Foundations | closed | [progress/M0.md](progress/M0.md) |
| M1 — Migration | **in progress** | [progress/M1.md](progress/M1.md) |
| M2 — Join and sync | next | [progress/M2.md](progress/M2.md) |
| M3 — Shared statuses and activity | later | [progress/M3.md](progress/M3.md) |

Dated decisions and the points left to the maintainer: [DECISIONS.md](DECISIONS.md) (not needed by agents).

## Brief common to every ticket
- Read the ticket in full with its comments: a "Rework (2026-11-14)" section, then its "Implementation details", win over the older text below them when they differ. Read the SPEC sections it names, and the plan of its milestone file. Counts and names given in a ticket are indicative: search the code.
- A plan table lists lanes or steps: a ticket starts when the tickets before it in its lane, and those named in its row, are merged. At most 3 agents at once, one worktree and branch per ticket.
- Stay in the scope of the ticket: no refactoring nor feature beyond it; what it calls out of scope stays out. Deferred or discovered work is written as a comment on the related ticket.
- Done means: `flutter analyze` clean, `dart tool/coverage.dart <suite>` passing for every suite named in the ticket (coverage gate 95–100 %, justified exclusions), texts in both ARB files, the integration test of the feature written and its line ticked in the integration tests ticket of the milestone when the ticket asks for it, the box of the ticket ticked in its milestone file.
- `SPEC.md` already states the target of every ticket: it changes only when a ticket finds a gap in it, and the pull request says so.
- Fixtures are saved by REAPER, never edited by hand, and hold no plugin storing a path (`test/fixtures/README.md`); a special file a test needs is built by the test.
- The tests of `packages/repository` share an in-memory `RepositoryStorage` with injected failures (`test/memory_storage.dart`): reuse it.
- Not for an agent: the points in `DECISIONS.md`, the hand validation of each milestone.
