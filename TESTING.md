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
- Hider movement constraints.
- Shape/color cooldowns.
- Correct and wrong shot behavior.
- Round ending when all hiders are found or time expires.
- Deterministic bot/simulation behavior.

