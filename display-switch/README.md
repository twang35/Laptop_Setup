# display-switch

Move the BenQ EL2870U between the desktop (HDMI 1) and this laptop (DisplayPort 1) with a keyboard
shortcut in each direction.

Installs nothing and leaves nothing running. It drives the already-running BetterDisplay through
that app's own binary, which doubles as a CLI.

## Use it from the terminal

    ./display-switch.sh read        # what input the monitor reports right now
    ./display-switch.sh desktop     # -> HDMI 1, waking the desktop alongside
    ./display-switch.sh laptop      # -> DP 1, with the wiggle and a retry loop
    ./display-switch.sh wake        # just wake the desktop's screen (for debugging)

A switch takes about 16 seconds, most of it the two macOS mode sets the wiggle needs. That is close
to the floor for this approach; see *Why it is not faster*.

## Set up the two hotkeys

The two in use are **Monitor to Desktop Input** (⌘⌥⌃H) and **Monitor to Laptop Input** (⌘⌥⌃D) — H for
HDMI, D for DisplayPort. Their extracted definitions are in [`shortcuts/`](shortcuts/), as a record;
they are not importable, because Shortcuts imports only signed files and signing needs iCloud.

Each is a **single action**, so building them by hand takes about a minute.

For each of the two directions:

1. Shortcuts.app → **File → New Shortcut**.
2. Search the action list for **Run Shell Script** and drag it in.
3. Paste as the script — the path being wherever you keep this script:

       "$HOME/Projects/Laptop_Setup/display-switch/display-switch.sh" laptop

   …using `desktop` for the other one. The **Shell** setting does not matter and the real ones do not
   set it: the script is invoked as a quoted path and carries its own `#!/bin/zsh`.
4. Name them **Monitor to Laptop** and **Monitor to Desktop**.
5. In the shortcut's details pane (the ⓘ sidebar), **Add Keyboard Shortcut** and press the chord you
   want. Pick something no app will swallow — the laptop-direction one gets pressed while you are
   looking at the built-in screen.

The first run may ask for permission to access files under `~/Projects`. If that is a nuisance, paste
the body of `display-switch.sh` directly into the action instead of calling the file — it depends on
nothing but the BetterDisplay binary.

## How the laptop direction works

Switching *to* the desktop is one DDC write, because the desktop is already driving HDMI 1 and the
monitor finds a live signal. Switching *to* the laptop is harder: while HDMI 1 is displayed the DP
link is idle, so the monitor accepts "select DP 1", finds no live signal, and falls back. The fix is
to make macOS assert a fresh timing on that link immediately after the write, by changing the refresh
rate and changing it back.

That is a race against the monitor's search window, which is why the timing of the dispatch matters
more than anything else here. See *Timing*.

**Everything is one try, and nothing is awaited.** No retry loops, no verification, no blocking
calls in the switch path. A switch that does not take is visible on the monitor, and pressing the key
again is faster and clearer than any recovery logic.

Real-world testing showed the earlier wait-for-each-call version losing the race: by the time the
input write returned, the monitor had already given up. Dispatching without waiting closes that gap.

## Tunables

Environment variables, so the behaviour can be swept without editing the script:

| variable | default | meaning |
|---|---|---|
| `WIGGLE` | `refreshRate` | `refreshRate` (60→40-60→60), `rate5994`, `rate50`, `reinitialize`, `reconfigure`, `none` |
| `LEAD` | `0.1` | wall time from dispatching the input write to starting the wiggle |
| `GAP` | `0.1` | wall time between the two halves of the wiggle |
| `VERIFY` | `0` | `1` polls until the monitor confirms and reports |
| `DEADLINE` | `10` | with `VERIFY=1`, how long to keep polling |
| `MON` | `BenQ EL2870U` | display name |
| `DESKTOP_HOST` | `the-claw-den` | host to wake for the desktop direction |
| `DESKTOP_WAKE` | `1` | set `0` to skip waking the desktop |

`./sweep.sh` uses these to test each candidate wiggle five times and report which held the switch.

## Waking the desktop

