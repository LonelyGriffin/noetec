---
name: git-github-workflow
description: "The noetec GitHub PR workflow: branch-per-issue (NOET-XX), isolate your worktree via `multica repo checkout`, source agent-gh.sh for the App token, push, open a PR with 'Closes NOET-XX', and review via 'gh pr review'. Use when committing, pushing, opening a PR, or reviewing."
---

# Git & GitHub PR workflow

Code flows through GitHub PRs (`https://github.com/LonelyGriffin/noetec.git`). Multica issues track status; **GitHub PRs are the review surface**.

## Isolate your worktree first (mandatory)

All agents share one machine, so a plain `git checkout` in a shared directory moves
the branch under every other agent and strands their uncommitted work — never do it.
Every task works in its OWN isolated git worktree:

1. From the task workdir, run
   `multica repo checkout https://github.com/LonelyGriffin/noetec.git`
   → creates `<task-workdir>/noetec`, a linked worktree backed by the daemon's
   bare clone cache, on a fresh `agent/<role>/<task-id>` branch at the latest
   `origin/main`.
2. `cd noetec`, then branch off the remote:
   - new work: `git checkout -b NOET-XX`
   - continue an existing branch: `git checkout -b NOET-XX origin/NOET-XX`
3. Do all work in that worktree. The legacy shared clone at
   `/home/noetec-agent/projects/noetec` is forbidden — treat it as read-only.
   Never `git checkout` / `git reset` / `git rebase` there.

## Commit, push, PR

- Branch per issue: `NOET-XX`. PR title `NOET-XX: <summary>`, body includes `Closes NOET-XX` (auto-closes the issue on merge).
- Before committing/pushing, run `source $HOME/.config/noetec-gh-app/agent-gh.sh <role>` (roles: `architect` | `developer` | `qa`). It sets your per-agent commit identity, a fresh GitHub App token, and routes all GitHub traffic over HTTPS through the App (never your own SSH key). Re-run it right before push (the token lives ~60 min), and source + push in the SAME shell — the exported `GH_TOKEN` does not survive a new shell.
- Push: `git push -u origin NOET-XX`. Open PR: `gh pr create --base main --head NOET-XX --title "NOET-XX: ..." --body "…\n\nCloses NOET-XX"`.
- Review: the Architect posts a verdict with `gh pr review <PR> --comment`. There is NO `gh pr approve` command, and the App cannot approve its own PR (GitHub returns "Can not approve your own pull request") — so the formal approve + merge is done by Павел on GitHub.

Only Павел approves and merges — that rule lives in CLAUDE.md hard rules and always applies.
