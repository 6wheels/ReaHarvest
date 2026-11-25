---
name: implement-issue
description: Implement one `ready` ReaHarvest issue. Without an argument, selects the eligible issue (open, `ready`, current milestone, every blocker closed) by priority and wave, and proposes it. Then writes a plan for the user to validate, implements only the acceptance criteria, runs format, analyze and tests, reviews the diff against the issue, and commits with a message that references the issue. Also run by `orchestrate` in a subagent.
argument-hint: "[issue number]"
disable-model-invocation: true
---

# Implement an issue

**In a subagent** (launched by `orchestrate`): the user does not see this conversation. Each "wait for the user" below means: end with your report and stop; you are resumed with the user's decisions. Report in French, once, and leave no background work running after it. Push, open a pull request, or write to GitHub only when your prompt says so.

## 1. Select the issue

- **Current milestone**: the lowest open milestone whose title starts with `M` (`gh api repos/{owner}/{repo}/milestones?state=open --jq '.[].title'`).
- **Without an argument**:
  - Candidates: `gh issue list --state open --milestone "<current>" --label ready --json number,title,labels`.
  - Keep a candidate only when all its blockers are closed: `gh api repos/{owner}/{repo}/issues/<n>/dependencies/blocked_by --jq '[.[] | select(.state == "open")] | length'` must be `0`.
  - Rank by `priority:high`, then `medium`, then `low`. Within a priority, prefer the earliest wave of `progress/M<n>.md`, then an issue that changes no file of an issue in progress (open pull request, branch `<n>-*`). Then take the lowest number.
  - Propose the first one, with its priority, wave, advised model and the reason for the choice, plus up to two alternatives. **Wait for the user's choice.**
- **With an argument**: check the same eligibility. When the issue is not eligible, say why and stop.

## 2. Prepare

- Read the issue with its comments, the SPEC.md sections it names, and its line in `progress/M<n>.md`. When the advised model differs from the current model, tell the user.
- Count the running work: at most 3 agents at once. When 3 issues already have an open branch or worktree, stop and say so.
- Create a worktree and a branch from an up-to-date `main`: `git fetch origin && git worktree add ../ReaHarvest-worktrees/<n>-<slug> -b <n>-<slug> origin/main`. Work only inside it.

## 3. Plan, then wait

Present the plan:
- one entry per acceptance criterion, with the files to change and the test that proves it;
- the out-of-scope items, restated;
- the showcase components to add or change (through the `add-ui-component` skill);
- the coverage suites to run.

**Wait for the user's validation.** A change to the plan is validated again.

## 4. Implement

- Write only what the acceptance criteria need: no refactoring, no feature, no cleanup beyond them.
- Follow `CLAUDE.md`: Rules, UI, Performance.
- Deferred or discovered work: ask the user, then write it as a comment on the issue (`gh issue comment`).

## 5. Verify

- `dart format .`, then `flutter analyze` with no issue.
- `dart tool/coverage.dart <suite>` for every suite the issue names, plus the suites of every package changed.
- The integration test, when the issue asks for one, and its line ticked in the integration tests issue of the milestone.
- New texts in both ARB files.
- Run the `review-against-issue` skill on the diff. Fix the confirmed findings that are inside the scope; report the others to the user, with your verdict on each.
- In a subagent, do not run `code-review`: `orchestrate` has it run by another agent after your commit, when the user wants it, and resumes you with the findings to fix. Alone, run the `code-review` skill at level `high` on the branch against `origin/main` (never a level above `high`), and handle its findings the same way.

## 6. Commit

- **Planning line**, in the worktree of the issue, and only when the commit closes the issue (`Closes`):
  - Remove `#<n>` from `progress/M<n>.md`: the issue number from its wave or lane cell, or its row in a file without waves.
  - When a wave or lane is left with no issue, remove its row, and its model note if it named this issue.
  - Change nothing else. Run `git diff progress/` to check that only this issue's line changed.
  - The removal goes into the same commit as the code, so that it is merged with it.
  - With `Rel #<n>`, the file stays unchanged.
- Conventional Commits: `<type>(<scope>): <description>`, in English, imperative mood. The body references the issue (`Closes #<n>` when every criterion is met, `Rel #<n>` otherwise). No AI attribution and no session link.
- Show the message, then commit. Push or open a pull request only when the user asks. In a subagent, the message goes into your report.
- One commit per issue: squash the fixes and diagnosis commits of the branch before the pull request.
- A pull request, when asked: its title is the Conventional Commits title of the change, and it carries the `type:*` label of its issue (`gh pr create --label type:<kind>`): the release notes group the pull requests by this label.

## Stop conditions

- No eligible issue: say why (none `ready`, all blocked, milestone closed) and stop.
- An eligible issue has no line in `progress/M<n>.md` (no wave, no model): say so and suggest `refine-issue`. Never guess a wave or a model.
- At commit time, the issue's line is missing from `progress/M<n>.md`, or the diff of `progress/` touches another issue: stop and show it. Never fix another issue's line.
- An issue that is not `ready`, or that has an open blocker: stop. Never implement it, even when asked by number.
- A criterion that is ambiguous, contradicts SPEC.md or the code, or needs a decision: stop and ask (CLAUDE.md, "When in doubt").
- The plan has not been validated: write no code.
- Analyze, tests or the coverage gate fail and cannot be fixed inside the scope: stop and report the output. Never lower a threshold, never skip a test, never add a coverage exclusion without a written reason.
- The review finds a criterion not met: do not commit with `Closes`.
