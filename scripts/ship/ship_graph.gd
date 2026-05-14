class_name ShipGraph
extends RefCounted

# Room connection graph. Dijkstra pathfinding over weighted edges.
# Queries respect door lock state and maintenance-tube access restrictions.

class _Edge:
	var to_room: String
	var weight: float
	var door_id: String
	var maintenance_only: bool

	func _init(to: String, w: float, door: String, maint: bool) -> void:
		to_room = to
		weight = w
		door_id = door
		maintenance_only = maint


var _edges: Dictionary = {}  # room_id -> Array[_Edge]


func add_room(room_id: String) -> void:
	if room_id not in _edges:
		_edges[room_id] = []


func connect_rooms(room_a: String, room_b: String, weight: float = 1.0,
		door_id: String = "", maintenance_only: bool = false) -> void:
	add_room(room_a)
	add_room(room_b)
	_edges[room_a].append(_Edge.new(room_b, weight, door_id, maintenance_only))
	_edges[room_b].append(_Edge.new(room_a, weight, door_id, maintenance_only))


func find_path(from_room: String, to_room: String,
		allow_maintenance: bool = false,
		blocked_doors: Array[String] = []) -> Array[String]:
	if from_room == to_room:
		return [from_room]
	if from_room not in _edges or to_room not in _edges:
		return []

	var dist: Dictionary = {}
	var prev: Dictionary = {}
	var unvisited: Dictionary = {}

	for room_id in _edges:
		dist[room_id] = INF
		prev[room_id] = ""
		unvisited[room_id] = true
	dist[from_room] = 0.0

	while not unvisited.is_empty():
		var current: String = _min_dist_room(dist, unvisited)
		if current == "" or dist[current] == INF:
			break
		if current == to_room:
			break
		unvisited.erase(current)
		for edge in _edges.get(current, []):
			if not unvisited.has(edge.to_room):
				continue
			if edge.maintenance_only and not allow_maintenance:
				continue
			if edge.door_id != "" and edge.door_id in blocked_doors:
				continue
			var alt: float = dist[current] + edge.weight
			if alt < dist[edge.to_room]:
				dist[edge.to_room] = alt
				prev[edge.to_room] = current

	if dist.get(to_room, INF) == INF:
		return []

	var path: Array[String] = []
	var node: String = to_room
	while node != "":
		path.push_front(node)
		node = prev[node]
	return path


func get_neighbours(room_id: String, allow_maintenance: bool = false,
		blocked_doors: Array[String] = []) -> Array[String]:
	var result: Array[String] = []
	for edge in _edges.get(room_id, []):
		if edge.maintenance_only and not allow_maintenance:
			continue
		if edge.door_id != "" and edge.door_id in blocked_doors:
			continue
		result.append(edge.to_room)
	return result


func _min_dist_room(dist: Dictionary, unvisited: Dictionary) -> String:
	var min_id: String = ""
	var min_val: float = INF
	for room_id in unvisited:
		if dist[room_id] < min_val:
			min_val = dist[room_id]
			min_id = room_id
	return min_id
