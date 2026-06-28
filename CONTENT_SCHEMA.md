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

