class_name HidefallMinigames

# Hider inspection minigames.
#
# When the seeker picks up (inspects) a live hider, the hider must pass a short
# minigame on their phone to "hold still". Passing keeps the prop calm; failing
# makes it shake, yelp, and jump out of the seeker's hand.
#
# The minigame RUNS ON THE PHONE (client) so input is instant: it shows the
# instructions for a short intro, then plays, then reports pass/fail to the
# host. The host only picks which minigame, enforces a safety deadline, and
# reacts to the result. This catalog is the single source of truth for labels,
# instructions, difficulty tuning, and per-game parameters, shared by host and
# phone.
#
# HOW TO ADD A NEW MINIGAME (keep it mobile-friendly and quick):
#   1. Add an entry to CATALOG (id -> label, instructions, archetype).
#   2. Add its tuned numbers to params_for() (harder as `difficulty` rises).
#   3. If it needs a brand-new interaction, add an archetype branch in
#      hider_client.gd (_minigame_build / _minigame_tick / input handlers);
#      most games reuse the "tap", "hold", or "drag" archetypes.
#   4. Add a case to any archetype-specific rule handling on the phone.
#   5. Record it in MINIGAMES.md and add/extend a test.
# Difficulty is an integer that grows each time the same hider is re-inspected.

const INTRO_SECONDS := 1.5
const DEADLINE_GRACE := 3.0

# archetype: how the phone renders + collects input.
#   "tap"  - big button(s); rule in params drives the goal
#   "hold" - press-and-hold button; rule drives the goal
#   "drag" - drag a marker along a bar; rule drives the goal
const CATALOG := {
	"mash_meter":    {"label": "Mash!",          "instructions": "TAP FAST to fill the bar!",           "archetype": "tap"},
	"tap_count":     {"label": "Tap Ten",        "instructions": "Tap exactly the target number",       "archetype": "tap"},
	"beat_tap":      {"label": "On The Beat",    "instructions": "Tap when the sweep hits the middle",   "archetype": "tap"},
	"green_light":   {"label": "Green Means Go", "instructions": "Tap only while it's GREEN",            "archetype": "tap"},
	"copy_cat":      {"label": "Copy Cat",       "instructions": "Repeat the arrows: L / R",             "archetype": "tap"},
	"whack":         {"label": "Whack-a-Prop",   "instructions": "Tap the target as it hops",            "archetype": "tap"},
	"perfect_stop":  {"label": "Perfect Stop",   "instructions": "Tap to stop the marker in the zone",   "archetype": "tap"},
	"hold_still":    {"label": "Hold Still",     "instructions": "Press and HOLD until it fills",        "archetype": "hold"},
	"let_go":        {"label": "Let Go Now",     "instructions": "Release when the bar is in the zone",  "archetype": "hold"},
	"twitchy":       {"label": "Twitchy",        "instructions": "Hold - but let go on each FLASH",      "archetype": "hold"},
	"deep_breath":   {"label": "Deep Breath",    "instructions": "Hold on IN, release on OUT",           "archetype": "hold"},
	"keep_center":   {"label": "Keep Centered",  "instructions": "Drag to keep the dot in the zone",     "archetype": "drag"},
	"shadow":        {"label": "Shadow",         "instructions": "Drag to keep the dot on the target",   "archetype": "drag"},
	"hot_zone":      {"label": "Hot Zone",       "instructions": "Keep the dot in the zone as it jumps", "archetype": "drag"},
	"tightrope":     {"label": "Tightrope",      "instructions": "Keep the dot dead centre - careful!",  "archetype": "drag"},
}


static func ids() -> Array:
	return CATALOG.keys()


static func exists(minigame_id: String) -> bool:
	return CATALOG.has(minigame_id)


static func label(minigame_id: String) -> String:
	return String(CATALOG.get(minigame_id, {}).get("label", minigame_id))


static func instructions(minigame_id: String) -> String:
	return String(CATALOG.get(minigame_id, {}).get("instructions", ""))


static func archetype(minigame_id: String) -> String:
	return String(CATALOG.get(minigame_id, {}).get("archetype", "tap"))


static func random_id(rng: RandomNumberGenerator) -> String:
	var keys := CATALOG.keys()
	return String(keys[rng.randi() % keys.size()])


