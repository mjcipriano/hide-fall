I’d build this as a **mixed-reality prop-hunt party game**: the Quest player is the seeker walking around the real room, while phone players are live controllable props hiding among physics objects in that same MR space.

For the implementation basis: Godot is still a good fit for AI-agent coding because Godot scenes/scripts/resources are mostly text-editable, Godot supports high-level multiplayer abstractions over ENet, WebRTC, and WebSocket peers, and Godot can export to Android and iOS with the usual platform signing caveats. ([Godot Engine documentation][1]) For Quest MR, the Godot OpenXR Vendors Plugin has Meta Quest passthrough support, spatial anchors, hand tracking, and scene-related features that match this game’s needs. ([Godot VR][2]) For local multiplayer, I’d use Quest-hosted LAN play with QR-code joining plus optional network discovery; Android has Network Service Discovery for local services, while iOS requires local-network privacy handling, so QR fallback is important. ([Android Developers][3])

Here is the full game design document.

# Game Design Document: **Hidefall**

> **Implementation amendments (2026-07-02, v0.3.3).** The shipped game deviates from this document in the following ways, by the owner's direction; where they conflict, the amendments win:
>
> 1. **No blackout phase.** The round flow is lobby → (optional room setup) → object rain → seek. Hiders drop from the ceiling together with the decoys during object rain and can steer as they land; there is no vision-darkening stage. `round.blackout_seconds` no longer exists.
> 2. **Ammo economy.** By default a shot is only consumed on a **miss** (shooting a decoy); hitting a live hider is free (`seeker.consume_shot_on_hit=false`). The round ends when the seeker spends their last shot (`round.end_when_out_of_shots=true`); surviving hiders win. The seek timer does **not** end the round by default (`round.end_on_seek_timeout=false`) — it can be re-enabled from the in-game settings menu.
> 3. **No head-locked seeker HUD.** Status (phase, timer, shots/gun state, scans, join info) lives on a compact left-wrist panel; a toggleable wrist settings menu (left Y button) carries round actions and all live-tunable settings. QR joining is desktop-only; phones join via LAN discovery or manual entry because a QR rendered inside the headset cannot be scanned.
> 4. **Hider abilities.** `Freeze` was replaced on phones by `Dash` (burst of speed) and `Mimic` (instantly copy an adjacent decoy's shape/color/pattern), both with cooldowns.

## 1. High Concept

**Hidefall** is a local mixed-reality party game for Meta Quest 3 and phones. One player wears the Quest headset and becomes the **Seeker**. Other players join from Android or iPhone as **Hiders**, each controlling a disguised object inside the Seeker’s real room.

At the start of each round, dozens of colorful physics objects rain from above and scatter across the room. During a short blackout phase, phone players choose a shape and color, spawn into the room as one of the objects, and hide among the clutter. When the lights return, the Quest player walks around the room, picks up objects, inspects them, and uses a limited number of shots to identify the living props before time runs out.

The core fantasy is:

> “A bunch of objects just fell into my real room. Some of them are my friends. I have to figure out which ones are alive before they escape detection.”

The game should feel chaotic, funny, physical, and social. It should be easy to set up in a living room, office, bedroom, or playroom, and should support quick rounds with lots of replayability.

---

# 2. Platforms

## 2.1 Quest 3 App

The Quest 3 app is the main host and authoritative game simulation.

The Quest player sees the real room through passthrough mixed reality. Virtual objects fall into the room, land on the floor, collide with one another, and can be picked up, thrown, bumped, or shot.

The Quest app is responsible for:

* Hosting the local game lobby.
* Mapping or approximating the play area.
* Spawning all physical props.
* Running the authoritative physics simulation.
* Tracking the Seeker’s hands/controllers/headset.
* Receiving hider input from phones.
* Applying hider movement, disguise changes, and collisions.
* Determining hits, captures, round outcomes, and scoring.
* Broadcasting simplified game state to phone clients.

## 2.2 Phone App

The phone app is not VR/AR. It is a 2D arcade-style controller and mini-game interface.

Phone players see a stylized top-down or angled 2D representation of the room. They control their object with touch controls, select shape/color, dodge attention, hide among decoys, and react to the Seeker’s actions.

The phone app is responsible for:

* Joining the Quest-hosted room.
* Choosing player name/avatar.
* Selecting or randomizing object type and color.
* Moving the hider object.
* Triggering disguise changes.
* Showing danger indicators when the Seeker is nearby.
* Showing when the hider is being held, inspected, shot at, or hidden.
* Displaying score, round status, and post-round results.

---

# 3. Target Experience

## 3.1 Player Count

Recommended:

* Minimum: 1 Quest Seeker + 1 phone Hider.
* Ideal: 1 Quest Seeker + 2–5 phone Hiders.
* Maximum initial target: 1 Quest Seeker + 8 phone Hiders.

The game should technically support bots so it can be tested with no phone players or only one phone player.

## 3.2 Session Length

A full session should last 10–20 minutes.

A single round should last 2–4 minutes.

Default round timing:

* Lobby/setup: variable.
* Object rain phase: 10 seconds.
* Blackout/hide phase: 10 seconds.
* Seek phase: 90 seconds.
* Results phase: 15 seconds.

All phase durations should be configurable.

## 3.3 Tone

The tone should be playful and chaotic rather than scary.

Visual style should be colorful, readable, and toy-like. Objects should be easy to distinguish at a glance, but there should be enough variety that hiding is meaningful.

The game should create funny moments:

* A hider bumps into a pile and accidentally reveals themselves.
* The Seeker picks up a suspicious cone and stares at it while the phone player freezes.
* A hider slowly slides away behind the Seeker’s back.
* Several props all wobble from a chain reaction.
* The Seeker wastes their last shot on a decoy.

---

# 4. Core Gameplay Loop

## 4.1 Round Flow

Each round follows this structure:

1. **Lobby**

   * Quest player creates a room.
   * Phone players join.
   * Host sets game options.
   * Players ready up.

2. **Room Setup**

   * Quest player confirms floor height and play boundary.
   * Game creates a safe virtual play zone.
   * Optional room mesh/walls/furniture data is used if available.
   * Fallback arena is created if room scanning is unavailable.

3. **Object Rain**

   * Many decoy objects fall from above for a configurable duration.
   * Objects bounce, roll, collide, and settle.
   * Phone players can preview object types/colors during this phase.

4. **Blackout Countdown**

   * Quest player receives warning countdown.
   * Quest vision darkens.
   * Hiders finalize object type/color and spawn into the room.
   * Hiders move into position.

5. **Seek Phase**

   * Quest vision returns.
   * Quest player searches the room.
   * Hiders can move, rotate, change disguise, and bump objects, but must avoid looking suspicious.
   * Seeker can pick up objects, inspect them, throw them, or shoot them.
   * Seeker has limited shots.

6. **Round End**

   * Round ends when all hiders are found, time expires, or the Seeker runs out of shots and confirms surrender.
   * Results show who survived, who was found, accuracy, best hiding score, and funniest stats.

7. **Role/Rematch**

   * Players can rematch.
   * Seeker role can rotate.
   * Game settings can be adjusted.

---

# 5. Player Roles

## 5.1 Seeker: Quest Player

The Seeker is physically present in the room wearing the Quest headset.

The Seeker’s goals:

* Find all live hider objects.
* Use shots carefully.
* Inspect suspicious props.
* Watch for movement, unnatural positioning, color changes, or suspicious collisions.
* Find hiders before the timer expires.

Seeker abilities:

* Walk around the safe real-world play space.
* Look around in passthrough.
* Pick up props.
* Drop or throw props.
* Shoot suspicious props.
* Use limited “scan pulse” ability if enabled.
* Call out guesses socially.

Seeker limitations:

* Limited bullets.
* Limited time.
* Cannot see during blackout.
* Cannot shoot while holding an object unless specifically enabled.
* Cannot see hider names until they are revealed.
* Must stay within safe play boundary.

## 5.2 Hider: Phone Player

Each Hider controls one live object in the Quest player’s room.

The Hider’s goals:

* Blend into the scattered decoy objects.
* Avoid being shot.
* Move only when safe.
* Change shape/color strategically.
* Use physics chaos to hide.
* Survive until time expires.

Hider abilities:

* Choose starting object type.
* Choose starting object color.
* Move around the room with touch controls.
* Rotate object.
* Nudge nearby objects.
* Change object type if not being held.
* Change color if not being held.
* Freeze/lock into place for a stealth bonus.
* Use one optional special ability depending on selected object class.

Hider limitations:

* Movement creates risk.
* Disguise changes have cooldowns.
* Larger objects are easier to spot.
* Smaller objects may move slower or be easier to knock away.
* Hider cannot move or transform while being held by the Seeker.
* If shot, hider is revealed and eliminated.
* If thrown too hard or moved outside the play area, hider is auto-returned with a penalty.

---

# 6. Game Phases in Detail

## 6.1 Lobby Phase

The Quest player starts the app and chooses **Host Game**.

The Quest headset displays:

* Room name.
* Room code.
* QR code.
* Current network name if available.
* Joined players.
* Ready status.
* Game options.

Phone players open the mobile app and choose **Join Game**.

Join options:

1. **Scan QR code**

   * Preferred method.
   * QR contains IP address, port, room ID, and short verification token.

2. **Auto-discover local game**

   * App scans for local hosts.
   * If found, shows “Michael’s Quest Room” or similar.

3. **Manual join**

   * Player enters room code and IP address.
   * Used as fallback.

Phone lobby shows:

* Player name.
* Color/avatar.
* Connection status.
* Ready button.
* Latency indicator.
* Object preview carousel.
* Round rules summary.

The lobby should support late joins, but late players become spectators until the next round unless the host enables mid-round joining.

## 6.2 Room Setup Phase

The Quest host needs to define a safe mixed-reality play space.

The game should support two setup modes.

### Simple Setup: Default

This is the MVP mode.

The game uses the headset’s floor height and guardian/play boundary. It creates a rectangular or oval virtual spawn area inside the safe boundary.

The Quest player confirms:

* Floor looks correct.
* Spawn area is not too close to walls.
* Player can move safely.

The game shows a glowing outline on the floor representing the play area.

### Advanced Setup: Room-Aware

If scene data is available, the game can use room mesh, walls, floor, and large furniture surfaces.

Room-aware features:

* Objects fall only onto valid floor areas.
* Objects avoid spawning inside real furniture.
* Walls block objects.
* Furniture can become hiding terrain if stable.
* Anchors keep the virtual room stable across rounds.

This should be treated as an enhancement, not required for first playable build.

## 6.3 Object Rain Phase

The Seeker sees objects falling from the ceiling into the room.

Default object count:

* Small room: 40 objects.
* Medium room: 75 objects.
* Large room: 120 objects.

Configurable range:

* Minimum: 20.
* Default: 75.
* Maximum initial target: 150.

Objects spawn above the play area, fall with gravity, bounce, collide, and settle.

Object rain should feel funny and physical, not dangerous or visually overwhelming.

Object categories:

* Basic shapes: cube, sphere, cylinder, cone, capsule, pyramid.
* Toy objects: rubber duck, block, ring, star, gear, bottle, cup.
* Household-ish fake props: box, can, ball, pillow, book, mug.
* Weird props: gem, alien egg, tiny statue, banana, donut, fish.

Each object has:

* Shape type.
* Color.
* Size class.
* Mass.
* Friction.
* Bounciness.
* Pickup grip point.
* Sound profile.
* Rarity weight.

During object rain, phone players can already browse the disguise menu but cannot fully move until blackout begins unless “early planning” mode is enabled.

## 6.4 Blackout Phase

The Quest player receives a countdown:

* “Objects settled.”
* “Hiders preparing.”
* “Vision blackout in 3…2…1…”

The Quest player’s vision darkens using an in-game blackout overlay. The actual passthrough should not be disabled in a way that creates safety risk. The player should be instructed to stand still during blackout.

During blackout:

* Hiders choose or confirm object type.
* Hiders choose color.
* Hiders spawn into available positions.
* Hiders move to hiding spots.
* Decoy objects may receive subtle random settling motions so hider movement is harder to detect from sound alone.

Default blackout duration: 10 seconds.

Configurable range: 5–30 seconds.

Hider spawn options:

* Random spawn among decoys.
* Spawn near edge of room.
* Spawn near similar objects.
* Host-configurable.

The game should prevent hiders from spawning too close to the Seeker’s feet or outside the safe play area.

## 6.5 Seek Phase

When blackout ends:

* Seeker vision returns.
* Seek timer starts.
* Hiders become vulnerable.

The Seeker searches the room and tries to identify live objects.

The phone players can continue moving or transforming, but every action creates risk.

### Hider Movement Rules

Hiders move using a virtual joystick or swipe-to-move interface.

Movement options:

* Slow creep: quiet, safer, low speed.
* Quick dash: faster, creates visible wobble/trail/sound.
* Rotate in place: low risk, useful for blending.
* Freeze: no movement, builds stealth score.

Movement should not be instant. Objects should accelerate and slide naturally.

Hider movement should be physically simulated on the Quest host. Phones send movement input, not final positions.

### Disguise Change Rules

Hiders can change:

* Shape.
* Color.
* Size variant, if enabled.
* Surface pattern, if unlocked.

Rules:

* Cannot change while being held.
* Cannot change for 2 seconds after being dropped.
* Cannot change while airborne.
* Shape change cooldown: default 12 seconds.
* Color change cooldown: default 6 seconds.
* Changing creates a small pop, shimmer, or rustle visible to the Seeker.
* Repeated changes reduce stealth score.

This prevents hiders from constantly morphing with no penalty.

### Pickup Rules

The Seeker can pick up most objects.

When a hider object is picked up:

* Phone player sees “You are being inspected!”
* Hider movement is disabled.
* Hider transformation is disabled.
* Hider can perform a small “panic wiggle” only if enabled.
* Seeker may rotate and inspect the object.
* If the Seeker drops it, hider regains control after a short stun.

Pickup should not automatically reveal the hider. The Seeker still has to decide whether to shoot.

### Shooting Rules

The Seeker has limited bullets.

Default bullets:

* 1 hider: 3 bullets.
* 2 hiders: 5 bullets.
* 3 hiders: 6 bullets.
* 4+ hiders: hiders + 3 bullets.

Configurable.

When the Seeker shoots:

* If the object is a hider, that hider is revealed and eliminated.
* If the object is a decoy, the object bursts, dents, or flies away, and the Seeker loses a bullet.
* If bullets reach zero, Seeker can still inspect but cannot eliminate except through optional “final guess” mode.

Shot feedback:

* Correct shot: big reveal effect, hider name appears, sound cue, score popup.
* Wrong shot: sad trombone/thunk, bullet count decreases, decoy reacts physically.
* Near miss: object reacts but no elimination.

The shot should require deliberate aiming. Use a simple raycast from controller or hand pointer.

## 6.6 Round End

Round ends when:

* All hiders are found.
* Seek timer expires.
* Seeker runs out of bullets and host setting ends round automatically.
* All hiders disconnect.
* Host manually ends round.

Results shown to Quest and phones:

* Seeker score.
* Hider survival status.
* Time survived.
* Shots fired.
* Accuracy.
* Best hider.
* Most suspicious movement.
* Longest freeze.
* Most chaotic collision.
* Closest call.
* Object disguise used.
* Replay/rematch buttons.

---

# 7. Scoring

Scoring should make both roles fun.

## 7.1 Seeker Score

Seeker earns points for:

* Finding hiders.
* Finding hiders quickly.
* Maintaining shot accuracy.
* Inspecting fewer decoys.
* Winning with bullets remaining.
* Finding hiders while they are moving.
* Finding all hiders before time expires.

Seeker loses or fails to gain points for:

* Shooting decoys.
* Running out of bullets.
* Taking too long.
* Throwing too many objects outside bounds.
* Unsafe behavior, if detected.

Example scoring:

* Correct shot: +500.
* Time bonus: +0–500.
* Bullet remaining: +100 each.
* Wrong shot: -150.
* All hiders found: +1000.

## 7.2 Hider Score

Hiders earn points for:

* Surviving to the end.
* Remaining still while Seeker is nearby.
* Moving without being seen.
* Successfully changing disguise near danger.
* Causing decoy confusion.
* Being picked up and not shot.
* Escaping suspicion after inspection.

Hiders lose or fail to gain points for:

* Excessive movement.
* Frequent disguise changes.
* Being shot early.
* Leaving the play area.
* Disconnecting.

Example scoring:

* Survive round: +1000.
* Each second alive: +10.
* Freeze near Seeker: +5/sec.
* Successful close call: +250.
* Picked up but not shot: +300.
* Shot: survival scoring stops.

## 7.3 Team Scoring

Optional team modes:

* Seeker vs all hiders.
* Hider team score based on number of survivors.
* Rotating seeker tournament.
* Best-of-five rounds.

---

# 8. Core Fun Mechanics

## 8.1 Suspicion System

The game should track “suspicion” for hiders. This does not automatically reveal them, but it drives phone feedback and optional assistive UI.

Suspicion increases when:

* Hider moves while Seeker is looking nearby.
* Hider changes shape/color in line of sight.
* Hider bumps many objects.
* Hider moves faster than normal physics clutter.
* Hider is isolated in an unnatural place.
* Hider is picked up.

Suspicion decreases when:

* Hider freezes.
* Hider remains among similar objects.
* Hider is far from Seeker.
* Hider blends near matching color/shape decoys.

Phone UI can show:

* Safe.
* Watched.
* Suspicious.
* Critical.

This helps phone players understand risk.

## 8.2 Blend Bonus

Hiders should be rewarded for blending into clusters.

A hider gets a blend bonus if:

* Nearby objects share similar color.
* Nearby objects share similar shape.
* Hider is partially occluded by other props.
* Hider is stationary.
* Hider is in a believable resting orientation.

This encourages actual hiding, not just running away.

## 8.3 Physics Chaos

Physics is central to the game.

Important physics behaviors:

* Objects collide with each other.
* Hider movement can push decoys.
* Seeker can bump piles with hands/controllers.
* Thrown objects scatter piles.
* Heavy objects move slowly but can shove others.
* Round objects roll easily and are harder to control.
* Tall objects tip over.

Physics should be fun but stable. The game should limit maximum velocities and auto-sleep resting objects to maintain performance.

## 8.4 Hider Special Abilities

Special abilities should be optional and configurable. They can be added after the MVP.

Possible abilities:

* **Freeze Frame**: instantly lock into a believable pose for 5 seconds.
* **Decoy Twitch**: make nearby decoys wobble to confuse Seeker.
* **Color Splash**: briefly recolor nearby decoys, creating cover.
* **Tiny Hop**: small jump to escape being trapped.
* **Heavy Mode**: become harder to push for 4 seconds.
* **Fake Break**: appear cracked/damaged like a shot decoy.
* **Swap Nearby**: swap position with a nearby matching decoy, limited uses.

Abilities should be short, readable, and funny.

---

# 9. Object Design

## 9.1 Object Attributes

Each object has:

* `object_id`
* `shape_id`
* `color_id`
* `size_class`
* `mass`
* `friction`
* `bounce`
* `roll_factor`
* `pickup_allowed`
* `is_hider`
* `owner_player_id`, if hider
* `stealth_weight`
* `visual_noise_level`
* `sound_profile`

## 9.2 Shape Classes

Initial MVP shapes:

1. Cube
2. Sphere
3. Cylinder
4. Cone
5. Capsule
6. Pyramid
7. Star
8. Ring
9. Duck
10. Mug
11. Can
12. Toy block

Later unlockable shapes:

* Banana
* Fish
* Donut
* Robot head
* Tiny chair
* Potion bottle
* Traffic cone
* Gem
* Rubber boot
* Alien egg

## 9.3 Color Palette

Initial colors:

* Red
* Blue
* Green
* Yellow
* Purple
* Orange
* Pink
* White
* Black
* Gray
* Cyan
* Lime

Advanced options:

* Stripes
* Dots
* Metallic
* Glow
* Transparent jelly
* Matte
* Wood toy
* Rubber

Color readability matters. Avoid colors that disappear into passthrough room backgrounds.

---

# 10. Controls

## 10.1 Quest Controls

Support both controllers and hands if possible, but MVP should prioritize controllers.

### Controller Controls

* Trigger: shoot.
* Grip: grab object.
* Thumbstick: optional locomotion disabled by default.
* A/X: scan pulse or interact.
* B/Y: menu.
* Grip release: drop object.
* Throw: natural controller velocity.

Because the Seeker is in a real room, artificial locomotion should be disabled by default.

### Hand Tracking Controls

Optional later:

* Pinch to grab.
* Finger gun or palm tap to shoot.
* Hand ray for menu interaction.

Hand tracking is nice but should not be required for MVP.

## 10.2 Phone Controls

Phone interface should be arcade-simple.

Default layout:

* Left side virtual joystick: move.
* Right side buttons:

  * Freeze
  * Change color
  * Change shape
  * Ability
* Top bar:

  * Timer
  * Seeker danger indicator
  * Cooldowns
  * Alive/found status

Alternate control mode:

* Tap destination to slide toward it.
* Swipe to dash.
* Hold to freeze.

MVP should support virtual joystick first.

---

# 11. Phone Player View

The phone screen should show a stylized top-down room map.

Visible elements:

* Player’s object.
* Nearby decoy objects.
* Walls/play boundary.
* General Seeker position.
* Seeker view cone, if enabled.
* Danger radius.
* Timer.
* Cooldowns.
* Current disguise.
* Status messages.

Do not show perfect information by default.

Recommended visibility rules:

* Hider sees nearby objects clearly.
* Far objects are simplified.
* Seeker position is approximate unless close.
* Other hiders are hidden or shown only as vague teammate pings.
* The exact Seeker aim ray is not shown unless using an easier mode.

This prevents phone players from having too much advantage.

---

# 12. Seeker View

The Quest view should be uncluttered.

Visible elements:

* Passthrough room.
* Virtual props.
* Timer.
* Bullet count.
* Subtle boundary.
* Optional hand/controller tool.
* Hit feedback.
* Current phase text.
* Warning if player nears boundary.

Do not put too much UI in the headset. The fun is looking around the real room.

## 12.1 Blackout Safety

During blackout, the game should not encourage movement.

Display:

* “Stand still. Hiders are hiding.”
* Countdown.
* Soft dark overlay.
* Boundary still faintly visible if needed.

The blackout should be a game effect, not a safety hazard.

---

# 13. Lobby and Local Connection Design

## 13.1 Recommended Networking Model

Use **Quest-as-host authoritative LAN multiplayer**.

The Quest app runs:

* Local game server.
* Authoritative physics.
* Authoritative game state.
* Room/lobby manager.
* Hit detection.
* Scoring.

Phones run:

* Lightweight client.
* Input sender.
* 2D state renderer.
* UI controller.

Phones should never be trusted to decide final position, hits, scoring, or elimination. They only send input requests.

## 13.2 Transport

Recommended MVP transport:

* WebSocket over local TCP.

Reasons:

* Works cross-platform.
* Easier to debug.
* More firewall/router-friendly than raw UDP.
* Good enough for a local party game.
* AI coding agents will handle it more reliably than a complex custom UDP stack.

Possible future transport:

* ENet/UDP for lower-latency movement.
* WebRTC for internet play.
* Relay server if remote play is added.

## 13.3 Discovery

Use three-layer discovery:

1. QR code join.
2. Local network service discovery.
3. Manual IP/room-code fallback.

The QR code should contain:

```json
{
  "game": "hidefall",
  "version": 1,
  "host_ip": "192.168.1.42",
  "port": 29444,
  "room_id": "842913",
  "token": "short-session-token"
}
```

The phone scans the Quest QR code and connects directly.

## 13.4 Room Code

The room code is not a cloud lobby code. It is a local verification code.

Purpose:

* Prevent random local devices from joining.
* Make sure the phone joined the intended Quest.
* Allow manual entry.

## 13.5 Same-Network Requirement

For MVP, all devices must be on the same Wi-Fi network.

If Wi-Fi blocks peer-to-peer traffic, fallback options:

* Quest creates or joins phone hotspot.
* Manual IP entry.
* Later: cloud relay mode.

## 13.6 Lobby State

Lobby should track:

* Host device ID.
* Connected clients.
* Player display names.
* Ready status.
* App version compatibility.
* Ping/latency.
* Selected avatar/color.
* Whether each phone has loaded required assets.
* Whether each player is alive/spectating.

## 13.7 Disconnect Handling

If a phone disconnects during lobby:

* Remove from lobby after timeout.

If a phone disconnects during round:

* Their object becomes an inert decoy after 5 seconds.
* If they reconnect quickly, control returns.
* If they do not reconnect, they count as eliminated or inactive depending on host setting.

If Quest host disconnects:

* Round ends for everyone.
* Phones show “Host disconnected.”

---

# 14. Game Modes

## 14.1 Classic Hidefall

Default mode.

* Objects rain.
* Hiders hide.
* Seeker finds them.
* Limited bullets.
* Hiders can move and morph with cooldowns.

## 14.2 Freeze Mode

Hiders can move only during blackout and during short movement windows.

This is easier for Seeker and good for beginners.

## 14.3 Chaos Mode

More physics, more objects, more movement.

* More decoys.
* Hider abilities enabled.
* Random object rain during seek phase.
* More bullets.
* Shorter rounds.

## 14.4 Kids / Easy Mode

Simplified rules.

* Fewer objects.
* Longer seek time.
* More bullets.
* Hiders have fewer disguise changes.
* Seeker gets scan pulse.

## 14.5 Expert Mode

Harder for Seeker.

* More decoys.
* Fewer bullets.
* Hiders can change shape/color more often.
* No seeker scan.
* Phone players get less danger information.

## 14.6 Bot Practice

No phone required.

Bots hide as objects and occasionally move.

Useful for:

* Quest-only testing.
* Tutorials.
* Automated testing.
* Demo mode.

---

# 15. Configurable Settings

All settings should be stored in a JSON config file and exposed in a host settings menu.

Recommended settings:

```json
{
  "round": {
    "object_rain_seconds": 10,
    "blackout_seconds": 10,
    "seek_seconds": 90,
    "results_seconds": 15
  },
  "objects": {
    "decoy_count": 75,
    "max_decoy_count": 150,
    "spawn_height_meters": 2.5,
    "allow_large_objects": true,
    "allow_rolling_objects": true
  },
  "seeker": {
    "base_bullets": 3,
    "bullets_per_hider": 1,
    "allow_pickup": true,
    "allow_throwing": true,
    "scan_pulse_enabled": false,
    "scan_pulse_count": 1
  },
  "hiders": {
    "shape_change_cooldown": 12,
    "color_change_cooldown": 6,
    "movement_speed": 1.0,
    "dash_enabled": true,
    "abilities_enabled": false,
    "cannot_move_while_held": true
  },
  "network": {
    "max_hiders": 8,
    "allow_late_join": false,
    "transport": "websocket_lan"
  }
}
```

---

# 16. Technical Architecture

## 16.1 Engine

Recommended engine:

* Godot 4.x
* GDScript for most gameplay
* OpenXR for Quest
* Godot OpenXR Vendors Plugin for Meta Quest features
* WebSocket or Godot high-level multiplayer API for LAN play

## 16.2 Project Structure

```text
repo/
  game/
    project.godot

    scenes/
      shared/
      quest/
      mobile/
      lobby/
      test/

    scripts/
      shared/
        game_state/
        networking/
        content/
        physics/
        scoring/
        config/
      quest/
        xr/
        seeker/
        room_setup/
        object_spawner/
      mobile/
        ui/
        controls/
        map_view/
        hider_client/

    content/
      objects/
      colors/
      modes/
      balance/

    tests/
      unit/
      integration/
      multiplayer/
      simulation/

  tools/
    validate_content.py
    build_manifest.py
    run_headless_tests.py

  .github/
    workflows/
      build_quest_apk.yml
      build_android_apk.yml
      build_ios_testflight.yml
      run_tests.yml
```

## 16.3 Shared Game State

The authoritative game state lives on Quest.

Key state:

```json
{
  "phase": "seek",
  "time_remaining": 82.4,
  "players": [],
  "objects": [],
  "shots_remaining": 5,
  "settings": {},
  "scores": {}
}
```

Object state:

```json
{
  "object_id": "obj_102",
  "shape": "cone",
  "color": "red",
  "position": [1.2, 0.0, -0.7],
  "rotation": [0, 45, 0],
  "velocity": [0, 0, 0],
  "is_hider": true,
  "owner_player_id": "p3",
  "held_by_seeker": false,
  "alive": true
}
```

Phones receive simplified snapshots, not full physics detail for every object at high frequency.

## 16.4 Network Update Model

Phones send inputs:

```json
{
  "type": "hider_input",
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

Quest sends state snapshots:

```json
{
  "type": "state_snapshot",
  "server_tick": 1024,
  "phase": "seek",
  "time_remaining": 81.2,
  "hider_state": {},
  "nearby_objects": [],
  "danger": "watched",
  "cooldowns": {}
}
```

Authoritative server tick:

* 20 ticks/sec for gameplay.
* 5–10 snapshots/sec to phones.
* Higher frequency only for the controlled hider and nearby objects.

## 16.5 Physics Authority

Quest owns all physics.

Phones do not simulate authoritative physics. They may interpolate or predict their own movement for responsiveness, but Quest corrections always win.

This avoids cheating and prevents different devices from disagreeing about where objects are.

## 16.6 Room Coordinates

The Quest app defines a local room coordinate system.

Phones receive a 2D projection of that room:

* X/Z world position maps to 2D phone map.
* Y height is mostly ignored for phone gameplay.
* Objects above floor are shown with small icons or shadows.
* Play boundary is shown as a shape.

This keeps the phone UI simple.

---

# 17. Safety and Comfort

Safety is critical because the Quest player is physically moving.

Rules:

* No artificial locomotion by default.
* Game must respect the Quest boundary.
* Important objects should spawn inside a safe inner play area.
* Do not require crawling under furniture.
* Do not require fast movement.
* Do not spawn important objects behind the player’s real obstacles.
* Blackout should instruct the player to stand still.
* If player nears boundary, show warning and pause shooting.
* If headset tracking is lost, pause the round.
* If floor detection fails, require setup again.

The game should be playable standing or slowly walking.

---

# 18. Tutorial

## 18.1 Quest Tutorial

Teach Seeker:

1. Look around the room.
2. Watch objects fall.
3. Pick up object.
4. Drop object.
5. Shoot object.
6. Identify a fake hider.
7. Start real round.

## 18.2 Phone Tutorial

Teach Hider:

1. Join room.
2. Choose shape and color.
3. Move with joystick.
4. Freeze.
5. Change color.
6. Change shape.
7. Avoid Seeker danger indicator.
8. Survive.

Tutorial should be skippable but strongly recommended before first game.

---

# 19. Art Direction

## 19.1 Visual Style

Objects should look like colorful toy props.

Recommended:

* Simple geometry.
* Bright readable colors.
* Soft outlines.
* Slightly exaggerated physics.
* Minimal texture complexity.
* Clean silhouettes.

Avoid:

* Highly realistic clutter.
* Tiny hard-to-see objects.
* Transparent objects in MVP.
* Overly dark colors.
* Sharp/weapon-like props.

## 19.2 Quest View

Quest objects should look anchored in the real room.

Use:

* Soft contact shadows if possible.
* Simple lighting.
* Clear collision shapes.
* Consistent scale.
* Subtle object outlines only when needed.

## 19.3 Phone View

Phone UI should be bold and readable.

Style:

* Arcade map.
* Large buttons.
* Clear cooldown rings.
* Danger color states.
* Object preview cards.
* Fun animations.

---

# 20. Audio

Audio should help reveal suspicious behavior but not make hiding impossible.

Quest audio:

* Objects falling.
* Bounces.
* Rolling.
* Pickup.
* Throw.
* Shot.
* Correct reveal.
* Wrong shot.
* Countdown.
* Timer urgency.

Phone audio:

* Danger pulse.
* Cooldown ready.
* Being picked up warning.
* Shot nearby.
* Eliminated.
* Round win/loss.

Spatial audio on Quest can make the game more fun, but be careful: if hider movement is too loud, hiding becomes impossible.

---

# 21. Accessibility

Options:

* Reduce motion.
* Disable object rain camera shake.
* Increase UI size.
* Colorblind-friendly palette.
* Left-handed phone controls.
* Longer timers.
* More bullets.
* Reduce object count for performance/clarity.
* Seated mode.
* No blackout mode.
* High contrast outlines.

---

# 22. MVP Scope

The first playable version should include only what is needed to validate the core game.

## 22.1 MVP Features

Quest:

* Host lobby.
* QR join display.
* Basic room/floor setup.
* Object rain.
* Physics props.
* Blackout timer.
* Seek timer.
* Pickup/drop.
* Shooting.
* Hit detection.
* Results screen.

Phone:

* Join via QR/manual IP.
* Choose name.
* Choose object shape/color.
* Move hider with joystick.
* Change color.
* Change shape.
* Freeze.
* Show top-down map.
* Show danger state.
* Show alive/eliminated/results.

Networking:

* Quest as local WebSocket host.
* Phone clients connect over same Wi-Fi.
* Reconnect handling.
* Version compatibility check.

Testing:

* Bot hiders.
* Headless simulation tests.
* Local two-client test harness.
* Config validation.
* Build automation.

## 22.2 Explicitly Not MVP

Save for later:

* Online matchmaking.
* Cloud accounts.
* Remote internet play.
* Advanced room mesh occlusion.
* Hand tracking-only controls.
* Complex cosmetics.
* Battle pass/progression.
* Voice chat.
* Store release.
* Procedural furniture interaction.
* Real-time phone camera AR.

---

# 23. Milestones

## Milestone 1: Single-Device Quest Prototype

Goal: prove the Quest MR experience.

Features:

* Passthrough scene.
* Floor-aligned play area.
* Spawn 50 objects.
* Physics settling.
* Pickup/drop.
* Shoot objects.
* One bot hider.

Success criteria:

* Quest player can walk around and shoot a hidden bot object.
* Performance remains comfortable.
* Objects rest on floor believably.

## Milestone 2: Phone Join Prototype

Goal: prove local phone-to-Quest connection.

Features:

* Quest WebSocket host.
* QR code display.
* Phone connects.
* Phone sends movement input.
* One hider object moves in Quest room.

Success criteria:

* Android phone can join and move an object.
* iPhone can join and move an object.
* Reconnect works after app backgrounding.

## Milestone 3: Full Round Loop

Goal: playable round.

Features:

* Lobby.
* Object rain.
* Blackout.
* Hider choice.
* Seek phase.
* Bullets.
* Results.

Success criteria:

* One Quest + two phones can complete three rounds without restarting.

## Milestone 4: Balancing and Game Feel

Goal: make it fun.

Features:

* Better object variety.
* Scoring.
* Suspicion/danger indicators.
* Cooldowns.
* Sound effects.
* UI polish.

Success criteria:

* Hiders feel they can win.
* Seeker feels they can make smart deductions.
* Wrong shots are funny, not frustrating.

## Milestone 5: Automated Builds

Goal: easy deployment.

Features:

* GitHub Actions build Quest APK.
* GitHub Actions build Android APK.
* iOS export path documented.
* Release manifest generated.
* Automated smoke tests run before release.

Success criteria:

* A GitHub Release contains installable Quest and Android APKs.
* TestFlight/Xcode path is ready for iPhone.

---

# 24. Testing Strategy

The game should be designed so AI coding agents can test most systems automatically.

## 24.1 Unit Tests

Test:

* Config parsing.
* Object definitions.
* Color definitions.
* Scoring rules.
* Cooldown logic.
* Phase transitions.
* Player ready state.
* Lobby state.
* Room code validation.
* Network message serialization.
* Hit detection helper functions.
* Hider movement constraints.

## 24.2 Simulation Tests

Run headless tests where possible.

Simulate:

* 1 seeker + 1 hider.
* 1 seeker + 4 hiders.
* Object rain with 20, 75, 150 objects.
* Hider movement during blackout.
* Hider cannot transform while held.
* Correct shot eliminates hider.
* Wrong shot reduces bullets.
* Round ends when timer expires.
* Round ends when all hiders are found.
* Disconnect and reconnect.

## 24.3 Multiplayer Integration Tests

Create local test harness:

* Start Quest-server simulation on desktop.
* Start fake phone clients.
* Send randomized input.
* Verify authoritative state remains valid.
* Verify no invalid positions.
* Verify no crash after 10 simulated rounds.

## 24.4 Device Smoke Tests

Required before each release:

Quest:

* App launches.
* Passthrough scene loads.
* Floor setup works.
* Objects spawn and settle.
* Pickup works.
* Shooting works.
* QR lobby displays.
* Phone can connect.

Android:

* App installs from APK.
* App requests needed permissions.
* QR scan works.
* Manual join works.
* Joystick sends movement.
* App survives screen lock/reopen.

iPhone:

* TestFlight build launches.
* Local network permission appears when needed.
* QR scan works.
* Manual join works.
* App reconnects after backgrounding.

## 24.5 Performance Tests

Quest performance targets:

* Stable frame rate appropriate for Quest comfort.
* 75 decoys default.
* 150 decoys stress test.
* Physics sleeps inactive objects.
* Snapshot sending does not cause frame spikes.

Phone performance targets:

* 60 FPS UI target.
* Smooth joystick.
* Low battery/thermal load.
* Works on older reasonable devices.

## 24.6 Network Tests

Test conditions:

* Same Wi-Fi.
* Phone hotspot.
* Router with client isolation disabled.
* Router with discovery blocked but direct IP works.
* High latency simulation.
* Packet loss simulation.
* Phone disconnect.
* Quest host pause.
* App background/foreground.

## 24.7 Safety Tests

Quest safety tests:

* Boundary warning.
* Blackout pause message.
* Tracking lost pause.
* Floor setup failure.
* Objects do not spawn outside safe zone.
* Important objects do not require unsafe reach.

---

# 25. AI Coding Agent Requirements

The repo should be structured for autonomous AI coding agents.

Rules for agents:

* Keep gameplay logic in shared scripts, not buried in scenes.
* All game settings must be data-driven.
* Add tests for every feature.
* Do not add engine plugins without documenting why.
* Do not break Android/Quest export presets.
* Keep Quest-specific code separate from mobile code.
* Keep network messages versioned.
* Use deterministic seeds in simulation tests.
* Prefer simple explicit systems over clever hidden editor state.
* Every scene should have a documented purpose.
* Every network message should have schema validation.
* Every content file should be validated by tools.

Required docs:

* `README.md`
* `ARCHITECTURE.md`
* `GAME_DESIGN.md`
* `NETWORK_PROTOCOL.md`
* `TESTING.md`
* `BUILD_AND_RELEASE.md`
* `CONTENT_SCHEMA.md`
* `AGENTS.md`

---

# 26. Build and Release Plan

## 26.1 Quest

Output:

* Signed Quest APK.
* Debug APK for testing.
* Release APK attached to GitHub Release.

Install:

* Developer-mode sideload.
* Later App Lab or Meta Store path.

## 26.2 Android

Output:

* Signed Android APK for direct install.
* Later AAB for Play Store.

Install:

* GitHub Release APK.
* User allows install from source.

## 26.3 iPhone

Output:

* Xcode project/export.
* TestFlight build.

Install:

* TestFlight for testers.
* Later App Store if desired.

## 26.4 Release Manifest

Each release should include:

```json
{
  "version": "0.1.0",
  "protocol_version": 1,
  "quest_apk": "hidefall-quest-v0.1.0.apk",
  "android_apk": "hidefall-mobile-android-v0.1.0.apk",
  "ios_build": "testflight",
  "minimum_mobile_protocol": 1,
  "notes": "First playable local multiplayer build"
}
```

The Quest and phone apps should refuse incompatible protocol versions with a clear message.

---

# 27. Risks and Mitigations

## Risk: Quest physics with many objects performs poorly

Mitigation:

* Use simple collision shapes.
* Sleep settled objects.
* Limit object count by room size.
* Use LOD.
* Reduce physics tick rate if needed.
* Cap velocities.
* Pool objects.

## Risk: LAN discovery fails

Mitigation:

* QR code join is primary.
* Manual IP entry exists.
* Discovery is convenience only.
* Clear troubleshooting screen.

## Risk: iOS local network permission confuses users

Mitigation:

* Explain permission before triggering it.
* Show fallback instructions.
* Provide manual join.
* Provide reconnect button.

## Risk: Hiders are too hard to find

Mitigation:

* Add scan pulse.
* Reduce decoys.
* Increase bullets.
* Show subtle movement clues.
* Increase hider cooldowns.
* Add easy mode.

## Risk: Hiders are too easy to find

Mitigation:

* Add more decoys.
* Reduce bullets.
* Shorten seeker time.
* Give hiders better danger UI.
* Allow more disguise changes.
* Add decoy wobble ability.

## Risk: Real rooms are messy or too small

Mitigation:

* Support small-room mode.
* Use safe inner boundary.
* Scale object count to room size.
* Allow seated/tabletop mode later.
* Do not require room mesh for MVP.

## Risk: AI agents create tangled project structure

Mitigation:

* Strong folder conventions.
* Required tests.
* Content schemas.
* Network schemas.
* Small milestones.
* CI checks.
* No feature accepted without test coverage.

---

# 28. Definition of “First Playable”

The first playable build is successful when:

* Quest host starts a lobby.
* At least one Android phone joins.
* At least one iPhone joins through TestFlight or dev install.
* Objects rain into the Quest room.
* Phone players choose shape/color.
* Quest vision blackout occurs.
* Phone players hide.
* Quest player searches.
* Quest player can pick up objects.
* Quest player can shoot objects.
* Correct shot reveals hider.
* Wrong shot consumes bullet.
* Round ends with results.
* Game can rematch without restarting.
* No major crash across three rounds.

---

# 29. Summary

Hidefall is a local mixed-reality hide-and-seek game where the Quest player searches their real room for phone-controlled living props hidden among a pile of colorful physics objects.

The most important design principles are:

1. Quest owns the real room, physics, and authority.
2. Phones are 2D arcade controllers, not AR clients.
3. QR-code local joining should always work even when discovery fails.
4. Hiding should be active but risky.
5. Seeker actions should feel physical and funny.
6. Every setting should be configurable.
7. Testing and automation should be treated as core features, not afterthoughts.

The MVP should focus on making one complete local round work reliably before adding progression, cosmetics, special powers, online play, or advanced room awareness.

[1]: https://docs.godotengine.org/en/stable/tutorials/networking/high_level_multiplayer.html?utm_source=chatgpt.com "High-level multiplayer - Godot Docs"
[2]: https://godotvr.github.io/godot_openxr_vendors/manual/meta/passthrough.html?utm_source=chatgpt.com "Meta Passthrough — Godot OpenXR Vendors plugin ..."
[3]: https://developer.android.com/develop/connectivity/wifi/use-nsd?utm_source=chatgpt.com "Use network service discovery | Connectivity"
