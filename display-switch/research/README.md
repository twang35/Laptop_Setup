# research

The harnesses used to work out the timing, kept for provenance. `../PLAN.md` has the results and the
reasoning; these are how the numbers were produced.

| file | state |
|---|---|
| `recipe.sh` | **works.** Scores *first-attempt* success for each ordering of the input write and the wiggle. `PARK=` sets how long to sit on the desktop first. Self-contained — talks to BetterDisplay directly |
| `probe.sh` | **works.** Dispatches one write-and-wiggle, then polls until the input flips, to tell a premature read apart from a failed switch. Self-contained |
| `sweep.sh` | **historical.** Compared the wiggle candidates, and established that the choice of wiggle does not matter. It drives `display-switch.sh` through `WIGGLE=` and `TRIES=`, which the rewritten script no longer has, so it will not run as-is |

The single most useful thing in here is the lesson `probe.sh` exists to catch: a verification
threshold is a parameter under test, not a constant. `sweep.sh`'s original run reported 14 of 15
trials needing a second attempt, which sent the investigation after the wrong cause — the switch had
been working all along and the read was arriving 3 seconds too early.
