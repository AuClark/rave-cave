#!/usr/bin/env bash
# Run the whole Sektor5 app on this computer against a synthetic rig: no decks, mixer, lights or
# brain needed. See docs/sim.md.
#
#   brain/sim/run.sh               # an endless auto-mixed set at 126 BPM
#   brain/sim/run.sh --bpm 132     # faster
#   brain/sim/run.sh --no-auto     # nothing mixes itself; load and play from the dashboard
#
# Then open http://localhost:8080 (Decks), :8090 (Lighting), :8100/edit (Projection),
# :8100/stage.html (Stage), :8110 (Visuals). Page edits show on refresh; Python edits need a restart.
# Ctrl-C stops everything.
set -euo pipefail
cd "$(dirname "$0")/../.."
REPO="$PWD"
VENV="$REPO/brain/sim/.venv"

PY=python3
if ! $PY -c "import numpy" 2>/dev/null; then
  if [[ -x "$VENV/bin/python3" ]] && "$VENV/bin/python3" -c "import numpy" 2>/dev/null; then
    PY="$VENV/bin/python3"
  else
    echo "numpy missing; creating $VENV (Homebrew Python blocks global pip)"
    python3 -m venv "$VENV"
    "$VENV/bin/pip" install -q numpy
    PY="$VENV/bin/python3"
  fi
fi

for port in 8080 8090 8100 8110; do
  if lsof -nP -iTCP:$port -sTCP:LISTEN >/dev/null 2>&1; then
    echo "port $port is already in use (another sim still running?): lsof -nP -iTCP:$port -sTCP:LISTEN"; exit 1
  fi
done

# The brain gets s5auth copied next to each service by deploy.sh; here the services import it from
# brain/common and serve the page script through git-ignored links.
export PYTHONPATH="$REPO/brain/common${PYTHONPATH:+:$PYTHONPATH}"
ln -sf ../common/web/s5auth.js brain/showbrain/s5auth.js
ln -sf ../../common/web/s5auth.js brain/projector/web/s5auth.js
ln -sf ../../common/web/s5auth.js brain/visuals/web/s5auth.js

# No admin PIN locally (everyone is admin), and light output goes nowhere (this machine).
export S5_AUTH_FILE="$REPO/brain/sim/no-auth.json"
export S5_TUBE1_HOST=127.0.0.1 S5_TUBE2_HOST=127.0.0.1 S5_BOX_HOST=127.0.0.1

LOGS="$REPO/brain/sim/logs"; mkdir -p "$LOGS"
pids=()
stop() { trap - INT TERM EXIT; kill "${pids[@]}" 2>/dev/null || true; wait 2>/dev/null || true; echo; echo "sim stopped"; }
trap stop INT TERM EXIT

$PY -u brain/sim/fakerig.py "$@"            > "$LOGS/fakerig.log"   2>&1 & pids+=($!)
sleep 0.5
$PY -u brain/showbrain/showbrain.py         > "$LOGS/showbrain.log" 2>&1 & pids+=($!)
$PY -u brain/projector/projector.py 8100    > "$LOGS/projector.log" 2>&1 & pids+=($!)
$PY -u brain/visuals/visuals.py 8110        > "$LOGS/visuals.log"   2>&1 & pids+=($!)
sleep 2

ok=1
for pid in "${pids[@]}"; do kill -0 "$pid" 2>/dev/null || ok=0; done
if [[ $ok == 0 ]]; then echo "something failed to start; see brain/sim/logs/"; tail -n 5 "$LOGS"/*.log; exit 1; fi

cat <<MSG
Sektor5 is running on a synthetic rig (logs in brain/sim/logs/).
  Decks       http://localhost:8080
  Lighting    http://localhost:8090
  Projection  http://localhost:8100/edit
  Stage       http://localhost:8100/stage.html
  Visuals     http://localhost:8110
Ctrl-C to stop.
MSG
[[ -n "${NO_OPEN:-}" ]] || open "http://localhost:8080" 2>/dev/null || true
wait
