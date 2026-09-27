#!/usr/bin/env bash
# Push code from this repo to the rig and restart what changed.
#
#   brain/deploy.sh            # deckdash + showbrain on the brain (CM4)
#   brain/deploy.sh deckdash   # just one service
#   brain/deploy.sh web        # dashboard page only (no restart)
#   brain/deploy.sh preview    # page to /preview/ for testing
#   brain/deploy.sh showbrain
#   brain/deploy.sh mixer      # DJM-450 USB bridge
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
  rsync -a brain/deckdash/DeckDash.java brain/deckdash/Timeline.java brain/deckdash/Library.java "$BRAIN":deckdash/
  rsync -rlt --omit-dir-times brain/deckdash/web/ "$BRAIN":/srv/rave/deckdash-web/
  # Compile to classes.new and swap only on success, so a failed build leaves the running one alone.
  ssh "$BRAIN" 'cd ~/deckdash && rm -rf classes.new && javac -cp "lib/*" -d classes.new DeckDash.java Timeline.java Library.java && rm -rf classes && mv classes.new classes && sudo systemctl restart deckdash && echo "deckdash restarted"'
fi

if [[ $what == web ]]; then       # page only: no compile, no restart (the page is re-read on every request)
  rsync -rlt --omit-dir-times brain/deckdash/web/ "$BRAIN":/srv/rave/deckdash-web/ && echo "dashboard page updated"
fi

if [[ $what == preview ]]; then   # work-in-progress page at http://ravecave.local:8080/preview/
  rsync -rlt --omit-dir-times brain/deckdash/web/ "$BRAIN":/srv/rave/deckdash-preview/ && echo "preview updated: http://${RAVE_BRAIN_HOST:-ravecave.local}:8080/preview/"
fi

if [[ $what == all || $what == showbrain ]]; then
  rsync -a --exclude overrides.json --exclude __pycache__ --exclude .env brain/showbrain/ "$BRAIN":showbrain/
  [[ -f .env ]] && rsync -a .env "$BRAIN":showbrain/.env     # site config, never committed
  ssh "$BRAIN" 'sudo systemctl restart showbrain && echo "showbrain restarted"'
fi

if [[ $what == all || $what == mixer ]]; then
  rsync -a brain/mixer/ "$BRAIN":mixer/
  ssh "$BRAIN" 'sudo systemctl restart mixer 2>/dev/null && echo "mixer restarted" || echo "mixer service not installed (see docs/brain.md)"'
fi

if [[ $what == pyramid ]]; then
  rsync -a fixtures/pyramid/ "$BOX":pyramid/
  ssh -t "$BOX" 'sudo systemctl restart pyramid && systemctl is-active pyramid'
fi

if [[ $what == panel ]]; then
  rsync -a fixtures/panel/ddp_panel.py fixtures/panel/panel_test.py "$BOX":panel-controller/
  ssh "$BOX" 'pkill -f "[d]dp_panel.py"; cd ~/panel-controller && (nohup python3 -u ddp_panel.py >> /tmp/ddp_panel.log 2>&1 &); sleep 2; pgrep -af "[d]dp_panel.py"'
fi
