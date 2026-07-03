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
#   "tap"    - big button(s); rule in params drives the goal
#   "hold"   - press-and-hold button; rule drives the goal
#   "drag"   - drag a marker along a bar; rule drives the goal
#   "choice" - a row of labelled buttons; answer make_round() prompts for a few
#              rounds. Word/quiz games are just a make_round() generator.
const CATALOG := {
	# --- original action games (tap/hold/drag) ---
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
	# --- word & quiz games (choice grid, answer a few rounds) ---
	"odd_one_out":   {"label": "Odd One Out",    "instructions": "Tap the word that doesn't belong",     "archetype": "choice"},
	"category_tap":  {"label": "Category",       "instructions": "Tap the word that fits the category",  "archetype": "choice"},
	"real_word":     {"label": "Real Word",      "instructions": "Tap the REAL word",                    "archetype": "choice"},
	"rhyme_time":    {"label": "Rhyme Time",     "instructions": "Tap the word that rhymes",             "archetype": "choice"},
	"opposite":      {"label": "Opposites",      "instructions": "Tap the opposite word",                "archetype": "choice"},
	"spell_check":   {"label": "Spell Check",    "instructions": "Tap the correctly spelled word",       "archetype": "choice"},
	"unscramble":    {"label": "Unscramble",     "instructions": "Tap the unscrambled word",             "archetype": "choice"},
	"missing_letter":{"label": "Missing Letter", "instructions": "Tap the missing letter",               "archetype": "choice"},
	"first_letter":  {"label": "First Letter",   "instructions": "Tap the word that starts with it",     "archetype": "choice"},
	"count_letters": {"label": "Count Letters",  "instructions": "How many letters?",                    "archetype": "choice"},
	"count_vowels":  {"label": "Count Vowels",   "instructions": "How many vowels?",                     "archetype": "choice"},
	"longer_word":   {"label": "Longer Word",    "instructions": "Tap the longest word",                 "archetype": "choice"},
	"double_letter": {"label": "Double Letter",  "instructions": "Tap the word with a double letter",    "archetype": "choice"},
	"emoji_match":   {"label": "Emoji Match",    "instructions": "Tap the matching emoji",               "archetype": "choice"},
	"stroop":        {"label": "Ink Colour",     "instructions": "Tap the INK colour, not the word!",    "archetype": "choice"},
	"math_add":      {"label": "Quick Add",      "instructions": "Tap the correct sum",                  "archetype": "choice"},
	"math_sub":      {"label": "Quick Subtract", "instructions": "Tap the correct answer",               "archetype": "choice"},
	"true_math":     {"label": "True or False",  "instructions": "Is the sum right?",                    "archetype": "choice"},
	"which_bigger":  {"label": "Biggest",        "instructions": "Tap the biggest number",               "archetype": "choice"},
	"which_smaller": {"label": "Smallest",       "instructions": "Tap the smallest number",              "archetype": "choice"},
	"odd_number":    {"label": "Odd Number",     "instructions": "Tap the odd number out",               "archetype": "choice"},
	"word_recall":   {"label": "Remember",       "instructions": "Remember the word, then tap it",       "archetype": "choice"},
	# --- more action games ---
	"simon_say":     {"label": "Simon Says",     "instructions": "Watch, then repeat the colours",       "archetype": "choice"},
	"bullseye":      {"label": "Bullseye",       "instructions": "Tap when the ring is smallest",        "archetype": "tap"},
	"metronome":     {"label": "Metronome",      "instructions": "Tap on every beat",                    "archetype": "tap"},
	"reflex":        {"label": "Reflex",         "instructions": "Tap the moment it turns green",        "archetype": "tap"},
	"charge_up":     {"label": "Charge Up",      "instructions": "Hold to charge, release in the zone",  "archetype": "hold"},
	"pulse_hold":    {"label": "Pulse Hold",     "instructions": "Hold on GREEN, release on RED",        "archetype": "hold"},
	"trace_wave":    {"label": "Trace",          "instructions": "Drag to follow the wave",              "archetype": "drag"},
	"hot_cold":      {"label": "Hot & Cold",     "instructions": "Drag to find the hidden spot",         "archetype": "drag"},
}