# Per-game tuning, scaled by difficulty (0 = easiest, capped). Returns every
# number the phone needs to run the game plus its label/instructions/archetype.
static func params_for(minigame_id: String, difficulty: int) -> Dictionary:
	var d := clampi(difficulty, 0, 6)
	var base := {
		"minigame": minigame_id,
		"label": label(minigame_id),
		"instructions": instructions(minigame_id),
		"archetype": archetype(minigame_id),
		"intro": INTRO_SECONDS,
		"duration": 4.0,
		"rule": minigame_id,
	}
	match minigame_id:
		"mash_meter":
			base["duration"] = 3.5
			base["target_taps"] = 12 + 3 * d
			base["drain_per_sec"] = 3.5 + 0.6 * float(d)
		"tap_count":
			base["duration"] = 4.5
			base["target_taps"] = 5 + d
		"beat_tap":
			base["duration"] = 5.0
			base["needed"] = 3 + (d / 2)
			base["sweep_speed"] = 0.9 + 0.18 * float(d)
			base["window"] = clampf(0.22 - 0.02 * float(d), 0.08, 0.22)
		"green_light":
			base["duration"] = 5.0
			base["needed"] = 3 + (d / 2)
			base["green_frac"] = clampf(0.55 - 0.05 * float(d), 0.28, 0.55)
			base["cycle"] = clampf(1.1 - 0.08 * float(d), 0.55, 1.1)
		"copy_cat":
			base["duration"] = 6.0
			base["length"] = 3 + d
		"whack":
			base["duration"] = 5.0
			base["needed"] = 4 + d
			base["hop"] = clampf(0.9 - 0.08 * float(d), 0.4, 0.9)
		"perfect_stop":
			base["duration"] = 4.0
			base["speed"] = 0.8 + 0.18 * float(d)
			base["window"] = clampf(0.24 - 0.025 * float(d), 0.08, 0.24)
		"hold_still":
			base["duration"] = 2.2 + 0.35 * float(d)
		"let_go":
			base["duration"] = 5.0
			base["rise"] = 0.5 + 0.09 * float(d)
			base["window"] = clampf(0.22 - 0.022 * float(d), 0.07, 0.22)
		"twitchy":
			base["duration"] = 4.5
			base["flashes"] = 2 + (d / 2)
			base["react"] = clampf(0.7 - 0.06 * float(d), 0.3, 0.7)
		"deep_breath":
			base["duration"] = 6.0
			base["cycles"] = 2 + (d / 3)
			base["period"] = clampf(1.7 - 0.1 * float(d), 1.0, 1.7)
			base["window"] = clampf(0.35 - 0.03 * float(d), 0.15, 0.35)
		"keep_center":
			base["duration"] = 3.0 + 0.6 * float(d)
			base["zone"] = clampf(0.55 - 0.05 * float(d), 0.2, 0.55)
			base["drift"] = 0.55 + 0.12 * float(d)
			base["flip"] = 1.0 + 0.3 * float(d)
			base["fail_at"] = clampf(1.4 - 0.1 * float(d), 0.6, 1.4)
		"shadow":
			base["duration"] = 4.0 + 0.5 * float(d)
			base["zone"] = clampf(0.42 - 0.04 * float(d), 0.18, 0.42)
			base["target_speed"] = 0.5 + 0.12 * float(d)
			base["fail_at"] = clampf(1.5 - 0.12 * float(d), 0.6, 1.5)
		"hot_zone":
			base["duration"] = 4.5 + 0.5 * float(d)
			base["zone"] = clampf(0.4 - 0.035 * float(d), 0.18, 0.4)
			base["jump_every"] = clampf(1.4 - 0.12 * float(d), 0.6, 1.4)
			base["fail_at"] = clampf(1.3 - 0.1 * float(d), 0.6, 1.3)
		"tightrope":
			base["duration"] = 3.5 + 0.5 * float(d)
			base["zone"] = clampf(0.28 - 0.03 * float(d), 0.12, 0.28)
			base["drift"] = 0.75 + 0.14 * float(d)
			base["flip"] = 1.3 + 0.3 * float(d)
			base["fail_at"] = clampf(1.0 - 0.1 * float(d), 0.5, 1.0)
	return base


# The host's safety deadline for the whole inspection (intro + play + grace).
# If the phone never reports a result (idle/cheating/disconnect), the host
# auto-fails the hider at this point so "do nothing" can't stall forever.
static func time_limit(minigame_id: String, difficulty: int) -> float:
	var p := params_for(minigame_id, difficulty)
	return float(p.get("intro", INTRO_SECONDS)) + float(p.get("duration", 4.0)) + DEADLINE_GRACE


# Render-only view the host puts in the snapshot for the phone to start from.
static func snapshot(state: Dictionary) -> Dictionary:
	if state.is_empty():
		return {}
	return {
		"minigame": String(state.get("minigame", "")),
		"difficulty": int(state.get("difficulty", 0)),
		"status": String(state.get("status", "active")),
		"time_left": maxf(0.0, float(state.get("time_limit", 0.0)) - float(state.get("elapsed", 0.0))),
	}
