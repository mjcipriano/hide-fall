# Hider Inspection Minigames

When the seeker **picks up (inspects)** a live hider, the hider must pass a short
minigame on their phone to *hold still*. Passing keeps the prop looking like an
inert decoy; **failing makes it shake, yelp, and jump out of the seeker's hand**
— a dead giveaway that it was alive, but not an elimination. Difficulty ramps
each time the same hider is re-inspected in a round.

Every minigame **shows its instructions first** (a ~1.5s "GET READY" intro so the
player can read and prepare), then plays.

## Architecture

The minigame **runs locally on the phone** so input is instant (real `Button`
nodes and a drag bar — no network round-trip per tap). The host is thin:

- **Host / sim** (`hidefall_simulation.gd`): on grabbing a live hider,
  `_start_inspection` picks a random minigame (or `hiders.inspection_minigame`
  if set) and records `{minigame, difficulty, time_limit}` in the snapshot's
  `hider_state.inspection`. `_update_inspections` only enforces the safety
  deadline — if the phone never reports (idle/cheat/disconnect) it auto-fails.
  `resolve_inspection(player_id, passed)` applies the phone's reported result:
  pass clears the inspection (calm, still held); fail runs `_fail_inspection`
  (upward jolt + spin + `inspection_failed` event). Difficulty = how many times
  this hider has been inspected.
- **Network**: phone → host `minigame_result {player_id, passed}` (validated in
  `network_message_validator.gd`); host routes it to `resolve_inspection`.
- **Host feedback** (`host_prototype.gd`): plays `surprised` + drops the grab on
  fail, `inspect_pass` on success.
- **Phone engine** (`hider_client.gd`): `_update_minigame` launches the local
  game when an inspection appears; `_minigame_start` → intro → `_minigame_tick`
  per game → `_minigame_finish(passed)` sends the result. Input via `_on_mg_a_*`
  / `_on_mg_b_down` (buttons) and `_on_mg_bar_input` (drag).
- **Catalog** (`minigames.gd`, `HidefallMinigames`): single source of truth —
  `CATALOG` (id → label, instructions, archetype), `params_for(id, difficulty)`
  (all tuned numbers), `random_id`, `time_limit`, `INTRO_SECONDS`.

Three input **archetypes** keep the phone code bounded: `tap` (big button, incl.
two-button sequences), `hold` (press-and-hold), `drag` (drag a marker on a bar).

## How to add a new minigame

1. **`minigames.gd` → `CATALOG`**: add `"<id>": {label, instructions, archetype}`.
2. **`minigames.gd` → `params_for`**: add a `match` case with its tuned numbers
   (harder as `difficulty` rises) and a `duration`.
3. **`hider_client.gd`**: add a `match` branch to `_minigame_tick` (and a draw
   branch in `_draw_minigame`, and init in `_minigame_init_state` if needed). If
   it fits an existing archetype's widgets you don't touch the input handlers.
4. **Tests**: the mobile smoke test already loops over every id and asserts it
   runs to completion; add a rule-specific assertion if the logic is subtle.
5. **Mark it in the table below.**

Set `hiders.inspection_minigame` in `default.json` to a single id to force it
(otherwise a random one is picked each pickup); `""` means random.

## Implemented minigames (15)

| id | label | archetype | goal | status |
|----|-------|-----------|------|--------|
| `mash_meter` | Mash! | tap | tap fast to fill the bar | ✅ v0.3.8 |
| `tap_count` | Tap Ten | tap | tap exactly the target count | ✅ v0.3.8 |
| `beat_tap` | On The Beat | tap | tap when the sweep is centred, N times | ✅ v0.3.8 |
| `green_light` | Green Means Go | tap | tap only while green, N times | ✅ v0.3.8 |
| `copy_cat` | Copy Cat | tap (2-btn) | repeat the L/R sequence | ✅ v0.3.8 |
| `whack` | Whack-a-Prop | tap | tap the hopping target N times | ✅ v0.3.8 |
| `perfect_stop` | Perfect Stop | tap | tap to stop the marker in the zone | ✅ v0.3.8 |
| `hold_still` | Hold Still | hold | hold until the bar fills | ✅ v0.3.8 |
| `let_go` | Let Go Now | hold | release while the bar is in the zone | ✅ v0.3.8 |
| `twitchy` | Twitchy | hold | hold, but release on every flash | ✅ v0.3.8 |
| `deep_breath` | Deep Breath | hold | hold on IN, release on OUT (rhythm) | ✅ v0.3.8 |
| `keep_center` | Keep Centered | drag | keep the dot in the zone vs drift | ✅ v0.3.8 |
| `shadow` | Shadow | drag | keep the dot on the moving target | ✅ v0.3.8 |
| `hot_zone` | Hot Zone | drag | keep the dot in the jumping zone | ✅ v0.3.8 |
| `tightrope` | Tightrope | drag | keep the dot dead-centre (tiny zone) | ✅ v0.3.8 |

## Practice mode

The mobile startup screen has a **PRACTICE MINIGAMES** button that plays every
minigame back-to-back locally (no host/join needed) with an EXIT button — good
for learning the games and for tuning. It reuses the same engine
(`_start_practice` → `_practice_next` cycles `MinigamesScript.ids()`), so a new
minigame automatically shows up in practice too.

## Backlog ideas

- Accelerometer "don't move the phone" game (needs device motion input).
- Two-player co-op inspection when multiple hiders are held.
