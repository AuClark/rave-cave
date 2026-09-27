# Contributing

`main` is protected. All changes come in through a pull request that the repo owner approves.

## Workflow

1. Start from an up-to-date `main`:
   ```bash
   git checkout main && git pull
   git checkout -b your-name/short-description     # e.g. moginie/pyramid-pixel-map
   ```
2. Commit your work on that branch and push it:
   ```bash
   git push -u origin your-name/short-description
   ```
3. Open a pull request into `main` (GitHub offers a link after the push, or run `gh pr create`). Fill in the template.
4. The owner (@AuClark) reviews. Pushing new commits resets any approval, so it's re-reviewed.
5. Once approved and all review comments are resolved, it's merged and the branch is deleted automatically.

Direct pushes, force-pushes and deleting `main` are blocked.

## Keeping your branch current

If `main` moves on while you work:
```bash
git fetch origin
git merge origin/main        # or: git rebase origin/main
```

## Conventions

- Layout and docs: see the [README](README.md). Code for a part goes in `brain/` or `fixtures/`; its documentation goes in `docs/`.
- Secrets and site values (Wi-Fi SSID/password, IP overrides) go in `.env` (git-ignored, see `.env.example`), never in commits.
- Test on the rig before asking for review: `brain/deploy.sh` pushes brain code to the CM4.
