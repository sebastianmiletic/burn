#!/bin/zsh
# Host + client play together headless: replication of players, server
# monsters, client attacks and block edits. Optional: --latency 150 --loss 0.02
cd "$(dirname "$0")/../.."
LAT=0; LOSS=0
while [[ $# -gt 0 ]]; do case $1 in --latency) LAT=$2; shift 2;; --loss) LOSS=$2; shift 2;; *) shift;; esac; done
LOG=$(mktemp -d)
perl -e 'alarm 400; exec @ARGV' godot --headless --path . -- --host --mp-test=host --name=Host --seed=777 --slot=6 > $LOG/host.txt 2>&1 &
HOST=$!
for i in {1..60}; do grep -q BURN_RUNES $LOG/host.txt && break; perl -e 'select(undef,undef,undef,0.5)'; done
CODE=$(grep -m1 BURN_RUNES $LOG/host.txt | awk '{print $2}')
echo "party runes: $CODE"
perl -e 'alarm 390; exec @ARGV' godot --headless --path . -- --join=$CODE --mp-test=client --name=Guest --sim-latency=$LAT --sim-loss=$LOSS > $LOG/client.txt 2>&1 &
CLIENT=$!
wait $CLIENT; wait $HOST
grep -h "^MP " $LOG/host.txt $LOG/client.txt
grep -hE "SCRIPT ERROR|^ERROR" $LOG/host.txt $LOG/client.txt | sort | uniq -c | head -10
FAILS=$(grep -h "^MP .* FAIL" $LOG/host.txt $LOG/client.txt | wc -l)
DONE=$(grep -h "^MP .* DONE" $LOG/host.txt $LOG/client.txt | wc -l)
echo "logs: $LOG"
[[ $FAILS -eq 0 && $DONE -eq 2 ]] && echo "MULTIPLAYER GAMEPLAY TEST PASSED" || { echo "MULTIPLAYER GAMEPLAY TEST FAILED"; exit 1; }
