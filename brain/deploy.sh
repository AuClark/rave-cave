#!/usr/bin/env bash
# Push code from this repo to the rig and restart what changed.
#
#   brain/deploy.sh            # every brain service (deckdash, showbrain, mixer, projector, visuals)
#   brain/deploy.sh deckdash   # just one service
#   brain/deploy.sh web        # dashboard page only (no restart)
#   brain/deploy.sh preview    # page to /preview/ for testing
#   brain/deploy.sh showbrain
#   brain/deploy.sh mixer      # DJM-450 USB bridge
#   brain/deploy.sh projector  # projection-mapping page on :8100
#   brain/deploy.sh visuals    # generative visuals control on :8110 (needs projector deployed too)
#   brain/deploy.sh tools      # brain/tools to ~/tools (set_pin.py: the admin PIN)
#   brain/deploy.sh pyramid    # pyramid receiver on rave-box (restart needs sudo there)
#   brain/deploy.sh panel      # HUB75 panel receiver on rave-box
#
# Where the code comes from (put these before the target):
#   brain/deploy.sh ...            this checkout; must be a clean main that matches origin/main
#   brain/deploy.sh --pr 6 ...     a clean checkout of PR #6's latest commit (workshop testing only)
#   brain/deploy.sh live ...       a clean checkout of origin/main (back to reviewed code)
#   brain/deploy.sh --force ...    this checkout as-is, skipping the checks (emergencies)
#
# Each deploy records what's running in ~/.deployed/<target> on the host:
#   ssh pi@ravecave.local 'grep . ~/.deployed/*'
#
# Hosts default to their .local names; override in the repo-root .env (see .env.example).
set -euo pipefail
cd "$(dirname "$0")/.."
[[ -f .env ]] && set -a && . ./.env && set +a
# Settings renamed RAVE_* -> S5_* (Sektor5); the old names still work.
S5_BRAIN_HOST=${S5_BRAIN_HOST:-${RAVE_BRAIN_HOST:-}}
S5_BOX_HOST=${S5_BOX_HOST:-${RAVE_BOX_HOST:-}}
BRAIN=${PI:-pi@${S5_BRAIN_HOST:-ravecave.local}}
BOX=${BOX:-raver@${S5_BOX_HOST:-rave-box.local}}

force=0 src=here
while [[ $# -gt 0 ]]; do
  case $1 in
    --force) force=1; shift ;;
    --pr) src=pr; pr=${2:?--pr needs a PR number}; shift 2 ;;
    live) src=live; shift ;;
    *) break ;;
  esac
done
what=${1:-all}

die() { echo "deploy: $*" >&2; exit 1; }

# Record what's now running: one line per target in ~/.deployed/ on the host that runs it.
mark() {
  local host=$BRAIN targets=$what
  [[ $what == pyramid || $what == panel ]] && host=$BOX
  [[ $what == all ]] && targets="deckdash showbrain mixer projector"
  local line="$1 @ $2, $(date '+%F %T') by $(git config user.name || whoami)"
  ssh "$host" "mkdir -p ~/.deployed && for t in $targets; do echo '$line' > ~/.deployed/\$t; done"
}

# Top-level call (not the re-run inside a clean checkout below).
if [[ -z ${DEPLOY_LABEL:-} ]]; then
  git fetch -q origin main 2>/dev/null || echo "deploy: can't reach GitHub; checking against the last fetched origin/main" >&2

  if [[ $src != here ]]; then
    if [[ $src == pr ]]; then
      git fetch -q origin "pull/$pr/head" || die "couldn't fetch PR #$pr"
      ref=$(git rev-parse FETCH_HEAD) label="PR #$pr"
    else
      ref=$(git rev-parse origin/main) label=main
    fi
    sha=$(git rev-parse --short "$ref")
    tmp=$(mktemp -d)
    trap 'git worktree remove --force "$tmp" >/dev/null 2>&1 || true' EXIT
    git worktree add -q --detach "$tmp" "$ref"
    [[ -f .env ]] && cp .env "$tmp/.env"
    echo "deploying $what from $label @ $sha"
    # Run that commit's own deploy script; older ones don't know about markers, so mark from here.
    DEPLOY_LABEL=$label "$tmp/brain/deploy.sh" "$what"
    mark "$label" "$sha"
    exit
  fi

  branch=$(git branch --show-current) sha=$(git rev-parse --short HEAD)
  dirty=$(git status --porcelain -- brain fixtures)
  if [[ $what == preview ]]; then     # scratch copy of the page: any branch, no checks
    label="preview from $branch${dirty:+ +uncommitted}"
  elif [[ $force == 0 ]]; then
    [[ $branch == main ]] || die "on '$branch', not main. Test a PR with 'brain/deploy.sh --pr N $what', or use --force."
    [[ -z $dirty ]] || die "uncommitted changes under brain/ or fixtures/. Commit them via a PR, or use --force."
    [[ $(git rev-parse HEAD) == $(git rev-parse origin/main) ]] ||
      die "local main isn't origin/main (git pull --ff-only first), or deploy it with 'brain/deploy.sh live $what'."
    label=main
  else
    label="local $branch${dirty:+ +uncommitted} (forced)"
  fi
  trap '[[ $? == 0 ]] && mark "$label" "$sha"' EXIT
