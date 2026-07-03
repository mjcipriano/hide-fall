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

Four input **archetypes** keep the phone code bounded: `tap` (big button, incl.
two-button sequences), `hold` (press-and-hold), `drag` (drag a marker on a bar),
and `choice` (a grid of labelled buttons — answer a few rounds; the game is just
a `make_round()` content generator).

## How to add a new minigame

1. **`minigames.gd` → `CATALOG`**: add `"<id>": {label, instructions, archetype}`.
2. **`minigames.gd` → `params_for`**: add a `match` case with its tuned numbers
   (harder as `difficulty` rises) and a `duration`.
3. **For a word/quiz game** (archetype `choice`): just add a `make_round()` case
   that returns `{prompt, options: [String], correct: int}` (optionally
   `prompt_color`, `memorize`, or `sequence`). The engine handles the rest.
   **For an action game**: add a `_minigame_tick` branch in `hider_client.gd`
   (plus a `_draw_minigame` branch and `_minigame_init_state` if needed).
4. **Tests**: the mobile smoke test loops over every id and asserts it runs to
   completion; `_test_inspection_minigame` validates every `choice` generator.
5. **Bump the count in `_test_inspection_minigame` and mark it below.**

Set `hiders.inspection_minigame` in `default.json` to a single id to force it
(otherwise a random one is picked each pickup); `""` means random.

## Implemented minigames (45)

**Action — tap** (`mash_meter`, `tap_count`, `beat_tap`, `green_light`,
`copy_cat`, `whack`, `perfect_stop`, `bullseye`, `metronome`, `reflex`).
**Action — hold** (`hold_still`, `let_go`, `twitchy`, `deep_breath`,
`charge_up`, `pulse_hold`).
**Action — drag** (`keep_center`, `shadow`, `hot_zone`, `tightrope`,
`trace_wave`, `hot_cold`).
**Word / quiz — choice** (`odd_one_out`, `category_tap`, `real_word`,
`rhyme_time`, `opposite`, `spell_check`, `unscramble`, `missing_letter`,
`first_letter`, `count_letters`, `count_vowels`, `longer_word`, `double_letter`,
`emoji_match`, `stroop`, `math_add`, `math_sub`, `true_math`, `which_bigger`,
`which_smaller`, `odd_number`, `word_recall` memory, `simon_say` sequence).

The 15 action games shipped in v0.3.8; the 30 word/quiz + extra action games in
v0.3.10.

## Practice mode

The mobile startup screen has a **PRACTICE MINIGAMES** button that plays every
minigame back-to-back locally (no host/join needed) with an EXIT button — good
for learning the games and for tuning. It reuses the same engine
(`_start_practice` → `_practice_next` cycles `MinigamesScript.ids()`), so a new
minigame automatically shows up in practice too.

## Backlog ideas

- Accelerometer "don't move the phone" game (needs device motion input).
- Two-player co-op inspection when multiple hiders are held.
