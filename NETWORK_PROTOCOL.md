# Network Protocol

Transport target: local WebSocket LAN.

Protocol version: `1`.

Clients send input and requests. The host owns physics, phase transitions, hit detection, scoring, and final object state.

## LAN Discovery Beacon

The Quest host broadcasts a UDP beacon (default port `29445`, `network.discovery_port`) about once per second so phones can list joinable games without QR scanning or typing. The beacon is JSON:

```json
{
  "game": "hidefall",
  "beacon_version": 1,
  "host_name": "Michael's Quest Room",
  "host_ip": "192.168.1.42",
  "port": 29444,
  "room_id": "842913",
  "token": "hidefall",
  "phase": "lobby",
  "players": 3,
  "protocol_version": 1
}
```

Phones bind the discovery port, validate `game == "hidefall"`, take the sender address as `host_ip`, and expire entries not re-announced within 5 seconds. Manual IP/room-code entry remains the fallback when broadcast is filtered.

## Client Messages

`preferred_*` fields are optional pre-join disguise choices; the host validates them against content ids and applies them when the hider spawns.

```json
{
  "type": "join_request",
  "version": 1,
  "room_id": "842913",
  "token": "short-session-token",
  "player_name": "Alex",
  "preferred_shape": "duck",
  "preferred_color": "purple",
  "preferred_pattern": "stripes"
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

Snapshot objects carry `pattern` and an `[x, y, z, w]` `orientation` quaternion so phone clients can render the same 3D world. `seeker` is the headset pose. `shot_cooldown_remaining` tells hiders when the gun is cooling (their escape window).

```json
{
  "type": "state_snapshot",
  "version": 1,
  "server_tick": 1024,
  "phase": "seek",
  "time_remaining": 81.2,
  "shots_remaining": 5,
  "shot_cooldown_remaining": 1.8,
  "scan_pulses_remaining": 1,
  "objects": [
    {
      "object_id": "obj_002",
      "shape": "mug",
      "color": "red",
      "pattern": "stripes",
      "position": [1.0, 0.15, 0.5],
      "orientation": [0.0, 0.0, 0.0, 1.0],
      "velocity": [0.0, 0.0, 0.0],
      "is_hider": false,
      "alive": true
    }
  ],
  "seeker": {"position": [0.4, 1.6, 1.2], "forward": [0.0, 0.0, -1.0]},
  "hider_state": {},
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
  "colors": ["red", "blue"],
  "patterns": ["solid", "stripes"]
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
