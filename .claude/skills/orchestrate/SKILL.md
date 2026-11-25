---
name: orchestrate
description: Run the issues of the current milestone from the main conversation. Selects up to 3 ready issues that can run in parallel (across one or more waves), proposes them with the advised implementation model and the advised review (needed or not, model, level), and after the user's approval launches one background subagent per issue (implement-issue). Then relays plans, questions and reports after checking them against the issue and the code, has the code reviewed on the model and level the user confirmed, and pushes, opens pull requests and rebases only on the user's request.
disable-model-invocation: true
---

# Orchestrate issues

The main conversation orchestrates, the subagents implement. The orchestrator writes no feature code: it selects, launches, checks, relays and integrates. It takes no argument: it picks the issues itself.

## 1. State

Read the state from `gh` and git, never from the markdown files:
- open pull requests: `gh pr list --state open --json number,headRefName,title,statusCheckRollup`;
- branches and worktrees `<n>-*`: `git worktree list`, `git branch -a`;
- the waves, advised models and review notes of `progress/M<n>.md`.

When work is in progress, show one table, one row per issue: issue, model, step (plan, implementation, review, ready for a pull request, pull request open), what it waits for (the user, an agent, a merge).

## 2. Select

- **Candidates**: eligibility of step 1 of `implement-issue` (current milestone, open, `ready`, every blocker closed), from any wave: an issue of a later wave is a candidate as soon as its blockers are closed.
- **Slots**: 3 minus the issues that already have a worktree (paused ones included). No slot left: say so and stop.
- **Parallel**: two issues run together only when neither blocks the other, they change no common file (read each issue's files and the notes of `progress/M<n>.md`: "one at a time", "same files", "alone among the interface issues"), and neither changes a file of an issue in progress.
- **Pick** by priority (`priority:high`, `medium`, `low`), then the earliest wave, then the lowest number, up to the free slots.
- **Not parallel**: give the order (which one waits for the merge of which, and why). Nothing can run in parallel: say why (blockers, shared files, notes), and propose the single best issue.

## 3. Propose, then wait

Show one table, one row per selected issue:

| Issue | Title | Priority | Wave | Implementation model | Review | Review model | Review level |
|---|---|---|---|---|---|---|---|

- **Implementation model**: the advised model of `progress/M<n>.md`. No line for the issue: suggest `refine-issue`, never guess.
- **Review needed**: yes by default. No when the diff is expected small and without logic (texts, theme values, a kit component already covered by goldens) and the issue is advised on Haiku: `review-against-issue` in the subagent is then enough.
- **Review model and level** (the level of `code-review`, also the `effort` of the reviewer agent):
  - default: `sonnet`, `medium`;
  - `opus`, `high` only when the line of the issue says "reviewed by the largest model before merge", or the issue touches the RPP writer, a destructive operation, the sync or the index format;
  - never above `high` (no `xhigh`, `max` or `ultra`).
- Add the order and the files shared, then the reasons for the issues left out (blocked, shared files, no slot).
- These advices are refined later: after the plan (scope larger or smaller than expected), and after the commit (size and nature of the diff).

**Wait for the user's approval.** The user may change the selection, a model, the review or its level.

## 4. Launch

- Once approved, launch every approved issue in the same message: one fresh subagent per issue, `Agent` with `subagent_type: issue-implementer` (`.claude/agents/`), `model` = the approved implementation model (`haiku`, `sonnet`, `opus`), `run_in_background: true`. Never a fork: a fork keeps the model of the orchestrator.
- The subagent does not see this conversation. Its prompt is self-contained:
  - the repository path, "read CLAUDE.md first", the issue number, the eligibility already checked;
  - "follow `.claude/skills/implement-issue/SKILL.md`, steps 2 and 3, then stop and return the plan: write no code";
  - the other issues launched or in progress, their worktrees (not to be touched) and the files they change;
  - the facts and decisions the user already gave that concern this issue;
  - "when you claim the issue allows or requires something, quote it";
  - "report in French, once; leave no background work running after the report".

## 5. Relay

For each report of a subagent:
- **Check it before relaying**: the issue text (quote it), the code (`file:line`), the CI runs (`gh run view`). A subagent can misread the issue, or a review can flag a point that does not hold: say so.
- Relay it short: what is done, what deviates from the issue, the questions. Give one recommendation per question, as a lettered or numbered choice the user can answer in one word.
- With a plan, restate the approved review advice and say whether the plan changes it.
- **Wait for the user.** A subagent's report never counts as the user's approval.
- Resume the same subagent with `SendMessage`: the decisions word for word, the steps to run (`implement-issue` steps 4 to 6), what stays forbidden (push, pull request, issue or comment unless the user asked for it).

## 6. Review

When a subagent reports its work committed:
- Check the commit: `git log origin/main..<branch>`, one commit per issue, message without AI attribution, `git diff origin/main -- progress/` touching only this issue's line.
- `review-against-issue` has run in the subagent (`implement-issue` step 5): relay its findings with a verdict on each.
- **Confirm the review**: show the diff size (`git diff --stat origin/main...<branch>`) and propose the review again (needed or not, model, level) with the rules of step 3, adjusted to the actual diff. **Wait for the user's confirmation** before launching it.
- The review runs in a fresh read-only subagent: `subagent_type: issue-reviewer`, `model` and `effort` as confirmed, `run_in_background: true`. Its prompt names the worktree of the issue, the branch, and the level: it runs `code-review <level> <branch>` from that worktree, with the branch as explicit target. The implementing subagent never reviews its own code.
- Before reporting, the reviewer checks that the reviewed diff is the one of `git diff origin/main...<branch>`: an empty or different diff is reported, never reviewed.
- Relay the review findings with a verdict on each. Resume the implementing subagent with the findings the user wants fixed, inside the scope; the others are reported, or written as a comment on the issue when the user asks.
- The pull request comes after the review, or after the user decided to skip it.

## 7. Integrate

Only on the user's request:
- **Push** the branch of the issue (`--force-with-lease` after an amend or a squash of its own branch).
- **Pull request**: title = the Conventional Commits title, label `type:*` of the issue, body in English: changes, deviations from the issue, `SPEC.md` changed and why, verification (runs, coverage, measures), `Closes #<n>`. No AI attribution, no session link.
- **Comments and new issues**: drafted in English, shown to the user, then written. A new issue gets no `ready` label: it goes through `refine-issue`.
- **After a merge**: rebase the branches that waited for it on `origin/main`, then resume or relaunch their issue. Two branches that both remove their line from the same cell of `progress/M<n>.md` conflict: on rebase, keep both removals. A freed slot: offer to run step 2 again.

## Agents

- A subagent that sends the same report again: stop it (`TaskStop`) once its work is committed.
- A stopped subagent cannot be resumed: launch a new one on the same model, from its branch and its last commit, with the decisions already taken.
- A subagent that asks for a permission it was denied, or for an action outside its prompt: refuse and tell the user.

## Stop conditions

- No eligible issue, or 3 worktrees already open: say so and stop.
- An issue without a line in `progress/M<n>.md`: suggest `refine-issue`, never guess a model.
- A report that contradicts the issue, SPEC.md or the code: tell the user before any resume.
