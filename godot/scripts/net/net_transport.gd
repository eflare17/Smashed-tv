class_name NetTransport
extends RefCounted
## The small interface every connection speaks (milestone 4), so the web's PeerJS and a native one swap freely.
## Owned by the Online task.
##
## One host, one guest. host(code) opens a room under that code, join(code) calls it. Messages are bytes
## (Net packs them); everything is reliable and in order (the HTML game's PeerJS channel is reliable too).
## Call poll() every frame: it fires the signals.

## The room is open and waiting (host), or the broker answered (guest).
signal opened(code: String)
## The other player is connected: messages can go both ways.
signal connected
## A message from the other player.
signal received(data: PackedByteArray)
## The other player went (or the connection failed after connecting).
signal disconnected
## A line for the menu ("room ABCD — waiting for player 2"); kind is "", "live" or "bad" like the HTML's setStatus.
signal status(text: String, kind: String)

func host(_code: String) -> void:
	pass

func join(_code: String) -> void:
	pass

func send(_data: PackedByteArray) -> void:
	pass

func poll() -> void:
	pass

func close() -> void:
	pass

func is_open() -> bool:
	return false

## What kind it is, for the menu ("PeerJS", "LAN").
func kind() -> String:
	return ""
