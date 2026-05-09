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

After the user selects a flow, present the prefix selection:

```
Select a branch prefix:
1. feature/     — New feature or enhancement
2. bugfix/      — Bug fixes
3. hotfix/      — Critical fixes for production
4. release/     — Release preparation
5. chore/       — Maintenance tasks, refactoring
6. experiment/  — Exploratory work, prototypes
```

The user selects a prefix number, then provides the branch name. Construct the full branch name as `<prefix><branch-name>` (e.g., `feature/add-config-system`).

**Feature branch flow:** create and switch to the feature branch with `git checkout -b <full-branch-name>`

**Worktree flow:** use `skill` tool to load `superpowers/using-git-worktrees` skill and follow it to create a worktree. Pass the full branch name when creating the worktree.

**First commit on new branch (feature branch only):**

If the user selected "Create a feature branch" AND there are uncommitted changes in the working tree (carried over from Step 2 where the user chose option 3 "Leave them as-is"), ask after creating the branch:

```
You have uncommitted changes on the new branch <full-branch-name>.
Would you like to commit them now?

1. Yes, commit all changes with a descriptive message
2. No, leave them uncommitted
```

If "Yes", prompt for a commit message, then run `git add -A && git commit -m "<message>"`.

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
