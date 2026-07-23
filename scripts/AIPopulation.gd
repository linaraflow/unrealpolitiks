# =============================================================================
# AIPopulation.gd
# ИИ: рост населения, потери, беженцы (бывший раздел 6 AIManager.gd).
# Обсчёт чанками — см. AIManager.pop_chunks / pop_chunk_index.
#
# Класс не хранит состояния — читает/пишет его через синглтон AIManager.
# =============================================================================
class_name AIPopulation
extends RefCounted

const MAX_REFUGEE_SEARCH_HOPS = 3

static func process_population() -> void:
    var chunk = AIManager.pop_chunks[AIManager.pop_chunk_index]
    AIManager.pop_chunk_index = (AIManager.pop_chunk_index + 1) % AIManager.POP_CHUNKS_COUNT

    var migration: Dictionary = {}

    for p_id_str in chunk:
        var p_id = int(p_id_str)
        var p_data = ProvinceRegistry.province_data[p_id_str]
        var current = int(p_data.get("population", 0))

        if current > 0:
            if CombatManager.active_battles.has(p_id):
                # Коэффициент увеличен, так как провинция обсчитывается раз в 10 дней
                var loss = int(current * 0.05)
                if loss > 0:
                    migration[p_id_str] = migration.get(p_id_str, 0) - loss
                    distribute_refugees(p_id, loss, migration)
            elif ProvinceRegistry.is_occupied(p_id):
                var loss = int(current * 0.003)
                if loss > 0:
                    migration[p_id_str] = migration.get(p_id_str, 0) - loss
                    distribute_refugees(p_id, loss, migration)
            else:
                var growth = int(current * 0.001)
                if growth > 0:
                    migration[p_id_str] = migration.get(p_id_str, 0) + growth

    for p_id_str in migration:
        if ProvinceRegistry.province_data.has(p_id_str):
            var new_pop = int(ProvinceRegistry.province_data[p_id_str].get("population", 0)) + migration[p_id_str]
            ProvinceRegistry.province_data[p_id_str]["population"] = max(0, new_pop)

static func distribute_refugees(from_p_id: int, amount: int, migration_dict: Dictionary) -> void:
    var safe_p_id = find_nearest_safe_province(from_p_id)
    if safe_p_id != -1:
        var safe_key = safe_p_id
        migration_dict[safe_key] = migration_dict.get(safe_key, 0) + amount

static func is_province_safe(p_id: int) -> bool:
    return not CombatManager.active_battles.has(p_id) and not ProvinceRegistry.is_occupied(p_id)

static func find_nearest_safe_province(start_p_id: int) -> int:
    var queue = [start_p_id]
    var visited = { start_p_id: true }
    var hops = 0
    var q_idx = 0

    while q_idx < queue.size() and hops < MAX_REFUGEE_SEARCH_HOPS:
        var level_size = queue.size() - q_idx
        for i in range(level_size):
            var current_id = queue[q_idx]
            q_idx += 1

            if current_id != start_p_id and is_province_safe(current_id):
                return current_id

            for adj_id in ProvinceRegistry.province_adjacency.get(current_id, []):
                var next_id = int(adj_id)
                if not visited.has(next_id):
                    visited[next_id] = true
                    queue.append(next_id)
        hops += 1

    # Если рядом безопасной провинции нет, ищем её рандомом (максимум 15 попыток)
    var all_keys = ProvinceRegistry.province_data.keys()
    if all_keys.is_empty():
        return -1

    for i in range(15):
        var rand_key = all_keys.pick_random()
        var rand_id = int(rand_key)
        if is_province_safe(rand_id):
            return rand_id

    return -1
