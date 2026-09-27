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
- Test on the rig before asking for review (see below).

## Deploying to the rig

`brain/deploy.sh` only deploys code that's on GitHub, so the rig always runs a known commit:

```bash
brain/deploy.sh --pr 6 deckdash   # test PR #6 on the rig (a clean checkout of its latest commit)
brain/deploy.sh live deckdash     # put reviewed main back
brain/deploy.sh deckdash          # from your checkout: only if it's a clean main matching origin/main
```

- `--pr` is for testing in the workshop, never during a show. Once the PR is merged, run `brain/deploy.sh live`.
- Push your branch and open the PR first; `--pr` deploys what's on GitHub, not your local changes.
- See what's running: `ssh pi@ravecave.local 'grep . ~/.deployed/*'`
- Dashboard page tweaks can go to `/preview/` from any branch, no PR or checks: `brain/deploy.sh preview`.
- `--force` skips the checks and deploys your checkout as-is. Emergencies only; say so in the PR.
