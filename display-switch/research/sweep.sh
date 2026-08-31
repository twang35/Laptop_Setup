#!/bin/zsh
# Phase 2 sweep: which wiggle reliably brings the monitor back to this laptop?
#
#   ./sweep.sh [trials]        # default 5 trials per candidate
#
# Each trial: send the monitor to the desktop, then try to bring it back with one candidate
# wiggle, and record how many attempts that took. A candidate passes only if every trial
# succeeds on the first attempt.
#
# Safety: if a candidate fails to bring the display back, the sweep recovers with the
# known-good 40-60Hz wiggle before continuing. If recovery also fails, it stops.

emulate -L zsh
set -u
cd "${0:A:h}"
SW=./display-switch.sh
TRIALS=${1:-5}
CANDIDATES=(refreshRate rate5994 rate50)

recover() {
  print -n "    recovering… "
  if WIGGLE=refreshRate TRIES=6 $SW laptop >/dev/null 2>&1; then
    print "back on the laptop."
    return 0
  fi
  print "RECOVERY FAILED — stopping. Bring the monitor back by hand in BetterDisplay."
  return 1
}

typeset -A result
for w in $CANDIDATES; do
  print "\n=== candidate: $w ==="
  attempts=()
  for t in {1..$TRIALS}; do
    print -n "  trial $t: to desktop… "
    if ! $SW desktop >/dev/null 2>&1; then
      print "could not reach the desktop input; skipping candidate."
      result[$w]="inconclusive (desktop switch failed)"
      break
    fi
    sleep 2
    print -n "back via $w… "
    out=$(WIGGLE=$w TRIES=4 $SW laptop 2>&1)
    if [[ $out == *"on laptop"* ]]; then
      n=${${out#*after }%% attempt*}
      attempts+=$n
      print "ok in $n attempt(s)."
    else
      attempts+=fail
      print "FAILED."
      recover || exit 1
    fi
    sleep 2
  done
  [[ -n ${result[$w]:-} ]] || result[$w]="${attempts[*]}"
done

print "\n=== results ($TRIALS trials each; 1 = first attempt, lower is better) ==="
for w in $CANDIDATES; do printf "%-14s %s\n" "$w" "${result[$w]:-not run}"; done
print "\nA candidate is only a winner if every trial reads 1."
