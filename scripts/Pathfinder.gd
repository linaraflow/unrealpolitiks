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
                if not settings.province_data.has(n):
                    # Провинция есть в графе смежности, но отсутствует в provinces.json —
                    # рассинхрон данных. Не падаем, просто не пускаем путь через неё.
                    continue
                var owner = settings.province_data[n].get("owner", "")

                if country == "":
                    continue

                # Провинции моря (owner == "sea") и ничья земля (owner == "")
                # свободно проходимы — это не чужая страна, блокировать нечем.
                # Раньше тут сразу шло ProvinceRegistry.countries_data[owner] —
                # для "sea" (и вообще для owner, которого нет в countries_data)
                # это падало с ошибкой, т.к. такого ключа не существует.
                if owner != "" and owner != ProvinceRegistry.SEA_OWNER:
                    if not ProvinceRegistry.countries_data.has(owner):
                        continue  # неизвестный/битый owner — не пускаем, но и не падаем
                    if not ProvinceRegistry.countries_data.has(country):
                        continue  # страна, которой принадлежит армия, уже уничтожена (_eliminate_country) — не пускаем, но и не падаем

                    var owner_data = ProvinceRegistry.countries_data[owner]
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

## Проверяет, что ВСЕ провинции страны имеют путь до столицы
## ТОЛЬКО через свои провинции (owner == country) или через море.
## В отличие от find_path(), тут враги и нейтралы вообще не проходимы —
## это проверка "нормальной", мирной связности территории.
func is_capital_connected(country: String) -> bool:
    if country == "":
        return true

    var c_data = ProvinceRegistry.countries_data.get(country, {})
    var cap_id: int = int(c_data.get("capital", -1))
    if cap_id == -1 or not ProvinceMap.adjacency.has(cap_id):
        # Нет данных о столице — не блокируем мир из-за рассинхрона данных.
        return true

    var own_provinces: Array = AIManager.get_country_provinces(country)
    if own_provinces.is_empty():
        return true

    var visited: Dictionary = {cap_id: true}
    var queue: Array = [cap_id]

    while not queue.is_empty():
        var current: int = queue.pop_front()
        if not ProvinceMap.adjacency.has(current):
            continue
        for neighbor in ProvinceMap.adjacency[current]:
            var n: int = int(neighbor)
            if visited.has(n):
                continue
            if not ProvinceMap.adjacency.has(n):
                continue
            if not settings.province_data.has(n):
                continue

            var owner = settings.province_data[n].get("owner", "")
            # Проходимо только через свои провинции или море — никаких чужих/ничьих.
            if owner != country and owner != ProvinceRegistry.SEA_OWNER:
                continue

            visited[n] = true
            queue.append(n)

    for p_id in own_provinces:
        if not visited.has(p_id):
            return false

    return true
