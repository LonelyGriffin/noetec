---
name: git-github-workflow
description: "The noetec GitHub PR workflow: branch-per-issue (NOET-XX), source agent-gh.sh for the App token, push, open a PR with 'Closes NOET-XX', and review via 'gh pr review'. Use when committing, pushing, opening a PR, or reviewing."
---

# Git & GitHub PR workflow

Code flows through GitHub PRs (`https://github.com/LonelyGriffin/noetec.git`). Multica issues track status; **GitHub PRs are the review surface**.

- Branch per issue: `NOET-XX`. PR title `NOET-XX: <summary>`, body includes `Closes NOET-XX` (auto-closes the issue on merge).
- Before committing/pushing, run `source $HOME/.config/noetec-gh-app/agent-gh.sh <role>` (roles: `architect` | `developer` | `qa`). It sets your per-agent commit identity, a fresh GitHub App token, and routes all GitHub traffic over HTTPS through the App (never your own SSH key). Re-run it right before push (the token lives ~60 min), and source + push in the SAME shell — the exported `GH_TOKEN` does not survive a new shell.
- Push: `git push -u origin NOET-XX`. Open PR: `gh pr create --base main --head NOET-XX --title "NOET-XX: ..." --body "…\n\nCloses NOET-XX"`.
- Review: the Architect posts a verdict with `gh pr review <PR> --comment`. There is NO `gh pr approve` command, and the App cannot approve its own PR (GitHub returns "Can not approve your own pull request") — so the formal approve + merge is done by Павел on GitHub.

Only Павел approves and merges — that rule lives in CLAUDE.md hard rules and always applies.
