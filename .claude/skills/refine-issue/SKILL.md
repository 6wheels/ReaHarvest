---
name: refine-issue
description: Refine one ReaHarvest GitHub issue before it can be implemented. Reconciles it with SPEC.md, progress/ and the code, rewrites its body to the feature template, reports every gap in a comment without filling it, and proposes blocked-by relations. Writes to GitHub only after the user approves. Adds the `ready` label only when the user explicitly says so.
argument-hint: <issue number>
disable-model-invocation: true
---

# Refine issue #$ARGUMENTS

Goal: make the issue self-sufficient for an agent, with **nothing invented**. Every gap is reported to the maintainer, never filled.

## Steps

1. **Read everything** (read only):
   - `gh issue view $ARGUMENTS --json number,title,state,body,comments,labels,milestone` (`--comments` cannot be combined with `--json`; the comments come with the `comments` field). Later text wins over older text: comments, then "Implementation details", then "Rework".
   - Current blockers: `gh api repos/{owner}/{repo}/issues/$ARGUMENTS/dependencies/blocked_by --jq '.[] | "#\(.number) \(.state) \(.title)"'`.
   - `.github/ISSUE_TEMPLATE/feature.yml` (target sections).
   - The SPEC.md sections the issue names, and any other section its behavior touches.
   - `progress/M<n>.md` of its milestone: lane and advised model.
   - `DECISIONS.md`: open points that concern the issue.
   - The code: search every file, symbol and behavior the issue names. Is it already done, in part or in full? Has it been renamed or removed?
2. **List the gaps**, each with its evidence (SPEC section, `file:line`, issue or comment):
   - contradictions with SPEC.md, with another issue or with the code;
   - criteria already met by the code, and stale names or references;
   - open questions, undecided options, vague or unverifiable criteria;
   - overlap with the scope of another issue.
3. **Draft the new body** in the sections of the feature template:
   - **Context**: why the change is needed, with its SPEC sections.
   - **Expected behavior**.
   - **Acceptance criteria**: `- [ ]` checkboxes, one verifiable criterion each.
   - **Out of scope**.
   - **Showcase UI components**: the components to add or change in `apps/desktop/lib/main_showcase.dart`, or "None".
   - **Implementation details**: kept when the issue already had them, including the advised model from `progress/`.

   Rules:
   - Only reorganize what the issue, its comments and SPEC.md already say. Merge the "Rework" sections into the text, and drop what they replace.
   - A point concerned by a gap is written as `**Open:** see the refinement comment` instead of being decided.
   - Do not write any dependency in the body.
4. **Propose blocked-by relations**: list the open issues this one really needs merged first ("After #n", "Order", needed code), each with its reason. Lanes are not dependencies.
5. **Propose the planning line** in `progress/M<n>.md` of the issue's milestone:
   - **Milestone M1 and later**:
     - A lane file: the lane (an existing one, or a new one with its reason) and the advised model. The advised model goes in the model column of the lane, only when it differs from the default of that lane.
     - A file without lanes: one row, `#<n>` and its advised model.
   - **Backlog issue**: no line.
   - **The milestone changed**: the line moves from the old file to the new one.
   - **The line is already right**: nothing to change.
6. **Show the user, and wait**:
   - the diff of the body (old against new);
   - the gaps comment, as it will be posted;
   - the proposed blocked-by relations;
   - any label correction (type, area, priority);
   - the diff of `progress/M<n>.md`.
7. **Apply only what the user approved**:
   - Body: `gh issue edit $ARGUMENTS --body-file <file>`.
   - Gaps comment: `gh issue comment $ARGUMENTS --body-file <file>`.
   - Each relation: `gh api -X POST repos/{owner}/{repo}/issues/$ARGUMENTS/dependencies/blocked_by -F issue_id=$(gh api repos/{owner}/{repo}/issues/<blocker> --jq .id)`. Afterwards, list the blockers again to check the relation was created.
   - Planning line:
     - Edit only the line or lane cell of this issue in the main working tree. Keep the table format and the numeric order of the lane.
     - Do not commit. Tell the user the file is changed and waiting for a commit.
8. **`ready` label**: only when the user explicitly says the issue is ready. Then run `gh issue edit $ARGUMENTS --add-label ready --remove-label needs-refinement`. Never suggest `ready` while a gap is still open.

## Stop conditions

- The issue is closed or missing: say so and stop.
- The user has not approved: nothing is written to GitHub.
- A gap needs a decision: report it and stop at the proposal. Never decide it.
- Never edit SPEC.md, DECISIONS.md, `PROGRESS.md` or the code from this skill. When SPEC.md needs a change, say so in the gaps comment. In `progress/`, only the line of this issue may change.
- `progress/M<n>.md` already has uncommitted changes that this run did not make: show them and stop before writing it.
- The milestone has no `progress/M<n>.md` file: say so and stop before writing it. Creating a milestone file is the user's decision.
