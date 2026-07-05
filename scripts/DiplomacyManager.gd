extends Node

var settings = preload("res://new_resource.tres")

signal sanctions_imposed(attacker: String, target: String)
signal sanctions_removed(attacker: String, target: String)

const IDEOLOGIES = {
    "liberalism": {"tax": 1.0, "war": 0.5, "peace": 1.5, "mil": 0.8, "eco": 1.2},
    "parliamentary_republic": {"tax": 1.1, "war": 0.6, "peace": 1.3, "mil": 0.9, "eco": 1.1},
    "monarchy": {"tax": 1.2, "war": 1.2, "peace": 0.8, "mil": 1.1, "eco": 0.9},
    "neo_nazism": {"tax": 1.3, "war": 2.0, "peace": 0.2, "mil": 1.5, "eco": 0.5},
    "fascism": {"tax": 1.4, "war": 1.8, "peace": 0.3, "mil": 1.4, "eco": 0.6},
    "socialism": {"tax": 0.9, "war": 0.7, "peace": 1.2, "mil": 1.0, "eco": 1.3},
    "communism": {"tax": 0.8, "war": 1.5, "peace": 0.5, "mil": 1.3, "eco": 1.1},
    "dictatorship": {"tax": 1.5, "war": 1.6, "peace": 0.4, "mil": 1.3, "eco": 0.7},
    "islamic_republic": {"tax": 1.1, "war": 1.1, "peace": 0.9, "mil": 1.2, "eco": 0.8},
    "military_junta": {"tax": 1.2, "war": 1.9, "peace": 0.3, "mil": 1.6, "eco": 0.4},
    "oligarchy": {"tax": 1.6, "war": 0.8, "peace": 1.1, "mil": 0.7, "eco": 1.5}
}

# Хранит активные процессы: "sender_target" -> {"sender": String, "target": String, "days_left": int, "type": String}
var active_processes: Dictionary = {}

func _ready() -> void:
    GameClock.on_day_passed.connect(_on_day_passed_diplomacy)

func _on_day_passed_diplomacy(_date: Dictionary) -> void:
    var completed: Array = []
    for key in active_processes.keys():
        active_processes[key]["days_left"] -= 1
        if active_processes[key]["days_left"] <= 0:
            completed.append(key)
            
    for key in completed:
        var proc = active_processes[key]
        if proc["type"] == "improve":
            change_relation(proc["sender"], proc["target"], 15.0)
        elif proc["type"] == "worsen":
            change_relation(proc["sender"], proc["target"], -15.0)
        active_processes.erase(key)

func start_relations_process(sender: String, target: String, type: String) -> bool:
    var key = sender + "_" + target
    if active_processes.has(key):
        return false
    active_processes[key] = {
        "sender": sender,
        "target": target,
        "days_left": 30,
        "type": type
    }
    return true

func get_process_progress(sender: String, target: String) -> float:
    var key = sender + "_" + target
    if not active_processes.has(key):
        return 0.0
    return (30.0 - active_processes[key]["days_left"]) / 30.0

func get_relation(country_a: String, country_b: String) -> float:
    var c_data = ProvinceRegistry.countries_data
    if not c_data.has(country_a) or not c_data[country_a].has("relations"): 
        return 0.0
    return c_data[country_a]["relations"].get(country_b, 0.0)

func change_relation(country_a: String, country_b: String, amount: float) -> void:
    var c_data = ProvinceRegistry.countries_data
    if not c_data.has(country_a) or not c_data.has(country_b): 
        return
        
    var current = get_relation(country_a, country_b)
    # Округляем итоговое значение отношений
    var new_rel = round(clamp(current + amount, -100.0, 100.0))
    
    c_data[country_a]["relations"][country_b] = new_rel
    c_data[country_b]["relations"][country_a] = new_rel

func change_ideology(country: String, new_ideology: String, cost: float) -> bool:
    var c_data = ProvinceRegistry.countries_data[country]
    if c_data.get("balance", 0.0) >= cost and IDEOLOGIES.has(new_ideology):
        c_data["balance"] -= cost
        c_data["ideology"] = new_ideology
        return true
    return false

func get_gdp(country: String, product_cost: float) -> float:
    var c_data = ProvinceRegistry.countries_data[country]
    var monthly = c_data.get("monthly_income", 0.0)
    var factories = c_data.get("factories", 0)
    var sanctions = c_data.get("sanctions", 0.0)
    var actual_price = product_cost * (1.0 - (sanctions / 100.0))
    return (factories * actual_price + monthly) * 12.0

func toggle_sanctions(attacker: String, target: String, cost: float) -> bool:
    var c_data = ProvinceRegistry.countries_data
    if not c_data.has(attacker) or not c_data.has(target):
        return false
        
    var target_data = c_data[target]
    if not target_data.has("sanctioned_by"):
        target_data["sanctioned_by"] = {}
        
    # ЕСЛИ САНКЦИИ УЖЕ ЕСТЬ -> ОТМЕНЯЕМ
    if target_data["sanctioned_by"].has(attacker):
        target_data["sanctioned_by"].erase(attacker)
        _recalculate_total_sanctions(target)
        change_relation(attacker, target, 15.0) 
        sanctions_removed.emit(attacker, target)
        return true
        
    # ЕСЛИ САНКЦИЙ НЕТ -> НАКЛАДЫВАЕМ
    if c_data[attacker].get("balance", 0.0) >= cost:
        c_data[attacker]["balance"] -= cost
        
        # Получаем ВВП атакующего и мировой ВВП (передаем актуальную цену продукта)
        var current_product_cost = 500000.0 # Желательно брать из settings.product_cost
        var attacker_gdp = get_gdp(attacker, current_product_cost)
        var world_gdp = get_world_gdp(current_product_cost)
        
        # Формула: доля ВВП страны от мирового ВВП
        var sanction_power = (attacker_gdp / world_gdp) * 100.0
        
        target_data["sanctioned_by"][attacker] = sanction_power
        _recalculate_total_sanctions(target)
        change_relation(attacker, target, -15.0)
        sanctions_imposed.emit(attacker, target)
        return true
        
    return false

func _recalculate_total_sanctions(country: String) -> void:
    var target_data = ProvinceRegistry.countries_data[country]
    var total_power: float = 0.0
    for attacker in target_data.get("sanctioned_by", {}):
        total_power += target_data["sanctioned_by"][attacker]
        
    # Округляем до целого числа через roundi
    target_data["sanctions"] = float(roundi(clamp(total_power, 0.0, 100.0)))

func get_world_gdp(product_cost: float) -> float:
    var total_gdp = 0.0
    for country in ProvinceRegistry.countries_data.keys():
        total_gdp += get_gdp(country, product_cost)
    return max(total_gdp, 1.0) # Защита от деления на ноль
