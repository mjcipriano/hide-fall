# Network Protocol

Transport target: local WebSocket LAN.

Protocol version: `1`.

Clients send input and requests. The host owns physics, phase transitions, hit detection, scoring, and final object state.

## Client Messages

```json
{
  "type": "join_request",
  "version": 1,
  "room_id": "842913",
  "token": "short-session-token",
  "player_name": "Alex"
}
```

```json
{
  "type": "hider_input",
  "version": 1,
  "player_id": "p3",
  "move": [0.2, -0.8],
  "rotate": 0.1,
  "freeze": false,
  "request_shape": null,
  "request_color": "blue",
  "ability": null,
  "client_time": 123.45
}
```

```json
{
  "type": "ready_state",
  "version": 1,
  "player_id": "p3",
  "ready": true
}
```

## Host Messages

```json
{
  "type": "state_snapshot",
  "version": 1,
  "server_tick": 1024,
  "phase": "seek",
  "time_remaining": 81.2,
  "shots_remaining": 5,
  "scan_pulses_remaining": 1,
  "hider_state": {},
  "nearby_objects": [],
  "danger": "watched",
  "cooldowns": {}
}
```

```json
{
  "type": "join_accepted",
  "version": 1,
  "player_id": "p3",
  "room_id": "842913",
  "spectator": false,
  "settings": {},
  "shapes": ["cube", "sphere"],
  "colors": ["red", "blue"]
}
```

When late joins are disabled after the lobby, the host accepts the peer as a spectator instead of rejecting the connection:

```json
{
  "type": "join_accepted",
  "version": 1,
  "player_id": "p9",
  "room_id": "842913",
  "spectator": true,
  "settings": {},
  "shapes": ["cube", "sphere"],
  "colors": ["red", "blue"]
}
```

```json
{
  "type": "join_rejected",
  "version": 1,
  "reason": "round_in_progress",
  "detail": "Late join is disabled until the next lobby."
}
```
