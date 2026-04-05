extends Node

var peer: ENetMultiplayerPeer

func start_server(port) -> void:
	peer = ENetMultiplayerPeer.new()
	peer.create_server(port)
	multiplayer.multiplayer_peer = peer

func start_client(ip, port) -> void:
	peer = ENetMultiplayerPeer.new()
	peer.create_client(ip, port)
	multiplayer.multiplayer_peer = peer

func stop_multiplayer() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
		print("Соединение закрыто, порт освобожден.")

func stop_server() -> void:
	if !multiplayer.is_server(): return
	var peers = multiplayer.get_peers()
	for id in peers:
		multiplayer.multiplayer_peer.disconnect_peer(id)
	multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	
