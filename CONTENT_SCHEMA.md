# Content Schema

All gameplay content lives in `game/content`.

## `settings/default.json`

Top-level keys:

- `round`
- `objects`
- `seeker`
- `hiders`
- `network`

Durations are seconds. Object counts are integers. Cooldowns are seconds.

Currently used gameplay settings include:

- `round.object_rain_seconds`
- `round.room_setup_seconds`
- `round.blackout_seconds`
- `round.seek_seconds`
- `round.results_seconds`
- `round.max_hiders`
- `objects.decoy_count`
- `seeker.bullets_base`
- `seeker.bullets_per_hider`
- `seeker.scan_pulse_enabled`
- `seeker.scan_pulse_count`
- `hiders.move_speed`
- `hiders.freeze_bonus_seconds`
- `hiders.shape_change_cooldown`
- `hiders.color_change_cooldown`
- `hiders.bot_decision_seconds`
- `network.default_port`
- `network.allow_late_join`

## `objects/shapes.json`

Array of shape definitions:

- `id`: stable lowercase identifier.
- `display_name`: UI label.
- `size_class`: `small`, `medium`, or `large`.
- `mass`: positive number.
- `friction`: `0.0` to `2.0`.
- `bounce`: `0.0` to `1.0`.
- `roll_factor`: `0.0` to `1.5`.
- `rarity_weight`: positive number.

## `objects/colors.json`

Array of colors:

- `id`: stable lowercase identifier.
- `display_name`: UI label.
- `hex`: `#RRGGBB`.
- `colorblind_safe`: boolean.