fi

if [[ $what == all || $what == deckdash ]]; then
  rsync -a brain/deckdash/DeckDash.java brain/deckdash/Timeline.java brain/deckdash/Library.java brain/deckdash/TempoMaster.java brain/deckdash/SystemInfo.java brain/deckdash/Auth.java "$BRAIN":deckdash/
  rsync -rlt --omit-dir-times brain/deckdash/web/ brain/common/web/s5auth.js "$BRAIN":/srv/rave/deckdash-web/
  # Compile to classes.new and swap only on success, so a failed build leaves the running one alone.
  ssh "$BRAIN" 'cd ~/deckdash && rm -rf classes.new && javac -cp "lib/*" -d classes.new DeckDash.java Timeline.java Library.java TempoMaster.java SystemInfo.java Auth.java && rm -rf classes && mv classes.new classes && sudo systemctl restart deckdash && echo "deckdash restarted"'
fi

if [[ $what == web ]]; then       # page only: no compile, no restart (the page is re-read on every request)
  rsync -rlt --omit-dir-times brain/deckdash/web/ brain/common/web/s5auth.js "$BRAIN":/srv/rave/deckdash-web/ && echo "dashboard page updated"
fi

if [[ $what == preview ]]; then   # work-in-progress page at http://ravecave.local:8080/preview/
  rsync -rlt --omit-dir-times brain/deckdash/web/ brain/common/web/s5auth.js "$BRAIN":/srv/rave/deckdash-preview/ && echo "preview updated: http://${S5_BRAIN_HOST:-ravecave.local}:8080/preview/"
fi

if [[ $what == all || $what == showbrain ]]; then
  rsync -a --exclude overrides.json --exclude __pycache__ --exclude .env brain/showbrain/ "$BRAIN":showbrain/
  rsync -a brain/common/s5auth.py brain/common/web/s5auth.js "$BRAIN":showbrain/     # admin PIN (shared)
  [[ -f .env ]] && rsync -a .env "$BRAIN":showbrain/.env     # site config, never committed
  ssh "$BRAIN" 'sudo systemctl restart showbrain && echo "showbrain restarted"'
fi

if [[ $what == all || $what == mixer ]]; then
  rsync -a brain/mixer/ "$BRAIN":mixer/
  ssh "$BRAIN" 'sudo systemctl restart mixer 2>/dev/null && echo "mixer restarted" || echo "mixer service not installed (see docs/brain.md)"'
fi

if [[ $what == all || $what == projector ]]; then
  rsync -rlt --omit-dir-times --exclude __pycache__ --exclude layouts brain/projector/ "$BRAIN":/srv/rave/projector/
  rsync -rlt --omit-dir-times brain/common/s5auth.py "$BRAIN":/srv/rave/projector/ && rsync -rlt --omit-dir-times brain/common/web/s5auth.js "$BRAIN":/srv/rave/projector/web/
  rsync -a brain/system/projector.service "$BRAIN":/tmp/projector.service
  ssh "$BRAIN" 'sudo install -m 644 /tmp/projector.service /etc/systemd/system/ && sudo systemctl daemon-reload && sudo systemctl enable -q projector && sudo systemctl restart projector && echo "projector restarted"'
fi

if [[ $what == all || $what == visuals ]]; then
  rsync -rlt --omit-dir-times --exclude __pycache__ --exclude state brain/visuals/ "$BRAIN":/srv/rave/visuals/
  rsync -rlt --omit-dir-times brain/common/s5auth.py "$BRAIN":/srv/rave/visuals/ && rsync -rlt --omit-dir-times brain/common/web/s5auth.js "$BRAIN":/srv/rave/visuals/web/
  rsync -a brain/system/visuals.service "$BRAIN":/tmp/visuals.service
  ssh "$BRAIN" 'sudo install -m 644 /tmp/visuals.service /etc/systemd/system/ && sudo systemctl daemon-reload && sudo systemctl enable -q visuals && sudo systemctl restart visuals && echo "visuals restarted"'
fi

if [[ $what == all || $what == tools ]]; then     # brain/tools/ (set_pin.py etc.) to ~/tools on the brain
  ssh "$BRAIN" 'mkdir -p ~/tools'
  rsync -a brain/tools/ brain/common/s5auth.py "$BRAIN":tools/ && echo "tools updated (set the PIN: ssh -t $BRAIN \"python3 ~/tools/set_pin.py\")"
fi

if [[ $what == pyramid ]]; then
  rsync -a fixtures/pyramid/ "$BOX":pyramid/
  ssh -t "$BOX" 'sudo systemctl restart pyramid && systemctl is-active pyramid'
fi

if [[ $what == panel ]]; then
  rsync -a fixtures/panel/ddp_panel.py fixtures/panel/panel_test.py "$BOX":panel-controller/
  ssh "$BOX" 'pkill -f "[d]dp_panel.py"; cd ~/panel-controller && (nohup python3 -u ddp_panel.py >> /tmp/ddp_panel.log 2>&1 &); sleep 2; pgrep -af "[d]dp_panel.py"'
fi
