extends Node

var settings = preload("res://new_resource.tres")

func find_path(start_id: int, goal_id: int, country: String) -> Array:
    if not ProvinceMap.adjacency.has(start_id):
        print("Провинция ", start_id, " не найдена в графе")
        return []
    if not ProvinceMap.adjacency.has(goal_id):
        print("Провинция ", goal_id, " не найдена в графе")
        return []
    if start_id == goal_id:
        return [start_id]

    var visited: Dictionary = {start_id: true}
    var previous: Dictionary = {start_id: -1}
    var queue: Array = [start_id]  # теперь просто ID, не пути

    while not queue.is_empty():
        var current: int = queue.pop_front()
        for neighbor in ProvinceMap.adjacency[current]:
            var n: int = int(neighbor)
            if not ProvinceMap.adjacency.has(n):
                continue
            if visited.has(n):
                continue

            if n != goal_id:
                var owner = settings.province_data[n].get("owner", "")
                var owner_data = ProvinceRegistry.countries_data[owner]
                if country == "":
                    continue
                var province_owner_data = ProvinceRegistry.countries_data[country]
                var check_control = owner in province_owner_data["control"] or country in owner_data["control"]
                # Своя провинция — проходим, враг — проходим, нейтрал — нет
                if owner != country and not ProvinceRegistry.is_at_war(country, owner) and not check_control:
                    continue

            visited[n] = true
            previous[n] = current
            if n == goal_id:
                return _reconstruct_path(previous, start_id, goal_id)
            queue.append(n)

    print("Путь от ", start_id, " до ", goal_id, " не найден")
    return []

func _reconstruct_path(previous: Dictionary, start_id: int, goal_id: int) -> Array:
    var path: Array = []
    var current: int = goal_id
    while current != -1:
        path.append(current)
        current = previous[current]
    path.reverse()
    return path

func find_distance(start_id: int, goal_id: int, country: String) -> int:
    var path: Array = find_path(start_id, goal_id, country)
    if path.is_empty():
        return -1
    return path.size() - 1
