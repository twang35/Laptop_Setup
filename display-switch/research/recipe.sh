#!/bin/zsh
# Which ORDERING of write and wiggle lands the switch on the first attempt, every time?
#
#   ./recipe.sh [trials] [recipe ...]
#
# The sweep showed every wiggle needing a second attempt at almost exactly the same rate, which
# says the problem is not which wiggle but WHEN it arrives. A DDC call takes seconds here, so by
# the time the wiggle lands the monitor has already given up on DP 1 and gone back to HDMI 1.
# Attempt 2 then succeeds because attempt 1's wiggle left the DP link trained and live.
#
# If that is right, a recipe that ends with the input write — after the link is already up —
# should land first time, with no loop at all.
#
# Recipes:
#   ww    write input, then wiggle              (what the sweep tested)
#   wwv   write input, wiggle, write input      (second write meets a live link)
#   vw    wiggle, then write input              (link up first, then select it)
#   vww   wiggle, write input, wiggle           (belt and braces)

emulate -L zsh
set -u
zmodload zsh/datetime
cd "${0:A:h}"

BD=/Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay
MON=${MON:-BenQ EL2870U}
TRIALS=${1:-5}
shift 2>/dev/null || true
RECIPES=(${@:-ww wwv vw vww})
VRR=${VRR:-40-60Hz}
RATE=${RATE:-60Hz}
GAP=${GAP:-0.4}
SETTLE=${SETTLE:-5}          # generous: we are testing ordering, not trimming latency
PARK=${PARK:-4}              # seconds to leave the monitor on the desktop before switching back

bd() { "$BD" "$@" 2>&1 & local p=$!; ( sleep 10; kill -9 $p 2>/dev/null ) & local w=$!; wait $p; kill $w 2>/dev/null; }
wake(){ /usr/bin/ssh -o ConnectTimeout=4 -o BatchMode=yes the-claw-den 'export DISPLAY=:0; xset dpms force on; xset s reset' >/dev/null 2>&1; }
rd()  { bd get -ddc -vcp=inputSelect "-name=$MON"; }
wi()  { bd set -ddc -vcp=inputSelect "-value=$1" "-name=$MON" >/dev/null; }
wig() { bd set "-refreshRate=$VRR" "-name=$MON" >/dev/null; sleep $GAP; bd set "-refreshRate=$RATE" "-name=$MON" >/dev/null; }

run_recipe() {
  case $1 in
    ww)  wi 15; wig ;;
    wwv) wi 15; wig; wi 15 ;;
    vw)  wig; wi 15 ;;
    vww) wig; wi 15; wig ;;
  esac
}

# Always leave the monitor on the laptop, whatever happens.
recover() {
  for i in {1..6}; do
    wi 15; wig; sleep 3
    [[ $(rd) == 15 ]] && return 0
  done
  return 1
}

typeset -A firstok
print "recipe test: $TRIALS trials each, SETTLE=${SETTLE}s, wiggle=40-60Hz round trip\n"

for rcp in $RECIPES; do
  ok=0; detail=()
  print "=== recipe: $rcp ==="
  for t in {1..$TRIALS}; do
    print -n "  trial $t: park on HDMI 1… "
    wake; wi 17; sleep $PARK
    if [[ $(rd) != 17 ]]; then print "could not park; skipping trial."; detail+=skip; continue; fi
    # After a long park, is the display still enumerated at all? If macOS has dropped it, a DDC
    # write has nothing to target and the whole approach needs a different answer.
    enum=$(bd get -identifiers "-name=$MON" 2>&1 | grep -c UUID)
    print -n "(enumerated=$enum) "

    print -n "run $rcp… "
    start=$EPOCHREALTIME
    run_recipe $rcp
    sleep $SETTLE
    got=$(rd)
    el=$(printf "%.1f" $(( EPOCHREALTIME - start )))
    if [[ $got == 15 ]]; then
      print "FIRST-ATTEMPT OK (${el}s)"
      ok=$(( ok + 1 )); detail+=ok
    else
      print "no (read $got after ${el}s)"
      detail+=no
      recover || { print "  RECOVERY FAILED — stopping."; exit 1 }
    fi
    sleep 2
  done
  firstok[$rcp]="$ok/$TRIALS  [${detail[*]}]"
  print "  -> first-attempt success: ${firstok[$rcp]}\n"
done

print "=== first-attempt success by recipe ==="
for r in $RECIPES; do printf "%-5s %s\n" "$r" "${firstok[$r]:-not run}"; done
print "\nThe winner is the one that reads N/N. That recipe needs no retry loop in normal use."
