---
name: workspace-setup
description: Use before stargin new feature / change to ensure the working environment is ready - checks branch, handles dirty files, offers worktree or feature branch flow
---

# Workspace Setup

Prepare the working environment for new change. This skill ensures you are not on main/master, handles uncommitted changes, and optionally sets up a git worktree for isolation.

**Core principle:** Never start new feature / change without a clean working environment.

**Announce at start:** "I'm checking the workspace before we begin brainstorming."

## The Process

### Step 1: Check Current Branch

```bash
git branch --show-current
```

**If not on `main` or `master`:**

Ask the user if he wants to proceed:

```
You are on the <current branch name> branch. Do you want to proceed?
```

**If "yes": continue**

**If "no": STOP, do not continue with any work and await for users instructions.**

### Step 2: Check for Uncommitted Changes

```bash
git status --porcelain
```

**If no changes:** Proceed to Step 3

**If changes exist:**

Present them to the user, grouped by status:

```
Your workspace has uncommitted changes:

Modified:
  - src/utils/helpers.ts
  - docs/specs/auth-redesign.md

Untracked:
  - docs/plans/auth-redesign.md

Staged:
  - src/config.ts
```

Then offer options:
```
What would you like to do with these changes?

1. Stash all (restore after execution with `git stash pop`)
2. Commit them and push changes.
3. Leave them as-is (proceed with dirty working tree)
```


### Step 3: Prepare working environment.
Ask the user how they want to proceed:

```
You are on the <name of current branch> branch. Before executing a plan, you need an isolated workspace.

1. Create a feature branch (stays in this directory)
2. Create a git worktree (isolated directory, recommended for larger work)

Which would you prefer?
```

**Feature branch flow:** create and switch to the feature branch

**Worktree flow:** use `skill` tool to load `superpowers/using-git-worktrees` skill and follow it to create a worktree.

### Step 4: Report

```
Workspace ready.
Branch: <branch-name>
Working directory: <path>
Status: clean | <N> uncommitted changes (user chose to keep)

Ready to execute plan.
```

## Red Flags

**Never:**
- Start work on main/master without user consent
- Stash or discard changes without user consent
- Copy files into worktree without user consent
- Skip the branch check
- Assume the user wants a particular flow

**Always:**
- Present clear options and let the user decide
- Report the final workspace state before handing off to execution
- Load `using-git-worktrees` skill for worktree creation (don't improvise)
