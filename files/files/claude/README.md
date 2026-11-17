# claude-config

My Claude Code user config (`~/.claude`). Only whitelisted files are tracked; see `.gitignore`.
A SessionStart hook in `settings.json` runs `git pull --ff-only` here each time Claude Code starts.

## Set up on a new machine

```sh
gh auth login && gh auth setup-git
cd ~/.claude
git init -b main
git remote add origin https://github.com/v3ai/claude-config.git
git fetch origin
git reset --hard origin/main    # overwrites local settings.json / CLAUDE.md with the repo's
git branch -u origin/main
```

## Push changes

```sh
cd ~/.claude && git add -A && git commit -m "..." && git push
```
