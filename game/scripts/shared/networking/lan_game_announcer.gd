class_name LanGameAnnouncer
extends Node

# Broadcasts a small UDP beacon so phones on the same Wi-Fi can list this game
# without scanning anything. The beacon includes what a phone needs to join.

const BEACON_GAME := "hidefall"
const BEACON_VERSION := 1

var udp := PacketPeerUDP.new()
var discovery_port := 29445
var interval_seconds := 1.0
var target_address := "255.255.255.255"
var info: Dictionary = {}
var _accumulator := 0.0
var _started := false


func start(p_discovery_port: int = 29445, p_interval_seconds: float = 1.0) -> Error:
	discovery_port = p_discovery_port
	interval_seconds = maxf(0.2, p_interval_seconds)
	udp.set_broadcast_enabled(true)
	var error := udp.set_dest_address(target_address, discovery_port)
	if error != OK:
		return error
	_started = true
	set_process(true)
	return OK


func stop() -> void:
	_started = false
	set_process(false)
	udp.close()


# Live lobby details merged into every beacon (room, port, players, phase...).
func set_info(p_info: Dictionary) -> void:
	info = p_info


static func build_beacon(p_info: Dictionary) -> String:
	var payload := p_info.duplicate(true)
	payload["game"] = BEACON_GAME
	payload["beacon_version"] = BEACON_VERSION
	return JSON.stringify(payload)


func _process(delta: float) -> void:
	if not _started:
		return
	_accumulator += delta
	if _accumulator < interval_seconds:
		return
	_accumulator = 0.0
	udp.put_packet(build_beacon(info).to_utf8_buffer())
