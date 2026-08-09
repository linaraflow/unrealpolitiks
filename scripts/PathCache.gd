extends Node

var _cache: Dictionary = {}

func find_path_cached(from_id: int, to_id: int, country: String) -> Array:
    var key: String = "%d:%d:%s" % [from_id, to_id, country]
    if _cache.has(key):
        return _cache[key]
    var path: Array = Pathfinder.find_path(from_id, to_id, country)
    _cache[key] = path
    return path

func find_distance_cached(from_id: int, to_id: int, country: String) -> int:
    var path: Array = find_path_cached(from_id, to_id, country)
    if path.is_empty():
        return -1
    return path.size() - 1

func invalidate_cache() -> void:
    _cache.clear()
