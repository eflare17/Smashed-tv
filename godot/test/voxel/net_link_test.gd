extends SceneTree
## Two copies of the game connected by a voxel transport, passing messages: a small reliable one, a long one (cut into
## pieces and put back), 200 fast ones each way. Run the host first, then the guest:
##   godot --headless -s res://test/voxel/net_link_test.gd -- --role=host --via=rtc --server=ws://127.0.0.1:9000/
##   godot --headless -s res://test/voxel/net_link_test.gd -- --role=guest --via=rtc --server=ws://127.0.0.1:9000/
## (--via=enet: no server.) Prints "LINK ok ..." or "LINK FAIL ...". Owned by the voxel session.

var tr: NetTransport
var role := "host"
var t := 0.0
var got_small := false
var got_big := false
var fast_got := 0
var sent := false
var big := PackedByteArray()
var done_t := -1.0

func _initialize() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	role = String(args.get("role", "host"))
	if String(args.get("via", "rtc")) == "enet":
		tr = VoxelEnetTransport.new()
	else:
		var r := VoxelRtcTransport.new()
		r.server = String(args.get("server", VoxelRtcTransport.DEFAULT_SERVER))
		r.local_only = args.has("local")
		tr = r
	tr.status.connect(func(text, kind): print("LINK %s status: %s (%s)" % [role, text, kind]))
	tr.received.connect(_got)
	seed(7)
	big.resize(100000)
	for i in big.size():
		big[i] = (i * 31 + 7) % 251
	if role == "host":
		tr.host(String(args.get("code", "TEST")))
	else:
		tr.join(String(args.get("code", "TEST")))

func _got(d: PackedByteArray) -> void:
	if d.size() == 5 and d.get_string_from_utf8() == "hello":
		got_small = true
	elif d.size() == big.size():
		got_big = d == big
	elif d.size() == 4:
		fast_got += 1

func _process(dt: float) -> bool:
	t += dt
	tr.poll()
	if tr.is_open() and not sent:
		sent = true
		tr.send("hello".to_utf8_buffer())
		tr.send(big)
	if sent and fast_got < 1000:
		var f := PackedByteArray([1, 2, 3, 4])
		tr.send_fast(f)
	if got_small and got_big and fast_got >= 100 and done_t < 0.0:
		done_t = t
		print("LINK ok %s via %s after %.1f s: small, long (%d bytes) and %d fast messages" % [role, tr.kind(), t, big.size(), fast_got])
	if done_t >= 0.0 and t > done_t + 2.0:
		tr.close()
		return true
	if t > 40.0:
		print("LINK FAIL %s: open %s small %s long %s fast %d" % [role, str(tr.is_open()), str(got_small), str(got_big), fast_got])
		return true
	return false
