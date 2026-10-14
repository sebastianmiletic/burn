#!/bin/zsh
# Launch a local LAN party for testing: one host plus N clients, each in a
# small window tiled across the screen. Clients find the host by its runes.
#
#   tools/launch_party.sh [clients=3] [--latency MS] [--loss FRACTION] [--headless]
#
# The simulated latency / loss is applied on the clients only (each client
# then sees a round trip of about 2 x MS to the host). Ctrl-C stops everyone.
set -u
cd "$(dirname "$0")/.."
GODOT=${GODOT:-godot}
CLIENTS=3
LATENCY=0
LOSS=0
HEADLESS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --latency) LATENCY=$2; shift 2 ;;
    --loss) LOSS=$2; shift 2 ;;
    --headless) HEADLESS=(--headless); shift ;;
    *) CLIENTS=$1; shift ;;
  esac
done

LOG=${TMPDIR:-/tmp}/burn_party
rm -rf "$LOG"; mkdir -p "$LOG"
W=800; H=450
pids=()
cleanup() { kill ${pids[@]} 2>/dev/null; }
trap cleanup INT TERM HUP ALRM EXIT

"$GODOT" ${HEADLESS[@]} --path . --resolution ${W}x${H} --position 0,30 -- --host --name=Host > "$LOG/host.log" 2>&1 &
pids+=($!)

CODE=""
for i in {1..100}; do
  CODE=$(grep -m1 "^BURN_RUNES " "$LOG/host.log" 2>/dev/null | awk '{print $2}')
  [ -n "$CODE" ] && break
  sleep 0.2
done
if [ -z "$CODE" ]; then
  echo "Host did not start (see $LOG/host.log)"; exit 1
fi
echo "Party runes: $CODE   (logs in $LOG)"

for n in $(seq 1 $CLIENTS); do
  col=$(( n % 2 )); row=$(( n / 2 ))
  "$GODOT" ${HEADLESS[@]} --path . --resolution ${W}x${H} --position $(( col * (W + 10) )),$(( 30 + row * (H + 40) )) -- \
    --join="$CODE" --name="Player$n" --sim-latency=$LATENCY --sim-loss=$LOSS > "$LOG/client$n.log" 2>&1 &
  pids+=($!)
  sleep 0.5
done

echo "Running $CLIENTS client(s) (latency ${LATENCY} ms, loss ${LOSS}). Ctrl-C to stop."
wait
