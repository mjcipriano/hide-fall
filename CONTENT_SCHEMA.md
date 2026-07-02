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

- `round.mode` — `one_shot` (found hiders are out) or `endless_hiders` (found hiders respawn into surviving decoy bodies; every shot object is destroyed).
- `round.object_rain_seconds`
- `round.room_setup_seconds`
- `round.seek_seconds`
- `round.results_seconds`
- `round.end_on_seek_timeout` — default `false`: the hunt timer does not end the round.
- `round.end_when_out_of_shots` — default `true`: spending the last shot ends the round.
- `round.max_hiders`
- `objects.decoy_count`
- `seeker.base_bullets`
- `seeker.bullets_per_hider`
- `seeker.shot_cooldown_seconds` — wait between shots; the hiders' escape window.
- `seeker.consume_shot_on_hit` — default `false`: only misses (decoys) consume a shot.
- `seeker.scan_pulse_enabled`
- `seeker.scan_pulse_count`
- `hiders.movement_speed`
- `hiders.shape_change_cooldown`
- `hiders.color_change_cooldown`
- `hiders.earthquake_enabled` / `hiders.earthquake_uses` / `hiders.earthquake_power` — one-use room-shaking ability.
- `hiders.ping_cooldown_seconds` — cooldown for the spatial taunt jingle.
- `hiders.bot_decision_seconds`
- `network.port`
- `network.discovery_port` — UDP port for the LAN game beacon (must differ from `network.port`).
- `network.discovery_interval_seconds`
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
- `rest_mode`: how the prop settles when dropped — one of:
  - `face`: topples to the nearest of its six axis faces (cube, toy block).
  - `flat`: lies flat on its top or underside (ring, donut, book, star).
  - `upright`: always stands back up (cone, pyramid, duck, mug).
  - `side`: lies on its side (capsule).
  - `side_or_upright`: stands if mostly upright, else rolls onto its side (cylinder, can, bottle).
  - `any`: rests exactly as placed (sphere).

Visual meshes for each shape id are built in `game/scripts/shared/props/prop_factory.gd`; adding a shape id without a factory case falls back to a cube mesh.

## `objects/colors.json`

Array of colors:

- `id`: stable lowercase identifier.
- `display_name`: UI label.
- `hex`: `#RRGGBB`.
- `colorblind_safe`: boolean.

## `objects/patterns.json`

Array of surface patterns applied on top of the color:

- `id`: stable lowercase identifier (`solid` must exist).
- `display_name`: UI label.
- `spawn_weight`: positive number; relative chance a decoy spawns with this pattern.

Pattern rendering (procedural textures / material properties) is implemented per id in `prop_factory.gd`: `stripes`, `dots`, `checker`, `wood` are grayscale tile textures; `metallic` and `glow` adjust material properties; unknown ids render as solid.
