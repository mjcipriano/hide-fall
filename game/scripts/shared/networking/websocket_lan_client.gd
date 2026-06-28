class_name WebSocketLanClient
extends Node

signal connected()
signal disconnected()
signal message_received(message: Dictionary)
signal connection_failed()

var peer := WebSocketPeer.new()
var url := ""
var connected_once := false


func connect_to_host(host: String, port: int) -> Error:
	url = "ws://%s:%d" % [host, port]
	return connect_to_url(url)


func connect_to_url(p_url: String) -> Error:
	url = p_url
	connected_once = false
	peer = WebSocketPeer.new()
	var error := peer.connect_to_url(url)
	set_process(error == OK)
	return error


func close() -> void:
	peer.close()
	set_process(false)


func send_message(message: Dictionary) -> Error:
	if peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return ERR_UNAVAILABLE
	return peer.send_text(JSON.stringify(message))


func is_connected_to_host() -> bool:
	return peer.get_ready_state() == WebSocketPeer.STATE_OPEN


func _process(_delta: float) -> void:
	peer.poll()
	match peer.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not connected_once:
				connected_once = true
				connected.emit()
			while peer.get_available_packet_count() > 0:
				var text := peer.get_packet().get_string_from_utf8()
				var parsed: Variant = JSON.parse_string(text)
				if parsed is Dictionary:
					message_received.emit(parsed)
		WebSocketPeer.STATE_CLOSING:
			pass
		WebSocketPeer.STATE_CLOSED:
			set_process(false)
			if connected_once:
				disconnected.emit()
			else:
				connection_failed.emit()

