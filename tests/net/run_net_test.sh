#!/usr/bin/env bash
# LAN party integration test: real host and client processes on localhost,
# headless. Usage: tests/net/run_net_test.sh   (from the project root)
# Exits non-zero if any scenario fails. Logs in $TMPDIR/burn_net_test/.
set -u
cd "$(dirname "$0")/../.."
GODOT=${GODOT:-godot}
mkdir -p build/validation
LOG=$(mktemp -d "$PWD/build/validation/net.XXXXXX")
H="res://tests/net/net_harness.gd"
fail=0

run() {  # run <seconds> <logfile> <args...>
  local secs=$1 log=$2; shift 2
  perl -e "alarm $secs; exec @ARGV" "$GODOT" --headless --path . --log-file "$LOG/$log.engine" -s "$H" -- --data-dir="$LOG/$log.data" "$@" > "$LOG/$log" 2>&1
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
run 90 s1_host.log --role=host --runes=R1-R14-R6-R9 --clients=1 --payload-mb=2 --rules &
sleep 2
run 90 s1_client.log --role=client --runes=R1-R14-R6-R9 --name=Ash --probe --rtt=0-60 --rules
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

echo "== 7. public server: master list, browser join, password, whispers, chat flood limit"
MPORT=47391
MURL="http://127.0.0.1:$MPORT"
python3 server/burn_master.py --port $MPORT --expiry 6 --probe-timeout 1 --log-level WARNING > "$LOG/s7_master.txt" 2>&1 &
MASTER=$!
for _ in $(seq 1 40); do grep -q BURN_MASTER_READY "$LOG/s7_master.txt" && break; sleep 0.25; done
run 120 s7_host.log --role=public-host --master="$MURL" --server-name="Integration Fire" --password=ember &
HPID=$!
sleep 2
run 120 s7_client.log --role=browser-client --master="$MURL" --server-name="Integration Fire" --password=ember --name=Rover
wait $HPID
report "public server + chat" s7_host.log s7_client.log
# The host unregistered on leave; a host that vanishes without a word expires.
python3 - "$MURL" > "$LOG/s7_expiry.log" 2>&1 <<'PY'
import json, sys, time, urllib.request
base = sys.argv[1]
def get():
    return json.load(urllib.request.urlopen(base + "/v1/servers", timeout=5))["count"]
ok = True
print("INFO: entries after the host left:", get()); ok &= get() == 0
body = json.dumps({"name": "Ghost", "protocol": 5, "port": 47299, "max_players": 4}).encode()
r = urllib.request.Request(base + "/v1/servers", data=body, method="POST", headers={"Content-Type": "application/json"})
reg = json.load(urllib.request.urlopen(r, timeout=5))
print("INFO: registered ghost", reg["id"], reg["address"]); ok &= get() == 1
time.sleep(7.5)
print("INFO: entries 7.5 s later:", get()); ok &= get() == 0
print("PASS: master unregister + expiry" if ok else "FAIL: master unregister + expiry")
print("RESULT expiry: ok" if ok else "RESULT expiry: failed")
PY
kill $MASTER 2>/dev/null
report "master expiry" s7_expiry.log

python3 tools/check_log.py "$LOG"/*.log || fail=1
echo "logs: $LOG"
exit $fail