`desktop` wakes the desktop's screen as it switches, so no mouse waggle is needed:

    ssh the-claw-den 'DISPLAY=:0 xset dpms force on; xset s reset'

**The wake is dispatched, not awaited**, like every other send in the switch path (changed
2026-09-03). With the desktop's output powered down, `xset` can take many seconds to return, and the
input write used to queue behind it; now both go out together. The monitor moves to HDMI 1 at once
and the desktop's screen comes up whenever the wake lands. `./display-switch.sh wake` is still the
blocking form, for checking that the wake itself works.

This is not only a convenience. When the monitor switches away, the desktop sees an HDMI
disconnect and powers that output down, so on the way back there may be no live signal for the
monitor to hold — the same failure mode as the DP side. Waking first addresses both.

It is **best effort**: bounded at a 4 s connect and an 8 s hard kill, and a failure posts a
notification from the background job while the switch proceeds regardless. `ssh` here is home-LAN only and has been seen to fail transiently, and
a hotkey must never wedge because the desktop is off or you are away from home.

**The desktop is not suspending, only blanking** (checked 2026-08-30): it answers `ssh` instantly
while the screen is dark, which a suspended machine cannot do. So `xset` is the right lever. If it
ever *did* suspend, `ssh` would be gone and only Wake-on-LAN could reach it — currently not viable,
because the box is on WiFi with Ethernet unplugged, `…/wlp11s0/device/power/wakeup` is `disabled`,
and the driver advertises no WoWLAN. Making it viable means a cable, UEFI WoL, and a persisted
`ethtool -s enp10s0 wol g`. Not worth it for a box that trains 24/7.

If waking turns out not to be enough in a genuinely cold case, the next thing to try is adding
`xrandr --auto`, which helps when X has marked the output *disconnected* rather than merely asleep.
It is deliberately not the default because it re-applies preferred modes and could clobber a custom
layout.

## Timing, and why the sends are fire-and-forget

Measured with the display idle, every call costs about **0.1 s** — DDC reads, DDC writes, refresh-rate
reads alike; a refresh-rate *set* is 0.79 s. Nothing here is inherently slow.

What is slow is an **input transition in progress**. While the monitor is actually changing input the
link is retraining, and every further call queues behind that, taking seconds instead of tenths. That
is the entire source of the multi-second latencies.

Which is why the laptop sequence does not wait for its calls to return. The CLI blocks until
BetterDisplay finishes the work, so a script that awaited the input write would only start the wiggle
several seconds later — long after the monitor had given up on DP 1 and fallen back to HDMI 1. The
three commands are dispatched without waiting and spaced by wall clock instead, so the wiggle begins
`LEAD` (0.1 s) after the input write goes out.

The final rate change back to `60Hz` is dispatched the same way, and **`disown` is what makes that
safe.** The script exits within a second of dispatching it, and a job still owned by the shell can
take a SIGHUP on the way out; disowned, it is reparented and runs to completion. Measured: the rate
lands ~0.5 s after the parent has already exited.

That was worth checking rather than assuming, because an earlier version *did* cut this call off —
not by exiting, but through its own `kill -9` timeout wrapper. The wrapper was the hazard, not the
exit.

Both directions now return in well under a second.

## Verification is opt-in

By default the script dispatches and exits without checking. Verification only existed to drive
retries, and there are no retries — a failed switch is visible on the monitor, and pressing the key
again is faster than any recovery logic. Polling for confirmation also has to contend with the
in-flight writes, which cost more than everything else combined (~16 s versus ~9 s).

    VERIFY=1 ./display-switch.sh laptop     # poll and report

Use it when changing `LEAD`, `GAP` or the wiggle, so a regression shows up as a number.

## Two traps worth knowing

- **`set` always exits 0.** Failure is the word `Failed.` on stdout. Never treat the exit code as
  confirmation — read the value back.
- **`-refreshRate=60` selects the *variable* 40-60Hz mode**, reports success, and leaves the display
  there. Refresh rates must be the exact strings from `get -refreshRateList`: `60Hz`, not `60`.

`PLAN.md` has the full measurement log, including the four wiggle candidates that were eliminated.
