---
name: review-against-issue
description: Review a diff against one ReaHarvest issue, point by point. Gives a verdict for each acceptance criterion, flags every change outside the scope or touching an out-of-scope item, and checks the CLAUDE.md rules. Read-only; runs in a subagent and returns a report. Use before committing an issue's work, or when asked to check a branch against its issue.
argument-hint: <issue number> [base ref, default origin/main]
context: fork
agent: general-purpose
allowed-tools: Read, Grep, Glob, Bash(gh issue view:*), Bash(git diff:*), Bash(git status:*), Bash(git merge-base:*)
---

# Review the diff against issue $ARGUMENTS

Read-only: change no file, write nothing to GitHub, commit nothing.

## Steps

1. **Load the issue**: `gh issue view <n> --comments`. Extract:
   - the acceptance criteria (checkboxes);
   - the expected behavior;
   - the out-of-scope items;
   - the showcase components;
   - the coverage suites named in the Done section.

   Later text wins over older text.
2. **Load the diff**: `git diff <base>...HEAD`, plus the uncommitted changes (`git diff HEAD`) and the untracked files (`git status --short`). The default base is `origin/main`.
3. **Check each criterion** and give it one verdict:
   - `MET`: give the code that does it as `file:line`, and the test that proves it.
   - `PARTIAL`: say what is missing.
   - `NOT MET`.
   - `NOT VERIFIABLE`: say why, for example a hand check in REAPER.
4. **Check the scope**:
   - Map every hunk to the criterion it serves. A hunk with no criterion is `OUT OF SCOPE`.
   - A hunk that touches an out-of-scope item is a `VIOLATION`.
   - Test files are mapped to the criterion they test.
5. **Check the cross-cutting rules of `CLAUDE.md`**:
   - pure Dart in `domain` and `rpp`;
   - adapters wired at the entry point only;
   - RPP targeted patches and atomic writes;
   - no blocking work on the UI isolate;
   - tokens only in UI code, and states shown as the issue specifies them;
   - new texts in both ARB files;
   - showcase updated for the listed components, with a golden test;
   - tests present for each criterion.
6. **Report**, in this form:
   - a table with one row per criterion: verdict and evidence;
   - the list of `OUT OF SCOPE` and `VIOLATION` hunks (`file:line`, one-line reason);
   - the rule findings;
   - **Verdict**: `PASS` only when every criterion is `MET` or justified `NOT VERIFIABLE`, and there is no `VIOLATION` and no unexplained `OUT OF SCOPE`. Otherwise `FAIL`, with the shortest list of what blocks.

## Stop conditions

- The issue has no acceptance criteria: report "issue not refined: run refine-issue first" and stop.
- The diff is empty: report it and stop.
- Never fix, suggest code or rewrite the issue: report only.
