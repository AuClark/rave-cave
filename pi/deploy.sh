#!/usr/bin/env bash
# Push the show code from this repo to the Pi and restart what changed.
#
#   pi/deploy.sh            # deckdash + showbrain
#   pi/deploy.sh showbrain  # just one
#   pi/deploy.sh panel      # panel receiver on rave-box
set -euo pipefail
cd "$(dirname "$0")/.."
PI=${PI:-pi@ravecave.local}
what=${1:-all}

if [[ $what == all || $what == deckdash ]]; then
  rsync -a pi/deckdash/DeckDash.java pi/deckdash/Timeline.java "$PI":deckdash/
  rsync -a pi/deckdash/web/ "$PI":deckdash/web/
  ssh "$PI" 'cd ~/deckdash && rm -rf classes && javac -cp "lib/*" -d classes DeckDash.java Timeline.java && sudo systemctl restart deckdash && echo "deckdash restarted"'
fi

if [[ $what == all || $what == showbrain ]]; then
  rsync -a --exclude overrides.json --exclude __pycache__ pi/showbrain/ "$PI":showbrain/
  ssh "$PI" 'sudo systemctl restart showbrain && echo "showbrain restarted"'
fi

if [[ $what == panel ]]; then
  rsync -a panel/ddp_panel.py rave-box:panel-controller/
  ssh rave-box 'pkill -f "[d]dp_panel.py"; cd ~/panel-controller && (nohup python3 -u ddp_panel.py >> /tmp/ddp_panel.log 2>&1 &); sleep 2; pgrep -af "[d]dp_panel.py"'
fi
