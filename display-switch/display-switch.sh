#!/bin/zsh
#
# display-switch — move the BenQ EL2870U between the desktop (HDMI 1) and this laptop (DP 1).
#
#   display-switch.sh desktop     # wake the desktop, then -> HDMI 1
#   display-switch.sh laptop      # -> DP 1, with the wiggle
#   display-switch.sh read        # print the input and refresh rate the monitor reports now
#   display-switch.sh wake        # just wake the desktop's screen (for debugging)
#
# Installs nothing and leaves nothing running: it drives the already-running BetterDisplay
# through that app's own binary, which doubles as its CLI.
#
# THE TIMING PROBLEM, AND WHY THE SENDS ARE FIRE-AND-FORGET
#
# The CLI blocks until BetterDisplay has finished the work, and a DDC write or a display mode set
# takes seconds. So a script that waits for the input write to return only starts the wiggle long
# after the monitor began looking for a signal on DP 1 — by which time it has given up and gone
# back to HDMI 1.
#
# So the three commands of the laptop sequence are dispatched WITHOUT waiting for their replies,
# spaced by wall-clock sleeps. The wiggle then begins ~0.1 s after the input write is dispatched
# instead of several seconds later.
#
# The read-back is the one call that must block, because its value is the whole point.
#
# Two traps this script exists to avoid:
#   - `set` returns exit 0 whether or not it did anything, and prints `Failed.` on stdout. Only a
#     read-back proves a change.
#   - a bare `-refreshRate=60` selects the *variable* 40-60Hz mode, not 60Hz. Refresh rates must be
#     the exact strings that `get -refreshRateList` prints.

emulate -L zsh
set -u
zmodload zsh/datetime

BD=/Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay
MON=${MON:-BenQ EL2870U}

HDMI1=17                      # DDC inputSelect value for the desktop
DP1=15                        # DDC inputSelect value for this laptop
RATE=${RATE:-60Hz}            # exact string from `get -refreshRateList`
VRR=${VRR:-40-60Hz}           # ditto

LEAD=${LEAD:-0.1}             # wall time from dispatching the input write to starting the wiggle
GAP=${GAP:-0.4}               # wall time between the two halves of the wiggle
VERIFY=${VERIFY:-0}           # 0: dispatch and exit. 1: poll until the monitor confirms, and report
DEADLINE=${DEADLINE:-10}      # with VERIFY=1, how long to keep polling

DESKTOP_HOST=${DESKTOP_HOST:-the-claw-den}
DESKTOP_WAKE=${DESKTOP_WAKE:-1}

# --- dispatch -------------------------------------------------------------------------------------

# Blocking call, bounded. Used for reads, where the answer is what we came for.
bd() {
  local out
  out=$("$BD" "$@" 2>&1 &
        local p=$!
        ( sleep 8; kill -9 $p 2>/dev/null ) &
        local w=$!
        wait $p
        kill $w 2>/dev/null)
  print -r -- "$out"
}

# Fire and forget: dispatch and return immediately. The point is the wall clock, not the reply.
#
# `disown` matters: the script exits within a second of dispatching these, and a job still owned by
# the shell can take a SIGHUP on the way out. Disowned, it is reparented and runs to completion, so
# the rate change lands even though nobody waited for it.
send() { "$BD" "$@" >/dev/null 2>&1 & disown; }

read_input() { bd get -ddc -vcp=inputSelect "-name=$MON"; }
read_rate()  { bd get -refreshRate "-name=$MON"; }

send_input() { send set -ddc -vcp=inputSelect "-value=$1" "-name=$MON"; }
send_rate()  { send set "-refreshRate=$1" "-name=$MON"; }

notify() { /usr/bin/osascript -e "display notification \"$1\" with title \"Display switch\"" >/dev/null 2>&1; }

# --- the desktop's screen -------------------------------------------------------------------------

# Wake the desktop's display output before handing it the monitor.
#
# When the monitor switches away to DP 1 the desktop sees an HDMI disconnect and powers that output
# down, so on the way back there is no live signal — which is both why the mouse has to be moved and
# a reason the monitor can decline to hold HDMI 1. Waking it first addresses both.
#
# Best effort by design: ssh is home-LAN only and has been seen to fail transiently, and a hotkey
# must never wedge because the desktop is off. A failure here is reported, not fatal.
wake_desktop() {
  [[ $DESKTOP_WAKE == 1 ]] || return 0
  ( /usr/bin/ssh -o ConnectTimeout=4 -o BatchMode=yes "$DESKTOP_HOST" \
        'export DISPLAY=:0; xset dpms force on; xset s reset' >/dev/null 2>&1 &
    local p=$!
    ( sleep 8; kill -9 $p 2>/dev/null ) &
    local w=$!
    wait $p
    local rc=$?
    kill $w 2>/dev/null
    exit $rc )
}

# --- confirmation ---------------------------------------------------------------------------------

# Poll until the monitor reports the input we asked for, or the deadline passes. Polling rather than
# one read after a fixed settle: it reports success as soon as it is true instead of always paying
# the worst case, and a read that is not a number means "no answer yet", not "wrong".
confirm_within() {
  local want=$1 deadline=$2 start=$EPOCHREALTIME got
  while (( EPOCHREALTIME - start < deadline )); do
    got=$(read_input)
    [[ $got == $want ]] && { printf "%.1f" $(( EPOCHREALTIME - start )); return 0 }
  done
  print -r -- "${got:-no answer}"
  return 1
}

# --- main -----------------------------------------------------------------------------------------

case ${1:-} in
  read)
    print -r -- "input=$(read_input)  rate=$(read_rate)"
    ;;

  wake)
    if wake_desktop; then print -r -- "woke $DESKTOP_HOST"; else print -r -- "could not wake $DESKTOP_HOST"; exit 1; fi
    ;;

  desktop)
    # Wake the desktop's output first, so the monitor finds a live signal on HDMI 1 and the screen
    # is already up when it appears.
    wake_desktop || print -r -- "note: could not wake $DESKTOP_HOST (off, asleep or off-LAN); switching anyway"
    send_input $HDMI1
    (( VERIFY )) || exit 0
    if t=$(confirm_within $HDMI1 $DEADLINE); then
      print -r -- "on desktop (HDMI 1) in ${t}s"
    else
      print -r -- "did not confirm HDMI 1 within ${DEADLINE}s: input reads $t"
      exit 1
    fi
    ;;

  laptop)
    # Dispatch all three without waiting, spaced by wall clock, so the wiggle lands inside the
    # window while the monitor is still looking for a signal on DP 1.
    send_input $DP1          # dispatched, not awaited
    sleep "$LEAD"
    send_rate "$VRR"         # dispatched, not awaited
    sleep "$GAP"
    send_rate "$RATE"        # dispatched, not awaited: it lands on its own a moment later

    (( VERIFY )) || exit 0
    if t=$(confirm_within $DP1 $DEADLINE); then
      print -r -- "on laptop (DP 1) in ${t}s, rate=$(read_rate)"
    else
      print -r -- "did not confirm DP 1 within ${DEADLINE}s: input reads $t"
      exit 1
    fi
    ;;

  *)
    print -u2 "usage: ${0:t} desktop|laptop|read|wake"
    exit 64
    ;;
esac
