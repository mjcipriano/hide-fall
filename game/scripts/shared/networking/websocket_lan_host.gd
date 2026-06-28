class_name WebSocketLanHost
extends Node

signal client_message(peer_id: int, message: Dictionary)
signal client_connected(peer_id: int)
signal client_disconnected(peer_id: int)

var port := 29444
var tcp_server := TCPServer.new()
var peers: Dictionary = {}
var next_peer_id := 1


func start(p_port: int = 29444) -> Error:
	port = p_port
	var error := tcp_server.listen(port)
	if error != OK:
		return error
	set_process(true)
	return OK


func stop() -> void:
	for peer_id in peers:
		var peer: WebSocketPeer = peers[peer_id]
		peer.close()
	peers.clear()
	tcp_server.stop()
	set_process(false)


func broadcast(message: Dictionary) -> void:
	var text := JSON.stringify(message)
	for peer_id in peers:
		send_to_peer(peer_id, message)


func send_to_peer(peer_id: int, message: Dictionary) -> Error:
	if not peers.has(peer_id):
		return ERR_DOES_NOT_EXIST
	var peer: WebSocketPeer = peers[peer_id]
	if peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return ERR_UNAVAILABLE
	return peer.send_text(JSON.stringify(message))


func _process(_delta: float) -> void:
	while tcp_server.is_connection_available():
		var stream := tcp_server.take_connection()
		var peer := WebSocketPeer.new()
		var error := peer.accept_stream(stream)
		if error == OK:
			var peer_id := next_peer_id
			next_peer_id += 1
			peers[peer_id] = peer
			client_connected.emit(peer_id)
	_poll_peers()


func _poll_peers() -> void:
	var disconnected: Array[int] = []
	for peer_id in peers:
		var peer: WebSocketPeer = peers[peer_id]
		peer.poll()
		match peer.get_ready_state():
			WebSocketPeer.STATE_OPEN:
				while peer.get_available_packet_count() > 0:
					var text := peer.get_packet().get_string_from_utf8()
					var parsed: Variant = JSON.parse_string(text)
					if parsed is Dictionary:
						client_message.emit(peer_id, parsed)
			WebSocketPeer.STATE_CLOSING, WebSocketPeer.STATE_CLOSED:
				disconnected.append(peer_id)
	for peer_id in disconnected:
		peers.erase(peer_id)
		client_disconnected.emit(peer_id)
