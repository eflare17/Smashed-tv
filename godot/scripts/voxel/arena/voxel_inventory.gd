class_name VoxelInventory
extends RefCounted
## A row of slots holding stacks of items (VoxelItems): the player's backpack, a chest's or a cabinet's insides. A slot
## is {} (empty) or {"id": item, "n": how many}; a stack never goes past the item's stack size. Owned by the voxel
## session.

signal changed

var slots: Array = []

func _init(size: int = 24) -> void:
	slots.resize(size)
	for i in size:
		slots[i] = {}

func size() -> int:
	return slots.size()

func is_empty_at(i: int) -> bool:
	return (slots[i] as Dictionary).is_empty()

func at(i: int) -> Dictionary:
	return slots[i]

## n of item id put in: onto stacks of it first, then into empty slots. Returns how many didn't fit.
func add(id: String, n: int) -> int:
	if n <= 0 or not VoxelItems.has(id):
		return maxi(n, 0)
	var most := VoxelItems.stack_max(id)
	var left := n
	for s: Dictionary in slots:
		if left == 0:
			break
		if not s.is_empty() and s.id == id and int(s.n) < most:
			var k := mini(left, most - int(s.n))
			s.n = int(s.n) + k
			left -= k
	for i in slots.size():
		if left == 0:
			break
		if (slots[i] as Dictionary).is_empty():
			var k := mini(left, most)
			slots[i] = {"id": id, "n": k}
			left -= k
	if left != n:
		changed.emit()
	return left

## How many of item id would fit.
func room_for(id: String) -> int:
	var most := VoxelItems.stack_max(id)
	var r := 0
	for s: Dictionary in slots:
		if s.is_empty():
			r += most
		elif s.id == id:
			r += most - int(s.n)
	return r

## Up to n of item id taken out (from the last stacks first). Returns how many.
func remove(id: String, n: int) -> int:
	var got := 0
	for i in range(slots.size() - 1, -1, -1):
		if got >= n:
			break
		var s: Dictionary = slots[i]
		if s.is_empty() or s.id != id:
			continue
		var k := mini(n - got, int(s.n))
		s.n = int(s.n) - k
		got += k
		if int(s.n) <= 0:
			slots[i] = {}
	if got > 0:
		changed.emit()
	return got

func count(id: String) -> int:
	var c := 0
	for s: Dictionary in slots:
		if not s.is_empty() and s.id == id:
			c += int(s.n)
	return c

func total() -> int:
	var c := 0
	for s: Dictionary in slots:
		if not s.is_empty():
			c += int(s.n)
	return c

## Up to n out of slot i (n < 0: the whole stack). Returns the stack taken ({} if none).
func take_at(i: int, n: int = -1) -> Dictionary:
	var s: Dictionary = slots[i]
	if s.is_empty():
		return {}
	var k := int(s.n) if n < 0 else mini(n, int(s.n))
	if k <= 0:
		return {}
	var out := {"id": s.id, "n": k}
	s.n = int(s.n) - k
	if int(s.n) <= 0:
		slots[i] = {}
	changed.emit()
	return out

## A stack put down in slot i: onto the same item there (as much as fits), into it if empty, or swapped with a
## different item there. Returns what's left in the hand ({} if it all went in).
func put_at(i: int, stack: Dictionary) -> Dictionary:
	if stack.is_empty():
		return {}
	var s: Dictionary = slots[i]
	if s.is_empty():
		var most := VoxelItems.stack_max(stack.id)
		var k := mini(int(stack.n), most)
		slots[i] = {"id": stack.id, "n": k}
		changed.emit()
		return {} if k == int(stack.n) else {"id": stack.id, "n": int(stack.n) - k}
	if s.id == stack.id:
		var room := VoxelItems.stack_max(s.id) - int(s.n)
		var k2 := mini(room, int(stack.n))
		if k2 <= 0:
			return stack
		s.n = int(s.n) + k2
		changed.emit()
		return {} if k2 == int(stack.n) else {"id": stack.id, "n": int(stack.n) - k2}
	if int(stack.n) > VoxelItems.stack_max(stack.id):
		return stack                  # (can't swap in more than a slot holds)
	slots[i] = {"id": stack.id, "n": int(stack.n)}
	changed.emit()
	return {"id": s.id, "n": int(s.n)}

## The slots as plain data (saving, sending): [[id, n] or [], ...].
func to_data() -> Array:
	var out := []
	for s: Dictionary in slots:
		out.append([] if s.is_empty() else [String(s.id), int(s.n)])
	return out

func from_data(d: Array) -> void:
	for i in slots.size():
		slots[i] = {}
	for i in mini(d.size(), slots.size()):
		var e = d[i]
		if typeof(e) == TYPE_ARRAY and (e as Array).size() == 2 and VoxelItems.has(String(e[0])) and int(e[1]) > 0:
			slots[i] = {"id": String(e[0]), "n": mini(int(e[1]), VoxelItems.stack_max(String(e[0])))}
	changed.emit()
