class_name HidefallMinigames

# Hider inspection minigames.
#
# When the seeker picks up (inspects) a live hider, the hider must pass a short
# minigame on their phone to "hold still". Passing keeps the prop calm; failing
# makes it shake, yelp, and jump out of the seeker's hand (see the simulation's
# _fail_inspection). All minigame rules are evaluated here so the logic is
# shared and authoritative on the host — the phone only renders the state and
# sends a normalized input.
#
# HOW TO ADD A NEW MINIGAME (keep it mobile-friendly and quick, <6s):
#   1. Add an entry to CATALOG below (id -> label/hint/input-kind).
#   2. Add a `match` case to make_state() (its tunable start state) and to
#      step() (its per-tick rule that sets status to "success" or "fail").
#   3. Add a renderer + input case in hider_client.gd (_draw_minigame /
#      _minigame_input_value), keyed by the same id.
#   4. Record it as implemented in MINIGAMES.md.
# Difficulty is an integer that grows each time the same hider is re-inspected;
# make_state() should get meaningfully harder as it rises.

const DEFAULT_MINIGAME := "steady_balance"

const CATALOG := {
	"steady_balance": {
		"label": "Steady Hands",
		"hint": "Keep the marker inside the safe zone until the bar fills",
		"input": "slider",
	},
}


static func exists(minigame_id: String) -> bool:
	return CATALOG.has(minigame_id)


static func ids() -> Array:
	return CATALOG.keys()


# Builds the starting state for a minigame at a given difficulty (0 = easiest).
static func make_state(minigame_id: String, difficulty: int) -> Dictionary:
	var d := clampi(difficulty, 0, 6)
	match minigame_id:
		"steady_balance":
			return {
				"minigame": "steady_balance",
				"difficulty": d,
				"ball": 0.0,
				"drift_dir": 1.0,
				"zone": clampf(0.55 - 0.05 * float(d), 0.2, 0.55),
				"duration": 3.0 + 0.6 * float(d),
				"drift_speed": 0.6 + 0.12 * float(d),
				"control_speed": 1.6,
				"flip_freq": 1.0 + 0.3 * float(d),
				"fail_at": clampf(1.4 - 0.1 * float(d), 0.6, 1.4),
				"elapsed": 0.0,
				"out_time": 0.0,
				"push": 0.0,
				"status": "pending",
			}
	# Unknown id: pass immediately so a bad config never traps a hider forever.
	return {
		"minigame": minigame_id,
		"difficulty": d,
		"ball": 0.0,
		"zone": 1.0,
		"duration": 0.0,
		"elapsed": 0.0,
		"out_time": 0.0,
		"push": 0.0,
		"status": "success",
	}


# Advances one minigame by delta seconds using the hider's latest push input
# (-1..1). Returns the updated state; status flips to "success" or "fail" when
# the round resolves. Deterministic (no RNG) so host and tests agree.
static func step(state: Dictionary, push: float, delta: float) -> Dictionary:
	if String(state.get("status", "pending")) != "pending":
		return state
	match String(state.get("minigame", "")):
		"steady_balance":
			var clamped_push := clampf(push, -1.0, 1.0)
			state["push"] = clamped_push
			var elapsed := float(state["elapsed"]) + delta
			state["elapsed"] = elapsed
			# Drift shoves the marker toward an edge and flips direction on a
			# timer, so the player has to keep tracking it, not just hold one way.
			var drift_dir := 1.0 if sin(elapsed * float(state["flip_freq"])) >= 0.0 else -1.0
			state["drift_dir"] = drift_dir
			var ball := float(state["ball"]) + (drift_dir * float(state["drift_speed"]) + clamped_push * float(state["control_speed"])) * delta
			ball = clampf(ball, -1.0, 1.0)
			state["ball"] = ball
			if absf(ball) > float(state["zone"]):
				state["out_time"] = float(state["out_time"]) + delta
			else:
				state["out_time"] = maxf(0.0, float(state["out_time"]) - delta)
			if float(state["out_time"]) >= float(state["fail_at"]):
				state["status"] = "fail"
			elif elapsed >= float(state["duration"]):
				state["status"] = "success"
	return state


# The compact, render-only view sent to the phone in the state snapshot.
static func snapshot(state: Dictionary) -> Dictionary:
	if state.is_empty():
		return {}
	return {
		"minigame": String(state.get("minigame", "")),
		"status": String(state.get("status", "pending")),
		"ball": float(state.get("ball", 0.0)),
		"zone": float(state.get("zone", 1.0)),
		"difficulty": int(state.get("difficulty", 0)),
		"time_left": maxf(0.0, float(state.get("duration", 0.0)) - float(state.get("elapsed", 0.0))),
	}
