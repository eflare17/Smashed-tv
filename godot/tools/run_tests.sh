#!/usr/bin/env bash
# The voxel game's self-tests, each run the way its own header comment says to run it.
#
# Why this exists: every test here is a Godot script with its own command line, and some of them need flags or a
# display that the obvious "--headless -s <the file>" does not give them. Run one the wrong way and it fails for
# nothing, which wastes an afternoon -- and, worse, three of the Dig Site tests sat on a branch for weeks not even
# compiling, because nothing ever ran the whole set. This is that one thing.
#
#   godot/tools/run_tests.sh                     everything it can (the picture tests are slow: see --skip-shots)
#   godot/tools/run_tests.sh --skip-shots        no screenshot tests (no display needed, minutes instead of hours)
#   godot/tools/run_tests.sh --only touch,judder the tests whose names match any of these
#   godot/tools/run_tests.sh --list              what it would run, and how, without running anything
#
#   GODOT=/path/to/godot                         which binary (default /root/godot/godot, then godot on PATH)
#   --timeout SECONDS                            per test (default 1800; 2700 for a picture test)
#   --logs DIR                                   where each test's full output goes (default a mktemp dir)
#
# One line per test, then a summary. Exit 0 only if every test that really ran passed.
#
# Four kinds of test, because four different command lines:
#   script  --headless -s res://test/voxel/<name>.gd, plus the user args in the table below ("-" for none)
#   scene   a .tscn, which is run as the main scene, not with -s (logic_test, perf_test)
#   shots   takes screenshots, so it needs a real display (xvfb-run) and --out=<dir>; never --headless
#   pair    two processes that talk to each other (a host and a guest). Not run: see WHY_PAIR below, which prints
#           both command lines so they can be run by hand.
#   phases  two runs in order, sharing a --save= path (digsite_save_test: dig and go home, then load it back)
set -u

here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
proj="$(dirname -- "$here")"          # the Godot project (godot/)
repo="$(dirname -- "$proj")"

godot="${GODOT:-}"
if [ -z "$godot" ]; then
	if [ -x /root/godot/godot ]; then godot=/root/godot/godot; else godot="$(command -v godot || true)"; fi
fi

timeout_s=1800
shot_timeout_s=2700
logs=""
only=""
skip_shots=0
list_only=0
while [ $# -gt 0 ]; do
	case "$1" in
		--skip-shots) skip_shots=1 ;;
		--only) only="$2"; shift ;;
		--only=*) only="${1#*=}" ;;
		--timeout) timeout_s="$2"; shift ;;
		--timeout=*) timeout_s="${1#*=}" ;;
		--logs) logs="$2"; shift ;;
		--logs=*) logs="${1#*=}" ;;
		--list) list_only=1 ;;
		-h|--help) sed -n '2,32p' "${BASH_SOURCE[0]}"; exit 0 ;;
		*) echo "run_tests.sh: unknown option $1 (try --help)" >&2; exit 2 ;;
	esac
	shift
done

if [ -z "$godot" ] || [ ! -x "$godot" ]; then
	echo "run_tests.sh: no Godot binary (set GODOT=/path/to/godot)" >&2
	exit 2
fi
if [ ! -f "$proj/project.godot" ]; then
	echo "run_tests.sh: $proj is not a Godot project" >&2
	exit 2
