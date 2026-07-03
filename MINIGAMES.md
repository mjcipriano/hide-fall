# Hider Inspection Minigames

When the seeker **picks up (inspects)** a live hider, the hider must pass a short
minigame on their phone to *hold still*. Passing keeps the prop looking like an
inert decoy; **failing makes it shake, yelp, and jump out of the seeker's hand**
— a dead giveaway that it was alive, but not an elimination. Difficulty ramps
each time the same hider is re-inspected in a round.

This document is the contract for adding minigames so any agent can drop a new
one in. Keep them **mobile-friendly, thumb-reachable, and short (< ~6 seconds)**.

## Architecture

All minigame *rules* live in one shared, authoritative module so the host and
tests agree and phones cannot cheat:

- `game/scripts/shared/game_state/minigames.gd` (`HidefallMinigames`)
  - `CATALOG` — id → `{label, hint, input}` metadata.
  - `make_state(id, difficulty)` — starting state; must get harder as `difficulty` (0..6) rises.
  - `step(state, push, delta)` — deterministic per-tick rule; sets `status` to `"success"` or `"fail"`.
  - `snapshot(state)` — the compact, render-only view sent to phones.

Wiring (already in place, you rarely touch it):

- **Sim** (`hidefall_simulation.gd`): `set_object_held(id, true)` on a live hider
  calls `_start_inspection`; `_update_inspections(delta)` runs each seek tick and
  calls `_fail_inspection` (pop-out jolt + `inspection_failed` event) on failure
  or emits `inspection_passed` on success. The phone's `minigame_input` (-1..1)
  is captured in `apply_hider_input` even while held, and stored as
  `obj["minigame_push"]`. The inspection view rides the snapshot in
  `get_hider_state().inspection`.
- **Host** (`host_prototype.gd`): `_process_simulation_events` plays `surprised`
  on fail (and drops the grab) and `inspect_pass` on success.
- **Phone** (`hider_client.gd`): `_update_minigame` shows/hides the overlay from
  the snapshot; `_draw_minigame` renders it; `_on_minigame_input` sends the push.
- **Config**: `hiders.inspection_minigame_enabled` (bool) and
  `hiders.inspection_minigame` (which id to use).

## How to add a new minigame

1. **`minigames.gd` → `CATALOG`**: add `"<id>": {"label": ..., "hint": ..., "input": ...}`.
2. **`minigames.gd` → `make_state`**: add a `match` case returning the start
   state, tuned so higher `difficulty` is meaningfully harder.
3. **`minigames.gd` → `step`**: add a `match` case that advances the state and
   sets `status` to `"success"`/`"fail"`. Keep it deterministic (no RNG) so
   headless tests are stable.
4. **`hider_client.gd`**: add a branch to `_draw_minigame` (and, if it needs a
   different control, `_on_minigame_input`) keyed by the same id.
5. **Tests** (`game/tests/test_runner.gd`, `_test_inspection_minigame` or a new
   test): assert a pass path and a fail path.
6. **Mark it done in the table below.**

To make a minigame the default, set `hiders.inspection_minigame` in
`game/content/settings/default.json` to its id.

## Implemented minigames

| id | label | input | difficulty scales | status | implemented |
|----|-------|-------|-------------------|--------|-------------|
| `steady_balance` | Steady Hands | drag left/right | zone shrinks, drift speeds up + flips faster, duration grows, out-of-zone tolerance shrinks | ✅ done | v0.3.7 (2026-07-02) |

## Backlog ideas (not yet implemented)

- `tap_rhythm` — tap in time with a pulsing ring; miss too many beats → drop.
- `hold_breath` — press and hold; release exactly when a shrinking bar empties.
- `dont_react` — decoy taps appear; tap real prompts, ignore fake-outs (Simon-ish).
- `trace_path` — drag a dot along a wandering line without leaving it.

When you implement one, move it up to the table and record the version.
