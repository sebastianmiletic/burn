#!/bin/zsh
# LAN party integration test: real host and client processes on localhost,
# headless. Usage: tests/net/run_net_test.sh   (from the project root)
# Exits non-zero if any scenario fails. Logs in $TMPDIR/burn_net_test/.
set -u
cd "$(dirname "$0")/../.."
GODOT=${GODOT:-godot}
LOG=${TMPDIR:-/tmp}/burn_net_test
rm -rf "$LOG"; mkdir -p "$LOG"
H="res://tests/net/net_harness.gd"
fail=0

run() {  # run <seconds> <logfile> <args...>
  local secs=$1 log=$2; shift 2
  perl -e "alarm $secs; exec @ARGV" "$GODOT" --headless --path . -s "$H" -- "$@" > "$LOG/$log" 2>&1
}

report() {
  local name=$1; shift
  local ok=1
  for f in "$@"; do
    grep -E "^(PASS|FAIL|INFO)" "$LOG/$f" | sed "s/^/    /"
    grep -q "^RESULT .*: ok" "$LOG/$f" || ok=0
  done
  if [ $ok = 1 ]; then echo "SCENARIO OK   $name"; else echo "SCENARIO FAIL $name"; fail=1; fi
}

echo "== 1. host + client, 2 MB session, no simulated lag"
run 90 s1_host.log --role=host --runes=R1-R14-R6-R9 --clients=1 --payload-mb=2 &
sleep 2
run 90 s1_client.log --role=client --runes=R1-R14-R6-R9 --name=Ash --probe --rtt=0-60
wait
report "basic party" s1_host.log s1_client.log

echo "== 2. client at 150 ms one-way latency, 2 % unreliable loss"
run 120 s2_host.log --role=host --runes=R4-R4-R10-R2 --clients=1 --payload-mb=2 &
sleep 2
run 120 s2_client.log --role=client --runes=R4-R4-R10-R2 --name=Ember --probe --sim-latency=150 --sim-loss=0.02 --rtt=260-420
wait
report "150 ms / 2% loss" s2_host.log s2_client.log

echo "== 3. two clients with the same name"
run 90 s3_host.log --role=host --runes=R7-R0-R15-R3 --clients=2 --payload-mb=0.1 &
sleep 2
run 90 s3_c1.log --role=client --runes=R7-R0-R15-R3 --name=Twin &
sleep 1.5
run 90 s3_c2.log --role=client --runes=R7-R0-R15-R3 --name=Twin --expect-name="Twin (2)"
wait
report "duplicate names" s3_host.log s3_c1.log s3_c2.log

echo "== 4. wrong runes"
run 30 s4_client.log --role=client --runes=R9-R9-R9-R9 --name=Lost --expect-fail="No party with those runes"
report "wrong runes" s4_client.log

echo "== 5. join a campaign already in progress"
run 90 s5_host.log --role=host --runes=R2-R8-R11-R5 --clients=1 --payload-mb=0.5 --start-early &
sleep 2
run 90 s5_client.log --role=client --runes=R2-R8-R11-R5 --name=Late
wait
report "join in progress" s5_host.log s5_client.log

echo "== 6. host closes the party"
run 60 s6_host.log --role=host --runes=R12-R3-R3-R0 --clients=1 --close-after-join &
sleep 2
run 60 s6_client.log --role=client --runes=R12-R3-R3-R0 --name=Left --expect-host-close
wait
report "host leaves" s6_host.log s6_client.log

exit $fail
