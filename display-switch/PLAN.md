# Switching the BenQ between the desktop and the laptop with two hotkeys

Two keyboard shortcuts on the laptop. One sends the monitor to the desktop (HDMI 1), one brings it
back to the laptop (DisplayPort 1) and does the wiggle that makes the monitor accept the DP link.

**Constraints.** Nothing installed on the laptop, no new background process. Only Shortcuts.app and
the already-running BetterDisplay. Speed does not matter — the monitor takes 1-2 s regardless.

**Status 2026-08-30:** built and measured — **18/18 first-attempt**.
What is left is the GUI minute — creating the two Shortcuts and binding the keys.

## What was measured (laptop, 2026-08-30)

| fact | value |
|---|---|
| monitor | BenQ EL2870U (2021, `J3M02305SL0`), BetterDisplay `tagID` 3, UUID `84653A99-…` |
| **the app binary is its own CLI** | `/Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay set|get|toggle -param=value` — **no install, and no GUI setup was needed** for any operation used here |
| DDC read | `get -ddc -vcp=inputSelect -name="BenQ EL2870U"` → `15` ✅ |
| DDC write | `set -ddc -vcp=inputSelect -value=15 …` → silent success ✅ |
| input codes | **DP 1 = 15**, **HDMI 1 = 17** |
| `get -refreshRateList` | `60Hz`, **`40-60Hz`**, `50Hz`, `30Hz`, `25Hz`, `24Hz`, `59.94Hz`, `29.97Hz`, `23.98Hz` |
| **`get -proAvailable`** | **`off`** — Pro is *not* active on this install |
| HTTP integration port | **55777** (the 8969 seen in the binary is Sentry's, unrelated) |
| desktop | `the-claw-den`, Ubuntu, up, driving **HDMI-A-2**. One ssh probe failed with "No route to host" and the next two succeeded — a transient mDNS blip, not the box |

### Traps found the hard way

| trap | detail |
|---|---|
| **`set` always exits 0** | failure is reported as the word `Failed.` on stdout, not by exit status. The exit code is worthless as a check |
| **`-refreshRate=60` selects the *variable* 40-60Hz mode** | it reported success and left the display at `40-60Hz`. Only the exact `refreshRateList` strings work — `60Hz`, not `60`. This actually happened during testing and had to be undone |
| **an invalid operation launches a second copy of the app** | `BetterDisplay status` printed *"the app already had 1 running instance and now an additional instance was started"*. It exited on its own, but only valid operations (`set`, `get`, `toggle`, `create`, `discard`, `help`) should ever be passed |

## The result

**One DDC write plus one refresh-rate round trip, then wait 5 s before reading back.** No reordering,
no second write, no loop in normal use.

| | |
|---|---|
| recipe | write DP 1 → wiggle (`60Hz → 40-60Hz → 60Hz`) |
| settle | **5 s** before the confirming read-back |
| measured | **18/18 first-attempt** at `SETTLE`≥4 — 5 trials at a 4 s park, 3 at a 2 min park, 10 at a 30 s park (the shipping defaults). The display stayed enumerated in every trial |
| duration | ~16-17 s, dominated by the two macOS mode sets |
| retry loop | kept as a net, but it no longer fires in normal use |

### The wrong turn, and what it cost

The first sweep ran with `SETTLE=2` and produced 1, 2, 2, 2, 2 for one wiggle and 2, 2, 2, 2, 2 for
the other two — 14 of 15 trials needing a second write-and-wiggle cycle. Three different wiggles
landing on the same number ruled out the wiggle as the cause, so the ordering became the suspect and
a four-way ordering experiment was built.

**The ordering was never the problem.** The very first trial of that experiment used the *unchanged*
baseline recipe and passed first time, because the experiment happened to use `SETTLE=4`. The monitor
had been switching correctly all along; the read at 2 s was simply arriving before it finished. The
`SETTLE` value, which had looked like an incidental bit of politeness, was the whole finding.

The lesson is narrower than "measure more": **a verification threshold is a parameter under test, not
a constant.** Every trial in the first sweep was really measuring `SETTLE`, and none of them said so.

## Wiggle candidates, as measured

| candidate | result |
|---|---|
| `reinitialize` | ❌ **prints `Failed.`** — ranked first in the earlier draft, does not work here |
| `reconfigure` | ❌ **prints `Failed.`** |
| `connected=off`/`on` | ❌ **Pro-gated**, and `proAvailable` is `off` |
| `hdr` toggle | ❌ Pro-gated |
| `60Hz → 59.94Hz → 60Hz` | ✅ round trip works and restores cleanly. Smallest visual delta |
| `60Hz → 50Hz → 60Hz` | ✅ works and restores cleanly |
| `60Hz → 40-60Hz → 60Hz` | ✅ works and restores cleanly. **The known-good one** |

So the hoped-for "one command, no round trip" wiggle does not exist on this install, and the refresh
rate family is the whole field. All three hold the switch equally well; `40-60Hz` is kept because it
is the one already proven by hand.

## Questions already answered

| question | answer | consequence |
|---|---|---|
| Does the wiggle work *before* the input write? | Only when the monitor is on no input. If the desktop is driving HDMI 1, the monitor is content and the wiggle does nothing | order is fixed: **input write, then wiggle**. There is a real timing window |
| Does a wiggle shuffle windows? | No | the round trips are safe to use |
| One toggle key or one per direction? | One per direction | each Shortcut is fixed-destination and idempotent |
| How fast must it be? | Not fast; 1-2 s is inherent | Shortcuts latency is a non-issue and retries are affordable |

The ordering answer splits the target into two starting states: **desktop driving HDMI 1** (the hard
case, needs write-then-wiggle) and **monitor idle** (a wiggle alone suffices). The retry loop in the
tool covers both with one code path, so it never has to detect which one it is in.

## The mechanism

While HDMI 1 is displayed the laptop's DP link is idle. macOS keeps the display attached — DDC still
reaches it, which is why this works at all — but no video timing is being driven. The monitor accepts
"select DP 1", looks for a live signal, does not find one, and falls back to HDMI 1. A refresh-rate
change forces a mode set, the mode set retrains the link, and the monitor sees the input go live.

## What was built

| file | what it is |
|---|---|
| `display-switch.sh` | the tool. `desktop` / `laptop` / `read`. Writes the input, wiggles, reads back, retries. Wiggle selectable via `WIGGLE=` so it can be swept |
| `sweep.sh` | wiggle harness. Runs each candidate N times and prints how many attempts each needed |
| `recipe.sh` | ordering and settle harness. Scores **first-attempt** success per recipe. `PARK=` sets how long to sit on the desktop first |
| `probe.sh` | timing probe: write and wiggle once, then watch until the input flips, to separate a premature read from a failed switch |
| `shortcuts/` | the two Shortcuts actually in use, extracted from `~/Library/Shortcuts/Shortcuts.sqlite`. A record, not importable — Shortcuts imports only signed files and signing needs iCloud. `shortcuts/README.md` also records where the hotkeys live, which is `pbs.plist`, not the Shortcuts store |

## Waking the desktop

Added after the fact: switching *to* the desktop now wakes its screen first, with
`ssh the-claw-den 'DISPLAY=:0 xset dpms force on; xset s reset'`.

The desktop runs an X11 session on `:0` as `claw`, which is also the ssh user, so `xset` works with
no extra auth. It sits at the GDM greeter. DPMS timeouts and the screensaver timeout are both `0` and
GNOME's screensaver reports inactive, so the blanking is not a timer — the likely cause is that when
the monitor switches away, the desktop sees an HDMI disconnect and powers that output down. That
would explain both the mouse waggle and why the monitor might decline to hold HDMI 1.

The wake is best effort and bounded (4 s connect, 8 s kill): a hotkey must not wedge because the
desktop is off or you are away from home. `xrandr --auto` is the escalation if `dpms force on` proves
insufficient in a genuinely cold case; it is not the default because it re-applies preferred modes.

## Where this stands

**Done:** the plumbing (no GUI step needed — the app binary is the CLI), the read-back instrument,
the full wiggle elimination, the ordering experiment, the `SETTLE` finding, a 2-minute-park check,
and the desktop wake.

**Still worth checking, and only reachable from a real cold state:** laptop just woken from sleep,
monitor powered off at the wall, desktop genuinely asleep rather than merely blanked. A 2-minute park
did not degrade anything and the display stayed enumerated throughout, which is the encouraging half.

**Needs the GUI, about a minute:** creating the two Shortcuts and assigning their keys. See
`README.md`.

## Risks and traps

- **Assigning a keyboard shortcut to a Shortcut is the weakest link.** Slow to first-fire, and it
  sometimes fails to register. Accepted. No-install fallback: an Automator Quick Action bound in
  System Settings → Keyboard.
- **Run Shell Script may prompt for file access** the first time it runs a script under `~/Projects`.
  If that is a nuisance, paste the script body inline into the action instead.
- **Test from the desktop-driving state, every time.** A pass from "monitor idle" proves nothing about
  the case that matters.
- **Believe nothing from a single pass**, and **treat the verification threshold as a variable.** The
  first sweep's entire result was an artefact of reading 3 s too early.
- **Verify, never assume.** Neither the exit code nor the absence of output means a DDC write landed.
- **Keep it laptop-side and stateless.** Both hotkeys are pressed on the laptop, so there is nothing
  to coordinate with the desktop and no state file that can go stale.