# Content banks for the word/quiz games (kept small but real).
const COMMON_WORDS := ["CAKE", "DUCK", "STAR", "FROG", "BOAT", "TREE", "MOON", "FISH", "BIRD", "LAMP", "BALL", "DOOR", "RING", "GOLD", "KING", "MILK", "RAIN", "SNOW", "LEAF", "NEST", "HAND", "BOOK", "DESK", "CORN", "LION", "BEAR", "WOLF", "NOSE", "CAVE", "DRUM"]
const MIXED_WORDS := ["CAT", "STAR", "APPLE", "SUN", "TIGER", "EGG", "HOUSE", "BEE", "PLANET", "OWL", "JUNGLE", "ANT", "ROCKET", "SKY", "BANANA", "FOX", "MOON", "UMBRELLA"]
const DOUBLE_WORDS := ["BALL", "EGG", "BELL", "MOON", "BOOK", "FEET", "TREE", "KISS", "PUFF", "GRASS", "JELLY", "PIZZA", "HELLO", "YELLOW"]
const WORD_CATEGORIES := {
	"ANIMAL": ["DOG", "CAT", "COW", "PIG", "FOX", "OWL", "BAT", "HEN", "LION", "BEAR"],
	"FOOD": ["CAKE", "RICE", "MILK", "SOUP", "PEAR", "PLUM", "CORN", "BREAD", "EGG"],
	"COLOR": ["RED", "BLUE", "GREEN", "PINK", "GOLD", "GRAY", "CYAN", "TAN"],
	"BODY": ["ARM", "LEG", "EAR", "EYE", "TOE", "HIP", "JAW", "RIB"],
	"HOUSE": ["DOOR", "ROOF", "WALL", "LAMP", "SINK", "SOFA", "BED"],
}
const RHYME_GROUPS := [
	["CAT", "HAT", "BAT", "MAT", "RAT"],
	["DOG", "LOG", "FOG", "HOG", "JOG"],
	["CAKE", "LAKE", "RAKE", "BAKE", "WAKE"],
	["STAR", "CAR", "JAR", "BAR", "FAR"],
	["TREE", "BEE", "SEA", "KEY", "PEA"],
	["LIGHT", "NIGHT", "KITE", "BITE", "WHITE"],
]
const OPPOSITES := [
	["HOT", "COLD"], ["UP", "DOWN"], ["BIG", "SMALL"], ["FAST", "SLOW"],
	["DAY", "NIGHT"], ["OPEN", "SHUT"], ["HARD", "SOFT"], ["HIGH", "LOW"],
	["WET", "DRY"], ["OLD", "NEW"], ["GOOD", "BAD"], ["LOUD", "QUIET"],
]
const EMOJI_WORDS := {"DOG": "🐶", "CAT": "🐱", "STAR": "⭐", "FISH": "🐟", "TREE": "🌳", "SUN": "☀", "CAR": "🚗", "BALL": "⚽", "CAKE": "🍰", "DUCK": "🦆", "BEE": "🐝", "MOON": "🌙"}
const COLOR_NAMES := ["RED", "BLUE", "GREEN", "YELLOW", "PURPLE", "ORANGE"]


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
	# Choice (word/quiz) games share a longer, multi-round shape by default.
	if archetype(minigame_id) == "choice":
		base["duration"] = 6.5 + 0.6 * float(d)
		base["rounds_needed"] = 2 + (d + 1) / 2
		base["options"] = 4
		base["show"] = 0.0
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
		# --- choice-game per-id tweaks ---
		"word_recall":
			base["show"] = clampf(1.6 - 0.12 * float(d), 0.7, 1.6)
			base["rounds_needed"] = 1
		"simon_say":
			base["sequence_len"] = 2 + (d + 1) / 2
			base["show"] = 0.7
			base["rounds_needed"] = 1
		# --- new action games ---
		"bullseye":
			base["duration"] = 4.5
			base["needed"] = 1 + d / 3
			base["speed"] = 0.8 + 0.16 * float(d)
			base["window"] = clampf(0.18 - 0.02 * float(d), 0.06, 0.18)
		"metronome":
			base["duration"] = 5.5
			base["beats"] = 4 + d
			base["period"] = clampf(0.75 - 0.04 * float(d), 0.4, 0.75)
			base["window"] = clampf(0.2 - 0.02 * float(d), 0.09, 0.2)
		"reflex":
			base["duration"] = 5.0
			base["needed"] = 2 + d / 2
			base["min_wait"] = 0.6
			base["max_wait"] = clampf(2.0 - 0.12 * float(d), 1.0, 2.0)
		"charge_up":
			base["duration"] = 5.0
			base["rise"] = 0.45 + 0.09 * float(d)
			base["target"] = 0.75
			base["window"] = clampf(0.16 - 0.016 * float(d), 0.06, 0.16)
		"pulse_hold":
			base["duration"] = 5.5
			base["period"] = clampf(1.5 - 0.1 * float(d), 0.9, 1.5)
			base["cycles"] = 2 + d / 3
			base["green_frac"] = 0.5
		"trace_wave":
			base["duration"] = 4.5 + 0.5 * float(d)
			base["zone"] = clampf(0.4 - 0.04 * float(d), 0.16, 0.4)
			base["target_speed"] = 0.6 + 0.14 * float(d)
			base["fail_at"] = clampf(1.4 - 0.12 * float(d), 0.6, 1.4)
		"hot_cold":
			base["duration"] = 6.0
			base["tolerance"] = clampf(0.12 - 0.012 * float(d), 0.05, 0.12)
			base["hold_time"] = 0.5
	return base


