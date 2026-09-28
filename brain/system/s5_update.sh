#!/usr/bin/env bash
# Keep this brain on GitHub's main: run by s5-update.timer (every 15 minutes).
#
# For each target it compares the commit recorded in ~/.deployed/<target> with main, for that
# target's files only, and deploys the ones that are behind with `brain/deploy.sh live <target>`
# (S5_BRAIN_HOST=local, so it runs here). It waits while a real deck is playing: a restart would
# drop the lights mid-set. It never touches the dashboard preview (/preview/, for testing).
#
#   /usr/local/lib/sektor5/s5_update.sh            # update now (what the timer runs)
#   /usr/local/lib/sektor5/s5_update.sh --check    # only say what's behind
#   journalctl -u s5-update                        # what it did
#   sudo systemctl disable --now s5-update.timer   # stop updating on its own
set -euo pipefail
REPO=${S5_UPDATE_REPO:-https://github.com/AuClark/sektor5.git}
DIR=$HOME/sektor5
check=0; [[ ${1:-} == --check ]] && check=1
exec 9>/tmp/s5-update.lock; flock -n 9 || { echo "already running"; exit 0; }   # one run at a time

# What each target is built from (brain/deploy.sh copies these).
declare -A FILES=(
  [deckdash]="brain/deckdash/*.java brain/deckdash/fetch_libs.sh brain/sim/fakerig.py"
  [web]="brain/deckdash/web brain/common/web"
  [showbrain]="brain/showbrain brain/common/s5auth.py brain/common/web/s5auth.js"
  [mixer]="brain/mixer"
  [projector]="brain/projector brain/common/s5auth.py brain/common/web/s5auth.js brain/system/projector.service"
  [visuals]="brain/visuals brain/projector/web/render.js brain/common/s5auth.py brain/common/web/s5auth.js brain/system/visuals.service"
  [tools]="brain/tools brain/common/s5auth.py"
)
ORDER="deckdash web showbrain mixer projector visuals tools"

[[ -d $DIR/.git ]] || git clone -q "$REPO" "$DIR"
cd "$DIR"
git fetch -q origin main
git checkout -q -B main origin/main && git reset -q --hard origin/main   # our own copy: never edited here
new=$(git rev-parse --short HEAD)

# A newer version of this script on main replaces the installed one, then carries on as that.
installed=/usr/local/lib/sektor5/s5_update.sh
if [[ $0 == "$installed" ]] && ! cmp -s brain/system/s5_update.sh "$installed"; then
  sudo install -m 755 brain/system/s5_update.sh "$installed" && echo "updated the updater" && exec "$installed" "$@"
fi

behind=()
for t in $ORDER; do
  had=$(sed -nE 's/.*@ ([0-9a-f]+).*/\1/p' ~/.deployed/$t 2>/dev/null || true)
  if [[ -z $had ]] || ! git cat-file -e "$had^{commit}" 2>/dev/null; then behind+=("$t"); continue; fi   # unknown: redeploy
  # shellcheck disable=SC2086
  git diff --quiet "$had" HEAD -- ${FILES[$t]} || behind+=("$t")
done
[[ ${#behind[@]} -eq 0 ]] && { echo "up to date with main @ $new"; exit 0; }
echo "main @ $new; behind: ${behind[*]}"
[[ $check == 1 ]] && exit 0

# A real set is playing? (The simulation doesn't count: restarting it is harmless.)
if curl -s -m 3 localhost:8080/api/sim | grep -q '"on":false' &&
   curl -s -m 3 localhost:8080/api/state | python3 -c 'import json,sys; sys.exit(0 if any(p.get("status",{}).get("playing") for p in json.load(sys.stdin).get("players",[])) else 1)' 2>/dev/null; then
  echo "a deck is playing: updating later"
  exit 0
fi

for t in "${behind[@]}"; do
  S5_BRAIN_HOST=local S5_DEPLOY_BY=auto-update brain/deploy.sh live "$t" 2>&1 | grep -v -i deprecat || echo "deploy $t failed"
done