fi
[ -n "$logs" ] || logs="$(mktemp -d -t voxel-tests-XXXXXX)"
mkdir -p "$logs"
shots_dir="$logs/shots"
## A saved game of its own for every test that touches one, fresh every run. This is not cosmetic. A test run with
## `-s` and no --save= and none of the flags VoxelArena counts as "testing" (--nosave among them) gets the REAL
## user://voxel_save.json: it loads whatever the last run left there and writes its own back. So inventory_test,
## farm_test and upgrades_test -- which all check that something is saved and comes back -- fail against another
## test's leftovers (measured: inventory_test 19 passed / 10 failed that way, 29 / 0 with a save file of its own),
## and which tests fail changes from run to run with the order. --nosave is not the answer either: it turns saving
## off altogether, so the save-and-load checks inside those tests fail instead (inventory_test 28 / 1).
saves_dir="$logs/saves"
mkdir -p "$saves_dir"
rm -f "$saves_dir"/*

# ---------------------------------------------------------------- the table: name, kind, the user args after --
# The args are taken from each test's own header comment. "-" means none at all -- which for a test that saves
# (save_test, help_test, digsite_save_test) is the point: --nosave would stop the very thing it is checking.
TESTS="
announcer_test|script|--nosave
barbecue_test|script|--save=@save@
bedroom_test|script|--save=@save@
chickens_test|script|--save=@save@
coop_test|pair|-
dangle_test|script|--save=@save@
demolition_test|script|--save=@save@
dig_test|script|--save=@save@
digsite_cave_test|script|--nosave
digsite_dingo_test|script|--nosave
digsite_dirt_test|script|--nosave
digsite_dynamite_test|script|--nosave
digsite_fleet_test|script|--nosave
digsite_ground_test|script|--nosave
digsite_save_test|phases|-
digsite_support_test|script|--nosave
digsite_sync_test|pair|-
digsite_test|script|--nosave
digsite_tools_test|script|--nosave
digsite_tunnel_test|script|--nosave
digsite_walkin_test|script|--nosave
farm_test|script|--save=@save@
fixes_test|script|--save=@save@
games_test|script|--save=@save@
gothica_test|script|--nosave
gun_range_test|shots|--save=@save@
health_test|script|--save=@save@
help_test|script|--save=user://help_x.json
inventory_test|script|--save=@save@
judder_test|script|--nosave
kinds_test|script|--save=@save@
lagcomp_test|pair|-
logic_test|scene|-
luna_invasion_test|script|--save=@save@
mine_coop_test|pair|-
mine_test|script|--nosave
net_link_test|pair|-
net_menu_test|script|--save=@save@
perf_test|scene|-
save_test|script|--save=@save@
settings_speed_test|script|--nosave
settings_stale_test|script|--nosave --settings --touch
settings_test|script|--save=@save@
shredder_test|script|--save=@save@
stkilda_carousel_fling_test|shots|--save=@save@
stkilda_carousel_hack_test|shots|--save=@save@
stkilda_dig_test|shots|--save=@save@
stkilda_kill12_test|shots|--save=@save@
stkilda_luna_smash_test|shots|--save=@save@
stkilda_rain_test|shots|--save=@save@
stkilda_ride_test|shots|--save=@save@
stkilda_rubble_test|shots|--save=@save@
stkilda_smash_test|shots|--save=@save@
stkilda_test|shots|--save=@save@
stkilda_tumble_test|shots|--save=@save@
stkilda_walk_test|shots|--save=@save@
stkilda_weapons_wall_test|shots|--save=@save@
sweep_arena_test|script|--save=@save@
sweep_games_test|script|--save=@save@
sweep_misc_test|script|--save=@save@
sweep_net_test|script|--save=@save@
sweep_test|script|--save=@save@
sweep_weapons_test|script|--save=@save@
sweep_yard_test|script|--save=@save@
touch_test|script|--nosave
upgrades_test|script|--save=@save@
waves_test|script|--waves
"

# Why the two-process ones are not run here. Each needs a second Godot (and net_link_test a signalling server as
# well), and a run that half-starts is worse than no run: it reports a failure that is only the missing other half.
pair_why() {
	case "$1" in
		coop_test) echo "two processes, a host and a guest over ENet:
      $godot --headless --fixed-fps 60 --path $proj -s res://test/voxel/coop_test.gd -- --host=COOP --via=enet --enemies=8
      $godot --headless --fixed-fps 60 --path $proj -s res://test/voxel/coop_test.gd -- --join=COOP --via=enet" ;;
		net_link_test) echo "two processes AND a signalling server (test/voxel/peer_server.js):
      node $proj/test/voxel/peer_server.js
      $godot --headless --path $proj -s res://test/voxel/net_link_test.gd -- --role=host  --via=rtc --server=ws://127.0.0.1:9000/
      $godot --headless --path $proj -s res://test/voxel/net_link_test.gd -- --role=guest --via=rtc --server=ws://127.0.0.1:9000/" ;;
		lagcomp_test) echo "two processes, a host and a guest, with a lag figure:
      $godot --headless --fixed-fps 60 --path $proj -s res://test/voxel/lagcomp_test.gd -- --host=LAG --via=enet --lag=150 --nosave
      $godot --headless --fixed-fps 60 --path $proj -s res://test/voxel/lagcomp_test.gd -- --join=LAG --via=enet --lag=150 --nosave" ;;
		digsite_sync_test) echo "two processes, a host and a guest, the Dig Site shared:
      $godot --headless --fixed-fps 60 --path $proj -s res://test/voxel/digsite_sync_test.gd -- --host=DS --lag=150 --loss=10 --nosave
      $godot --headless --fixed-fps 60 --path $proj -s res://test/voxel/digsite_sync_test.gd -- --join=DS --lag=150 --loss=10 --nosave" ;;
		mine_coop_test) echo "two processes, a host and a guest, the mine shared:
      $godot --headless --fixed-fps 60 --path $proj -s res://test/voxel/mine_coop_test.gd -- --host=MINE --via=enet --lag=120 --loss=10 --nosave
      $godot --headless --fixed-fps 60 --path $proj -s res://test/voxel/mine_coop_test.gd -- --join=MINE --via=enet --lag=120 --loss=10 --nosave" ;;
		*) echo "two processes that have to talk to each other" ;;
	esac
}

# the command line for one test, printed one argument a line (so --list and the runner never disagree)
cmd_for() {   # name kind args
	local name="$1" kind="$2" args="$3"
	case "$kind" in
		script)
			printf '%s\n--headless\n--path\n%s\n--fixed-fps\n60\n-s\nres://test/voxel/%s.gd\n' "$godot" "$proj" "$name"
			[ "$args" = "-" ] || { printf -- '--\n'; printf '%s\n' ${args//@save@/$saves_dir/$name.json}; } ;;
		scene)
			printf '%s\n--headless\n--path\n%s\n--fixed-fps\n60\nres://test/voxel/%s.tscn\n' "$godot" "$proj" "$name" ;;
		shots)
			# a real display, Forward+, and a folder for the pictures: never --headless
			printf 'xvfb-run\n-a\n%s\n--path\n%s\n--fixed-fps\n60\n-s\nres://test/voxel/%s.gd\n--\n--out=%s/%s\n' \
				"$godot" "$proj" "$name" "$shots_dir" "$name"
			[ "$args" = "-" ] || printf '%s\n' ${args//@save@/$saves_dir/$name.json} ;;
	esac
}

wanted() {
	[ -z "$only" ] || echo "$1" | grep -qE "$(echo "$only" | tr ',' '|')"
}

# did this test pass? exit code first, then its own summary line ("... N failed") and any FAIL line it printed
verdict() {   # rc logfile
	local rc="$1" log="$2"
	[ "$rc" -eq 0 ] || return 1
	grep -qE '[,:] *[1-9][0-9]* failed' "$log" && return 1
	grep -qE '^(FAIL[ :]|FAIL$|[A-Z]+ FAIL )' "$log" && return 1
	return 0
}

# the test's own summary line, for the one line this prints about it ("64 passed, 0 failed", or the bare PASS /
# FAIL: ... that the picture tests print)
summary_of() {   # logfile
	local s
	s="$(grep -hoE '[0-9]+ passed, [0-9]+ failed' "$1" | tail -1)"
	[ -n "$s" ] || s="$(grep -hE '^(PASS|FAIL)([ :]|$)' "$1" | tail -1)"
	echo "$s"
}

pass=0; fail=0; skip=0
failed_names=""
skips="$logs/skipped.txt"          # (one block a test: its name, then why, indented -- a reason runs to several lines)
: > "$skips"
note_skip() {   # name why
	printf '  %s:\n' "$1" >> "$skips"
	printf '%s\n' "$2" | sed 's/^/    /' >> "$skips"
	skip=$((skip + 1))
}

run_one() {   # name kind args
	local name="$1" kind="$2" args="$3"
	local log="$logs/$name.log"
	local t0 t1 rc secs sum lim
	lim="$timeout_s"
	[ "$kind" = "shots" ] && lim="$shot_timeout_s"
	t0=$(date +%s)
	if [ "$kind" = "phases" ]; then
		# two runs, in order, sharing one --save= path; the second only means anything if the first got that far
		local keep="$saves_dir/$name"       # (the two phases share it, and it starts the run fresh)
		: > "$log"
		local ph rc2=0
		for ph in 1 2; do
			timeout "$lim" "$godot" --headless --path "$proj" --fixed-fps 60 \
				-s "res://test/voxel/$name.gd" -- "--save=$keep" "--phase=$ph" >> "$log" 2>&1
			rc2=$?
			echo "--- phase $ph exit $rc2" >> "$log"
			[ "$rc2" -eq 0 ] || break
		done
		rc=$rc2
	else
		local -a cmd=()
		mapfile -t cmd < <(cmd_for "$name" "$kind" "$args")
		mkdir -p "$shots_dir/$name" 2>/dev/null || true
		timeout "$lim" "${cmd[@]}" > "$log" 2>&1
		rc=$?
	fi
	t1=$(date +%s)
	secs=$((t1 - t0))
	sum="$(summary_of "$log")"
	# the two-phase one prints a summary a phase, and the second phase is the half that matters: show both
	[ "$kind" = "phases" ] && sum="$(grep -hoE '[0-9]+ passed, [0-9]+ failed' "$log" | paste -sd';' - | sed 's/;/ then /g')"
	[ -n "$sum" ] || sum="no summary line"
	if [ "$rc" -eq 124 ]; then
		printf 'FAIL  %-30s %5ds  timed out after %ss\n' "$name" "$secs" "$lim"
		fail=$((fail + 1)); failed_names="$failed_names $name"
	elif verdict "$rc" "$log"; then
		printf 'pass  %-30s %5ds  %s\n' "$name" "$secs" "$sum"
		pass=$((pass + 1))
	else
		printf 'FAIL  %-30s %5ds  %s  (exit %s, %s)\n' "$name" "$secs" "$sum" "$rc" "$log"
		fail=$((fail + 1)); failed_names="$failed_names $name"
	fi
}

if [ "$list_only" -eq 1 ]; then
	echo "$TESTS" | while IFS='|' read -r name kind args; do
		[ -n "$name" ] || continue
		wanted "$name" || continue
		if [ "$kind" = "pair" ]; then
			echo "$name (pair, not run)"
		elif [ "$kind" = "phases" ]; then
			echo "$name: two runs sharing --save=$saves_dir/$name, --phase=1 then --phase=2"
		else
			echo "$name: $(cmd_for "$name" "$kind" "$args" | tr '\n' ' ')"
		fi
	done
	exit 0
fi

# A test file nobody listed here is a test nobody runs -- which is how three Dig Site tests sat on this branch not
# even compiling. So the table is checked against what is on disk, and a stranger is a failure, not a shrug.
strays=""
for f in "$proj"/test/voxel/*_test.gd; do
	n="$(basename "$f" .gd)"
	echo "$TESTS" | grep -q "^$n|" || strays="$strays $n"
done
if [ -n "$strays" ]; then
	echo "run_tests.sh: these tests are not in this script's table, so nothing runs them:$strays" >&2
	echo "              add a line for each (name|kind|the user args its own header documents) and run again." >&2
	exit 3
fi

echo "Godot:   $godot"
echo "project: $proj"
echo "logs:    $logs"
echo
while IFS='|' read -r name kind args; do
	[ -n "$name" ] || continue
	if ! wanted "$name"; then continue; fi
	case "$kind" in
		pair)
			printf 'skip  %-30s        %s\n' "$name" "needs two processes talking to each other"
			note_skip "$name" "$(pair_why "$name")" ;;
		shots)
			if [ "$skip_shots" -eq 1 ]; then
				printf 'skip  %-30s        %s\n' "$name" "screenshot test, --skip-shots was given"
				note_skip "$name" "takes screenshots (a display, xvfb-run, --out=dir), and --skip-shots was given"
			elif ! command -v xvfb-run >/dev/null 2>&1; then
				printf 'skip  %-30s        %s\n' "$name" "needs a display and xvfb-run isn't installed"
				note_skip "$name" "takes screenshots, so it needs a display, and xvfb-run is not installed"
			else
				run_one "$name" "$kind" "$args"
			fi ;;
		*) run_one "$name" "$kind" "$args" ;;
	esac
done <<< "$TESTS"

# digsite_save_test writes <--save= path>.facts, and with no --save= at all that lands in the project itself as
# godot/.facts. This runner always gives it a user:// path, so nothing should appear -- but an earlier run by hand
# may have left one, and a stray file in the working tree is worth saying out loud.
if [ -f "$proj/.facts" ]; then
	echo
	echo "note: $proj/.facts is in the working tree -- digsite_save_test run without --save= leaves it there."
	echo "      This runner gives it a user:// path instead, so it did not come from this run. Removing it."
	rm -f "$proj/.facts"
fi

echo
echo "------------------------------------------------------------"
printf '%d passed, %d failed, %d skipped\n' "$pass" "$fail" "$skip"
[ -z "$failed_names" ] || echo "failed:$failed_names"
if [ "$skip" -gt 0 ]; then
	echo
	echo "skipped, and why:"
	cat "$skips"
fi
echo "full output of every test: $logs"
[ "$fail" -eq 0 ]
