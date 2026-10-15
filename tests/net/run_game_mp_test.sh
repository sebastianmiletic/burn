#!/usr/bin/env bash
# Host + client on loopback; no shared user saves or temporary files outside repo.
set -u
cd "$(dirname "$0")/../.." || exit 1
LAT=0; LOSS=0; BYADDR=0
while [[ $# -gt 0 ]]; do
  case $1 in
    --latency) LAT=$2; shift 2;;
    --loss) LOSS=$2; shift 2;;
    --address) BYADDR=1; shift;;
    *) echo "Unknown option: $1" >&2; exit 2;;
  esac
done
GODOT=${GODOT:-godot}
mkdir -p build/validation
LOG=$(mktemp -d "$PWD/build/validation/mp.XXXXXX")
HOST=""; CLIENT=""
cleanup() { [[ -z "$HOST" ]] || kill "$HOST" 2>/dev/null || true; [[ -z "$CLIENT" ]] || kill "$CLIENT" 2>/dev/null || true; }
trap cleanup EXIT INT TERM
perl -e 'alarm 400; exec @ARGV' "$GODOT" --headless --path . --log-file "$LOG/host-engine.log" -- --host --mp-test=host --name=Host --seed=777 --slot=6 --data-dir="$LOG/host-data" > "$LOG/host.txt" 2>&1 &
HOST=$!
for ((i=0; i<100; i++)); do
  grep -q BURN_RUNES "$LOG/host.txt" && break
  sleep 0.5
done
CODE=$(grep -m1 BURN_RUNES "$LOG/host.txt" | awk '{print $2}')
[[ -n "$CODE" ]] || { echo "Host failed to start. Logs: $LOG"; exit 1; }
echo "party runes: $CODE"
JOIN="--join=$CODE"
[[ $BYADDR -eq 0 ]] || JOIN="--join-address=127.0.0.1:47211"
perl -e 'alarm 390; exec @ARGV' "$GODOT" --headless --path . --log-file "$LOG/client-engine.log" -- "$JOIN" --mp-test=client --name=Guest --sim-latency="$LAT" --sim-loss="$LOSS" --data-dir="$LOG/client-data" > "$LOG/client.txt" 2>&1 &
CLIENT=$!
status=0
wait "$CLIENT" || status=1
wait "$HOST" || status=1
CLIENT=""; HOST=""
grep -h '^MP ' "$LOG/host.txt" "$LOG/client.txt"
python3 tools/check_log.py "$LOG/host.txt" "$LOG/client.txt" || status=1
FAILS=$(grep -hc '^MP .* FAIL' "$LOG/host.txt" "$LOG/client.txt" | awk '{s+=$1} END {print s}')
DONE=$(grep -hc '^MP .* DONE' "$LOG/host.txt" "$LOG/client.txt" | awk '{s+=$1} END {print s}')
echo "logs: $LOG"
if [[ $status -eq 0 && $FAILS -eq 0 && $DONE -eq 2 ]]; then
  echo 'MULTIPLAYER GAMEPLAY TEST PASSED'
else
  echo 'MULTIPLAYER GAMEPLAY TEST FAILED'
  exit 1
fi
