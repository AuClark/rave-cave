#!/usr/bin/env bash
# Push code from this repo to the rig and restart what changed.
#
#   brain/deploy.sh            # deckdash + showbrain on the brain (CM4)
#   brain/deploy.sh deckdash   # just one service
#   brain/deploy.sh web        # just the dashboard page (no compile, no restart)
#   brain/deploy.sh showbrain
#   brain/deploy.sh pyramid    # pyramid receiver on rave-box (restart needs sudo there)
#   brain/deploy.sh panel      # HUB75 panel receiver on rave-box
#
# Hosts default to their .local names; override in the repo-root .env (see .env.example).
# Collaborators with their own login (not pi) set RAVE_BRAIN_USER and the RAVE_*_DIR paths in .env.
set -euo pipefail
cd "$(dirname "$0")/.."
[[ -f .env ]] && set -a && . ./.env && set +a
BRAIN=${PI:-${RAVE_BRAIN_USER:-pi}@${RAVE_BRAIN_HOST:-ravecave.local}}
DD=${RAVE_DECKDASH_DIR:-deckdash}            # relative paths are in the login's home
WEB=${RAVE_WEB_DIR:-$DD/web}                 # where deckdash serves index.html from (-Dweb)
SB=${RAVE_SHOWBRAIN_DIR:-showbrain}
BOX=${BOX:-raver@${RAVE_BOX_HOST:-rave-box.local}}
what=${1:-all}

if [[ $what == all || $what == deckdash ]]; then
  rsync -a brain/deckdash/DeckDash.java brain/deckdash/Timeline.java brain/deckdash/Library.java "$BRAIN:$DD/"
  rsync -a brain/deckdash/web/ "$BRAIN:$WEB/"
  # Compile to classes.new and swap only on success, so a failed build leaves the running one alone.
  ssh "$BRAIN" "cd $DD && rm -rf classes.new && javac -cp 'lib/*' -d classes.new DeckDash.java Timeline.java Library.java && rm -rf classes && mv classes.new classes && sudo -n systemctl restart deckdash && echo 'deckdash restarted'"
fi

if [[ $what == web ]]; then
  rsync -a brain/deckdash/web/ "$BRAIN:$WEB/" && echo "dashboard page updated (reload the browser)"
fi

if [[ $what == all || $what == showbrain ]]; then
  rsync -a --exclude overrides.json --exclude __pycache__ --exclude .env brain/showbrain/ "$BRAIN:$SB/"
  [[ -f .env ]] && rsync -a .env "$BRAIN:$SB/.env"     # site config, never committed
  ssh "$BRAIN" "sudo -n systemctl restart showbrain && echo 'showbrain restarted'"
fi

if [[ $what == pyramid ]]; then
  rsync -a fixtures/pyramid/ "$BOX":pyramid/
  ssh -t "$BOX" 'sudo systemctl restart pyramid && systemctl is-active pyramid'
fi

if [[ $what == panel ]]; then
  rsync -a fixtures/panel/ddp_panel.py fixtures/panel/panel_test.py "$BOX":panel-controller/
  ssh "$BOX" 'pkill -f "[d]dp_panel.py"; cd ~/panel-controller && (nohup python3 -u ddp_panel.py >> /tmp/ddp_panel.log 2>&1 &); sleep 2; pgrep -af "[d]dp_panel.py"'
fi
