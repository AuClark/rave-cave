#!/usr/bin/env bash
# Push code from this repo to the rig and restart what changed.
#
#   brain/deploy.sh            # deckdash + showbrain on the brain (CM4)
#   brain/deploy.sh deckdash   # just one service
#   brain/deploy.sh showbrain
#   brain/deploy.sh pyramid    # pyramid receiver on rave-box (restart needs sudo there)
#   brain/deploy.sh panel      # HUB75 panel receiver on rave-box
#
# Hosts default to their .local names; override in the repo-root .env (see .env.example).
set -euo pipefail
cd "$(dirname "$0")/.."
[[ -f .env ]] && set -a && . ./.env && set +a
BRAIN=${PI:-pi@${RAVE_BRAIN_HOST:-ravecave.local}}
BOX=${BOX:-raver@${RAVE_BOX_HOST:-rave-box.local}}
what=${1:-all}

if [[ $what == all || $what == deckdash ]]; then
  rsync -a brain/deckdash/DeckDash.java brain/deckdash/Timeline.java "$BRAIN":deckdash/
  rsync -a brain/deckdash/web/ "$BRAIN":deckdash/web/
  ssh "$BRAIN" 'cd ~/deckdash && rm -rf classes && javac -cp "lib/*" -d classes DeckDash.java Timeline.java && sudo systemctl restart deckdash && echo "deckdash restarted"'
fi

if [[ $what == all || $what == showbrain ]]; then
  rsync -a --exclude overrides.json --exclude __pycache__ --exclude .env brain/showbrain/ "$BRAIN":showbrain/
  [[ -f .env ]] && rsync -a .env "$BRAIN":showbrain/.env     # site config, never committed
  ssh "$BRAIN" 'sudo systemctl restart showbrain && echo "showbrain restarted"'
fi

if [[ $what == pyramid ]]; then
  rsync -a fixtures/pyramid/ "$BOX":pyramid/
  ssh -t "$BOX" 'sudo systemctl restart pyramid && systemctl is-active pyramid'
fi

if [[ $what == panel ]]; then
  rsync -a fixtures/panel/ddp_panel.py fixtures/panel/panel_test.py "$BOX":panel-controller/
  ssh "$BOX" 'pkill -f "[d]dp_panel.py"; cd ~/panel-controller && (nohup python3 -u ddp_panel.py >> /tmp/ddp_panel.log 2>&1 &); sleep 2; pgrep -af "[d]dp_panel.py"'
fi
