# Open work

- In-game check of 1.5.0 (not done yet): blueprint a requester chest and let robots build it; place a provider north, then south of it, and confirm requests turn off and on and deliveries arrive; walk and drive south with "Allow players to move down" off; Ctrl+Z after a south belt is auto-rotated.
- Measure `update_requesters` (every 180 ticks) in a large base; raise the interval if it shows up in the F4 timings.

# Decisions

- Pipes carry fluid any direction; only pumps are restricted (owner's call, don't change).
- Trains east-west only, no elevated rail (owner's call, kept for now).
- Bots can't be steered (robot orders are read-only, no delivery event), so the logistics rule gates requesters by position instead. The remaining southward bot trips are listed in README "Known gaps".