# Generates one question for a "choice" (word/quiz) game. Returns
# {prompt, options: [String], correct: int}; some add prompt_color / memorize /
# sequence. The phone calls this each round. Not needed for action archetypes.
static func make_round(minigame_id: String, difficulty: int, rng: RandomNumberGenerator) -> Dictionary:
	var d := clampi(difficulty, 0, 6)
	match minigame_id:
		"odd_one_out":
			var cats: Array = WORD_CATEGORIES.keys()
			var a := String(_pick(cats, rng))
			var b := a
			while b == a:
				b = String(_pick(cats, rng))
			var same := _sample(WORD_CATEGORIES[a], 3, rng)
			var odd := String(_pick(WORD_CATEGORIES[b], rng))
			while same.has(odd):
				odd = String(_pick(WORD_CATEGORIES[b], rng))
			return _round("ODD ONE OUT", odd, same, rng)
		"category_tap":
			var cats: Array = WORD_CATEGORIES.keys()
			var a := String(_pick(cats, rng))
			var correct := String(_pick(WORD_CATEGORIES[a], rng))
			var others: Array = []
			for c in cats:
				if c != a:
					others.append_array(WORD_CATEGORIES[c])
			return _round("TAP A " + a, correct, _sample_excluding(others, correct, 3, rng), rng)
		"real_word":
			var w := String(_pick(COMMON_WORDS, rng))
			var dist: Array = []
			for pw in _rng_shuffle(COMMON_WORDS, rng):
				if dist.size() >= 3:
					break
				if String(pw) == w:
					continue
				var s := _scramble(String(pw), rng)
				if not _is_word(s) and not dist.has(s):
					dist.append(s)
			return _round("TAP THE REAL WORD", w, dist, rng)
		"rhyme_time":
			var g: Array = RHYME_GROUPS[rng.randi() % RHYME_GROUPS.size()]
			var pair := _sample(g, 2, rng)
			var dist: Array = []
			for other in _rng_shuffle(RHYME_GROUPS, rng):
				if dist.size() >= 3:
					break
				if other == g:
					continue
				dist.append(String(_pick(other, rng)))
			return _round("RHYMES WITH " + String(pair[0]), String(pair[1]), dist, rng)
		"opposite":
			var p: Array = OPPOSITES[rng.randi() % OPPOSITES.size()]
			var flip := rng.randi() % 2
			var dist: Array = []
			for other in _rng_shuffle(OPPOSITES, rng):
				if dist.size() >= 3:
					break
				if other == p:
					continue
				dist.append(String(other[rng.randi() % 2]))
			return _round("OPPOSITE OF " + String(p[flip]), String(p[1 - flip]), dist, rng)
		"spell_check":
			var w := String(_pick(COMMON_WORDS, rng))
			var dist: Array = []
			var guard := 0
			while dist.size() < 3 and guard < 24:
				var m := _misspell(w, rng)
				if m != w and not _is_word(m) and not dist.has(m):
					dist.append(m)
				guard += 1
			return _round("REAL SPELLING?", w, dist, rng)
		"unscramble":
			var w := String(_pick(COMMON_WORDS, rng))
			return _round(_scramble(w, rng), w, _sample_excluding(COMMON_WORDS, w, 3, rng), rng)
		"missing_letter":
			var w := String(_pick(COMMON_WORDS, rng))
			var pos := rng.randi() % w.length()
			var missing := w.substr(pos, 1)
			var shown := w.substr(0, pos) + "_" + w.substr(pos + 1)
			var alphabet := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
			var dist: Array = []
			while dist.size() < 3:
				var c := alphabet.substr(rng.randi() % 26, 1)
				if c != missing and not dist.has(c):
					dist.append(c)
			return _round(shown, missing, dist, rng)
		"first_letter":
			var w := String(_pick(COMMON_WORDS, rng))
			var letter := w.substr(0, 1)
			var dist: Array = []
			for pw in _rng_shuffle(COMMON_WORDS, rng):
				if dist.size() >= 3:
					break
				if not String(pw).begins_with(letter) and not dist.has(pw):
					dist.append(pw)
			return _round("STARTS WITH " + letter, w, dist, rng)
		"count_letters":
			var w := String(_pick(COMMON_WORDS, rng))
			return _round("LETTERS IN " + w, w.length(), _number_distractors(w.length(), 3, rng), rng)
		"count_vowels":
			var w := String(_pick(COMMON_WORDS, rng))
			var vc := _count_vowels(w)
			return _round("VOWELS IN " + w, vc, _number_distractors(vc, 3, rng), rng)
		"longer_word":
			var ws := _sample(MIXED_WORDS, 4, rng)
			var guard := 0
			while _has_length_tie_at_max(ws) and guard < 12:
				ws = _sample(MIXED_WORDS, 4, rng)
				guard += 1
			var longest := String(ws[0])
			for w in ws:
				if String(w).length() > longest.length():
					longest = String(w)
			var dist: Array = []
			for w in ws:
				if String(w) != longest:
					dist.append(String(w))
			return _round("LONGEST WORD?", longest, dist, rng)
		"double_letter":
			var w := String(_pick(DOUBLE_WORDS, rng))
			var dist: Array = []
			for pw in _rng_shuffle(COMMON_WORDS, rng):
				if dist.size() >= 3:
					break
				if not _has_double(String(pw)) and not dist.has(pw):
					dist.append(pw)
			return _round("DOUBLE LETTER?", w, dist, rng)
		"emoji_match":
			var keys: Array = EMOJI_WORDS.keys()
			var w := String(_pick(keys, rng))
			var correct := String(EMOJI_WORDS[w])
			var dist: Array = []
			for e in _rng_shuffle(EMOJI_WORDS.values(), rng):
				if dist.size() >= 3:
					break
				if String(e) != correct and not dist.has(String(e)):
					dist.append(String(e))
			return _round(w, correct, dist, rng)
		"stroop":
			var ink := String(_pick(COLOR_NAMES, rng))
			var text := String(_pick(COLOR_NAMES, rng))
			while text == ink:
				text = String(_pick(COLOR_NAMES, rng))
			return _round(text, ink, _sample_excluding(COLOR_NAMES, ink, 3, rng), rng, {"prompt_color": ink})
		"math_add":
			var lim := 5 + 3 * d
			var a := 1 + rng.randi() % lim
			var b := 1 + rng.randi() % lim
			return _round("%d + %d = ?" % [a, b], a + b, _number_distractors(a + b, 3, rng), rng)
		"math_sub":
			var lim2 := 5 + 3 * d
			var x := 1 + rng.randi() % lim2
			var y := 1 + rng.randi() % lim2
			var hi := maxi(x, y)
			var lo := mini(x, y)
			return _round("%d - %d = ?" % [hi, lo], hi - lo, _number_distractors(hi - lo, 3, rng), rng)
		"true_math":
			var a2 := 1 + rng.randi() % (5 + 2 * d)
			var b2 := 1 + rng.randi() % (5 + 2 * d)
			var real := a2 + b2
			var shown := real
			if rng.randi() % 2 == 0:
				var off := 1 + rng.randi() % 3
				shown = real + (off if rng.randi() % 2 == 0 else -off)
				if shown < 0:
					shown = real + off
			var correct := "TRUE" if shown == real else "FALSE"
			var wrong := "FALSE" if correct == "TRUE" else "TRUE"
			return _round("%d + %d = %d" % [a2, b2, shown], correct, [wrong], rng)
		"which_bigger", "which_smaller":
			var nums: Array = []
			while nums.size() < 4:
				var v := 1 + rng.randi() % (20 + 10 * d)
				if not nums.has(v):
					nums.append(v)
			var target = nums.max() if minigame_id == "which_bigger" else nums.min()
			var dist: Array = []
			for v in nums:
				if v != target:
					dist.append(v)
			return _round("BIGGEST?" if minigame_id == "which_bigger" else "SMALLEST?", target, dist, rng)
		"odd_number":
			var target_odd := rng.randi() % 2 == 0
			var majority: Array = []
			while majority.size() < 3:
				var v := 1 + rng.randi() % (30 + 5 * d)
				if (v % 2 == 1) != target_odd and not majority.has(v):
					majority.append(v)
			var target := 1 + rng.randi() % (30 + 5 * d)
			while (target % 2 == 1) != target_odd or majority.has(target):
				target = 1 + rng.randi() % (30 + 5 * d)
			return _round("TAP THE ODD ONE OUT", target, majority, rng)
		"word_recall":
			var w := String(_pick(COMMON_WORDS, rng))
			return _round(w, w, _sample_excluding(COMMON_WORDS, w, 3, rng), rng, {"memorize": w})
		"simon_say":
			var colors := ["RED", "BLUE", "GREEN", "YELLOW"]
			var seq: Array = []
			var seq_len := 2 + (d + 1) / 2
			for _i in seq_len:
				seq.append(rng.randi() % colors.size())
			return {"prompt": "WATCH", "options": colors, "correct": -1, "sequence": seq}
	return {"prompt": "", "options": ["OK"], "correct": 0}


