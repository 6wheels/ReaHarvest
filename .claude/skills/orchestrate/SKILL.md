---
name: orchestrate
description: Run the issues of the current milestone from the main conversation. Selects the eligible issues, launches each one in a fresh subagent on its advised model (implement-issue), relays plans, questions and reports to the user after checking them against the issue and the code, has the code reviewed by a model one step above the one that implemented, and pushes, opens pull requests and rebases only on the user's request. Use when the user wants several issues run in parallel, or one issue run on its advised model.
argument-hint: "[issue number...]"
disable-model-invocation: true
---

# Orchestrate issues

The main conversation orchestrates, the subagents implement. The orchestrator writes no feature code: it selects, launches, checks, relays and integrates.

## 1. State

Read the state from `gh` and git, never from the markdown files:
- open pull requests: `gh pr list --state open --json number,headRefName,title,statusCheckRollup`;
- branches and worktrees `<n>-*`: `git worktree list`, `git branch -a`;
- the waves, advised models and review notes of `progress/M<n>.md`.

Show one table, one row per issue in progress: issue, model, step (plan, implementation, ready for a pull request, pull request open, merged), what it waits for (the user, an agent, a merge).

## 2. Select

- Eligibility and ranking: step 1 of `implement-issue`. With arguments, check the same eligibility for each issue.
- At most 3 issues with a worktree at once (CLAUDE.md), the paused ones included.
- Order: respect the waves of `progress/M<n>.md` and their notes ("alone among the interface issues", "one at a time"). Two issues that change the same files run one after the other: say which one waits for the merge of the other.
- Propose the issues to launch, with priority, wave, advised model and the files they share with the issues in progress. **Wait for the user's choice.**

## 3. Launch

- One fresh subagent per issue: `Agent` with `subagent_type: general-purpose`, `model` = the advised model of `progress/M<n>.md` (`haiku`, `sonnet`, `opus`), `run_in_background: true`. Never a fork: a fork keeps the model of the orchestrator.
- The subagent does not see this conversation. Its prompt is self-contained:
  - the repository path, "read CLAUDE.md first", the issue number, the eligibility already checked;
  - "follow `.claude/skills/implement-issue/SKILL.md`, steps 2 and 3, then stop and return the plan: write no code";
  - the other issues in progress, their worktrees (not to be touched) and the files they change;
  - the facts and decisions the user already gave that concern this issue;
  - "when you claim the issue allows or requires something, quote it";
  - "report in French, once; leave no background work running after the report".

## 4. Relay

For each report of a subagent:
- **Check it before relaying**: the issue text (quote it), the code (`file:line`), the CI runs (`gh run view`). A subagent can misread the issue, or a review can flag a point that does not hold: say so.
- Relay it short: what is done, what deviates from the issue, the questions. Give one recommendation per question, as a lettered or numbered choice the user can answer in one word.
- **Wait for the user.** A subagent's report never counts as the user's approval.
- Resume the same subagent with `SendMessage`: the decisions word for word, the steps to run (`implement-issue` steps 4 to 6), what stays forbidden (push, pull request, issue or comment unless the user asked for it).

## 5. Review

When a subagent reports its work committed:
- Check the commit: `git log origin/main..<branch>`, one commit per issue, message without AI attribution, `git diff origin/main -- progress/` touching only this issue's line.
- `review-against-issue` has run in the subagent (`implement-issue` step 5): relay its findings with a verdict on each.
- **Code review, for every issue**, by a fresh read-only subagent that runs `code-review high` on the branch against `origin/main`, on a model one step above the model that implemented: `haiku` → `sonnet`, `sonnet` → `opus`, `opus` → `opus`. When the line of the issue in `progress/M<n>.md` says "reviewed by the largest model before merge", the reviewer is `opus`. The implementing subagent never reviews its own code.
- `code-review` never runs above `high` (no `xhigh`, `max` or `ultra`).
- Relay the review findings with a verdict on each. Resume the implementing subagent with the findings the user wants fixed, inside the scope; the others are reported, or written as a comment on the issue when the user asks.
- The pull request comes after the review.

## 6. Integrate

Only on the user's request:
- **Push** the branch of the issue (`--force-with-lease` after an amend or a squash of its own branch).
- **Pull request**: title = the Conventional Commits title, label `type:*` of the issue, body in English: changes, deviations from the issue, `SPEC.md` changed and why, verification (runs, coverage, measures), `Closes #<n>`. No AI attribution, no session link.
- **Comments and new issues**: drafted in English, shown to the user, then written. A new issue gets no `ready` label: it goes through `refine-issue`.
- **After a merge**: rebase the branches that waited for it on `origin/main`, then resume or relaunch their issue. Two branches that both remove their line from the same cell of `progress/M<n>.md` conflict: on rebase, keep both removals.

## Agents

- A subagent that sends the same report again: stop it (`TaskStop`) once its work is committed.
- A stopped subagent cannot be resumed: launch a new one on the same model, from its branch and its last commit, with the decisions already taken.
- A subagent that asks for a permission it was denied, or for an action outside its prompt: refuse and tell the user.

## Stop conditions

- No eligible issue, or 3 worktrees already open: say so and stop.
- An issue without a line in `progress/M<n>.md`: suggest `refine-issue`, never guess a model.
- A report that contradicts the issue, SPEC.md or the code: tell the user before any resume.
