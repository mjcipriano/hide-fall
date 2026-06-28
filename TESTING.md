# Testing

Run all local checks:

```bash
make test
```

This validates JSON content and runs Godot headless tests.

Current coverage:

- Content/config parsing.
- Color and object definition validity.
- Phase transitions.
- Ready-gated round start and room setup confirmation.
- Hider movement constraints.
- Shape/color cooldowns.
- Scan pulse reveal and charge consumption.
- Late join spectator handling.
- Mobile join, ready, input, snapshot, and disguise request handling.
- Host join, snapshot, pickup/drop, scan, and spectator smoke behavior.
- Correct and wrong shot behavior.
- Round ending when all hiders are found or time expires.
- Deterministic bot/simulation behavior.