# --- choice-game content helpers ---
static func _pick(arr: Array, rng: RandomNumberGenerator):
	return arr[rng.randi() % arr.size()]


static func _rng_shuffle(arr: Array, rng: RandomNumberGenerator) -> Array:
	var a := arr.duplicate()
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var tmp = a[i]
		a[i] = a[j]
		a[j] = tmp
	return a


static func _sample(arr: Array, n: int, rng: RandomNumberGenerator) -> Array:
	return _rng_shuffle(arr, rng).slice(0, n)


static func _sample_excluding(arr: Array, exclude, n: int, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	for v in _rng_shuffle(arr, rng):
		if out.size() >= n:
			break
		if str(v) != str(exclude) and not out.has(v):
			out.append(v)
	return out


# Builds the option list: the correct answer plus distractors, stringified,
# shuffled, with the resulting correct index. Extra keys pass through.
static func _round(prompt: String, correct, distractors: Array, rng: RandomNumberGenerator, extra: Dictionary = {}) -> Dictionary:
	var cs := str(correct)
	var opts: Array = [cs]
	for dd in distractors:
		var s := str(dd)
		if not opts.has(s):
			opts.append(s)
	opts = _rng_shuffle(opts, rng)
	var result := {"prompt": prompt, "options": opts, "correct": opts.find(cs)}
	for k in extra:
		result[k] = extra[k]
	return result


static func _scramble(w: String, rng: RandomNumberGenerator) -> String:
	var chars: Array = []
	for i in w.length():
		chars.append(w[i])
	var out := w
	var tries := 0
	while out == w and tries < 8:
		chars = _rng_shuffle(chars, rng)
		out = "".join(chars)
		tries += 1
	return out


static func _misspell(w: String, rng: RandomNumberGenerator) -> String:
	var chars: Array = []
	for i in w.length():
		chars.append(w[i])
	var mode := rng.randi() % 3
	if mode == 0 and chars.size() >= 2:
		var i := rng.randi() % (chars.size() - 1)
		var t = chars[i]
		chars[i] = chars[i + 1]
		chars[i + 1] = t
	elif mode == 1:
		var i2 := rng.randi() % chars.size()
		chars.insert(i2, chars[i2])
	elif chars.size() > 3:
		chars.remove_at(rng.randi() % chars.size())
	var out := "".join(chars)
	if out == w:
		out = w + w.substr(w.length() - 1, 1)
	return out


static func _number_distractors(correct: int, n: int, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	var guard := 0
	while out.size() < n and guard < 60:
		var delta := (rng.randi() % 7) - 3
		if delta == 0:
			delta = 1
		var v := correct + delta
		if v >= 0 and v != correct and not out.has(v):
			out.append(v)
		guard += 1
	return out


static func _count_vowels(w: String) -> int:
	var count := 0
	for i in w.length():
		if "AEIOU".contains(w[i]):
			count += 1
	return count


static func _has_double(w: String) -> bool:
	for i in range(w.length() - 1):
		if w[i] == w[i + 1]:
			return true
	return false


static func _has_length_tie_at_max(words: Array) -> bool:
	var max_len := 0
	for w in words:
		max_len = maxi(max_len, String(w).length())
	var count := 0
	for w in words:
		if String(w).length() == max_len:
			count += 1
	return count > 1


static func _is_word(s: String) -> bool:
	if COMMON_WORDS.has(s) or MIXED_WORDS.has(s) or DOUBLE_WORDS.has(s):
		return true
	for cat in WORD_CATEGORIES.values():
		if cat.has(s):
			return true
	return false


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
