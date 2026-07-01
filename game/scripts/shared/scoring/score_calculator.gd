class_name ScoreCalculator
extends RefCounted


static func seeker_score(stats: Dictionary) -> int:
	var score := 0
	score += int(stats.get("correct_shots", 0)) * 500
	score += int(stats.get("shots_remaining", 0)) * 100
	score -= int(stats.get("wrong_shots", 0)) * 150
	if bool(stats.get("all_hiders_found", false)):
		score += 1000
	score += int(clamp(float(stats.get("time_bonus", 0.0)), 0.0, 500.0))
	return max(score, 0)


static func hider_score(hider: Dictionary, seek_seconds: float) -> int:
	var alive_time := float(hider.get("alive_time", 0.0))
	var score := int(alive_time * 10.0)
	if bool(hider.get("alive", false)):
		score += 1000
	score += int(float(hider.get("freeze_near_seconds", 0.0)) * 5.0)
	score += int(hider.get("close_calls", 0)) * 250
	score += int(hider.get("inspected_survived", 0)) * 300
	score += int(float(hider.get("distance_moved", 0.0)) * 40.0)
	if seek_seconds > 0.0 and alive_time >= seek_seconds:
		score += 200
	return max(score, 0)

