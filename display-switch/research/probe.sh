#!/bin/zsh
# Timing probe: after ONE write-and-wiggle, when does the monitor actually report DP 1?
#
#   ./probe.sh [runs] [wiggle] [gap]
#
# The sweep can only say "attempt 1 did not satisfy a read at SETTLE seconds". That is two very
# different findings wearing the same clothes:
#   - the switch landed and the read was early   -> the fix is a longer SETTLE, one attempt is enough
#   - the switch never happened                  -> the fix is in the wiggle itself
# This tells them apart by writing once and then watching, without ever writing again.

emulate -L zsh
set -u
zmodload zsh/datetime          # EPOCHREALTIME is not defined without this
cd "${0:A:h}"

BD=/Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay
MON=${MON:-BenQ EL2870U}
RUNS=${1:-4}
WIG=${2:-refreshRate}
GAP=${3:-0.4}
DEADLINE=${DEADLINE:-20}     # seconds to keep watching
RATE=60Hz

bd() { "$BD" "$@" 2>&1 & local p=$!; ( sleep 8; kill -9 $p 2>/dev/null ) & local w=$!; wait $p; kill $w 2>/dev/null; }
rd() { bd get -ddc -vcp=inputSelect "-name=$MON"; }

wiggle() {
  case $WIG in
    refreshRate) bd set -refreshRate=40-60Hz "-name=$MON" >/dev/null; sleep $GAP; bd set -refreshRate=$RATE "-name=$MON" >/dev/null ;;
    rate5994)    bd set -refreshRate=59.94Hz "-name=$MON" >/dev/null; sleep $GAP; bd set -refreshRate=$RATE "-name=$MON" >/dev/null ;;
    rate50)      bd set -refreshRate=50Hz    "-name=$MON" >/dev/null; sleep $GAP; bd set -refreshRate=$RATE "-name=$MON" >/dev/null ;;
    none)        : ;;
  esac
}

print "probe: wiggle=$WIG gap=$GAP deadline=${DEADLINE}s runs=$RUNS"
print "(one read takes a moment, so the resolution is however long a read takes)"
firsts=()
for r in {1..$RUNS}; do
  print -n "\nrun $r: to desktop… "
  bd set -ddc -vcp=inputSelect -value=17 "-name=$MON" >/dev/null
  sleep 3
  got=$(rd); print -n "input=$got. "
  if [[ $got != 17 ]]; then print "could not park on HDMI 1 — skipping run."; continue; fi

  print -n "one write+wiggle, then watching: "
  start=$EPOCHREALTIME
  bd set -ddc -vcp=inputSelect -value=15 "-name=$MON" >/dev/null
  wiggle

  found=""
  while true; do
    now=$EPOCHREALTIME
    el=$(( now - start ))
    (( el > DEADLINE )) && break
    v=$(rd)
    if [[ $v == 15 ]]; then
      found=$(printf "%.1f" $el)
      break
    fi
  done

  if [[ -n $found ]]; then
    print "DP 1 at ${found}s"
    firsts+=$found
  else
    print "never reached DP 1 within ${DEADLINE}s"
    firsts+=miss
    # recover so the next run starts from a known place
    bd set -ddc -vcp=inputSelect -value=15 "-name=$MON" >/dev/null; wiggle; sleep 3
  fi
  sleep 2
done

print "\n=== when DP 1 first appeared, per run ==="
print -r -- "${firsts[*]}"
print "\nIf these are all numbers, ONE write+wiggle is enough and SETTLE just has to exceed the largest."
print "If any say 'miss', the wiggle itself is not sufficient and needs tuning."
