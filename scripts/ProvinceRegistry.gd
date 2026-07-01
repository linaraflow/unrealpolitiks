extends Node

var settings = preload("res://new_resource.tres")

signal province_captured(province_id: int, new_owner: String)
signal province_army_changed(p_id: int)

# НОВЫЙ СИГНАЛ: провинция оккупирована / снята с оккупации
signal province_occupied(province_id: int, occupier: String)   # occupier="" → снятие оккупации

# province_id -> country_id (строка типа "Germany", "France")
var province_owners: Dictionary = {}

# province_id -> country_id (оккупант, "" если не оккупировано)
var province_occupants: Dictionary = {}

# country_id -> индекс в массиве цветов (0..255)
var country_index: Dictionary = {}
var country_colors: Array[Color] = []
var province_data: Dictionary = {}
var province_adjacency: Dictionary = {}
var owner_province_count: Dictionary = {}  # "Germany" -> 3
# Словарь: "Страна" -> ["Враг1", "Враг2"]
var war_relations: Dictionary = {}

var countries_data: Dictionary = {}

func _ready():
	_load_countries()
	_load_province_data()
	_load_province_adjacency()
	GameClock.on_day_passed.connect(_on_day_passed)
	_recalculate_all_populations()
	_recalculate_all_factories() # Первичный расчет фабрик при старте игры

func _on_day_passed(_date: Dictionary) -> void:
	_recalculate_all_populations()
	_process_economy()

## Пересчитывает население каждой страны как сумму населения её провинций
func _recalculate_all_populations() -> void:
	var totals: Dictionary = {}
	for key in province_data:
		var p = province_data[key]
		var owner = p.get("owner", "")
		if owner == "":
			continue
		var pop = int(p.get("population", 0))
		totals[owner] = totals.get(owner, 0) + pop

	for country in countries_data:
		countries_data[country]["population"] = totals.get(country, 0)

## Пересчитывает фабрики каждой страны при старте игры (только неоккупированные)
func _recalculate_all_factories() -> void:
	for country in countries_data:
		countries_data[country]["factories"] = 0

	for key in province_data:
		var p = province_data[key]
		var owner = p.get("owner", "")
		# Считаем готовые заводы только в неоккупированных провинциях, как в экономике
		if owner != "" and p.get("against_occupation", "") == "":
			var f_count = int(p.get("factories", 0))
			if countries_data.has(owner):
				countries_data[owner]["factories"] += f_count

## Население одной провинции
func get_province_population(province_id: int) -> int:
	return int(province_data.get(str(province_id), {}).get("population", 0))

## Население страны (уже посчитанное, обновляется раз в игровой день)
func get_country_population(country: String) -> int:
	return int(countries_data.get(country, {}).get("population", 0))

func _load_province_data():
	if not FileAccess.file_exists("res://scripts/provinces.json"):
		return
	var file = FileAccess.open("res://scripts/provinces.json", FileAccess.READ)
	var json = JSON.new()
	json.parse(file.get_as_text())
	province_data = json.data
	settings.province_data = province_data

	# Восстанавливаем оккупацию из JSON при загрузке
	for key in province_data:
		var p = province_data[key]
		var occ = p.get("against_occupation", "")
		if occ != "":
			var p_id = int(key)
			province_occupants[p_id] = occ

	_rebuild_count_cache()

func _load_province_adjacency():
	if not FileAccess.file_exists("res://scripts/province_adjacency.json"):
		return
	var file = FileAccess.open("res://scripts/province_adjacency.json", FileAccess.READ)
	var json = JSON.new()
	json.parse(file.get_as_text())
	province_adjacency = json.data
	settings.province_adjacency = province_adjacency

func _rebuild_count_cache():
	owner_province_count.clear()
	for key in province_data:
		var owner = province_data[key].get("owner", "")
		owner_province_count[owner] = owner_province_count.get(owner, 0) + 1

func _load_countries():
	if not FileAccess.file_exists("res://scripts/countries.json"):
		return
	var file = FileAccess.open("res://scripts/countries.json", FileAccess.READ)
	var json = JSON.new()
	json.parse(file.get_as_text())
	countries_data = json.data

	for key in json.data:
		var entry = json.data[key]
		var i = entry["index"]
		country_index[key] = i
		var c = entry["color"]
		while country_colors.size() <= i:
			country_colors.append(Color())
		country_colors[i] = Color(c[0]/255.0, c[1]/255.0, c[2]/255.0)

# ─── ЗАХВАТ (полная передача владения) ────────────────────────────────────────

func capture(from_country: String, to_country: String) -> void:
	for p_id in province_owners:
		if province_owners[p_id] == from_country:
			_set_owner(p_id, to_country)

func capture_province(province_id: int, new_owner: String) -> void:
	var old_owner = province_data[str(province_id)].get("owner", "")
	if old_owner != "":
		owner_province_count[old_owner] = owner_province_count.get(old_owner, 1) - 1
		
		# Проверяем, не была ли захвачена столица
		_check_capital_transfer(province_id, old_owner)
		
	owner_province_count[new_owner] = owner_province_count.get(new_owner, 0) + 1
	_set_owner(province_id, new_owner)
	province_data[str(province_id)]["owner"] = new_owner

func _set_owner(p_id: int, new_owner: String) -> void:
	province_owners[p_id] = new_owner
	province_captured.emit(p_id, new_owner)

# ─── ОККУПАЦИЯ ────────────────────────────────────────────────────────────────

## Оккупировать провинцию
func occupy_province(province_id: int, occupier: String) -> void:
	var key = str(province_id)
	if not province_data.has(key):
		return

	var current_owner = province_data[key].get("owner", "")
	if current_owner == occupier:
		return

	# Фиксируем истинного владельца ОДИН раз — при первом захвате провинции
	if not province_data[key].has("core_owner"):
		var existing_stripes = province_data[key].get("against_occupation", "")
		province_data[key]["core_owner"] = existing_stripes if existing_stripes != "" else current_owner

	var core_owner = province_data[key]["core_owner"]

	# Возврат провинции происходит только если оккупант — это ИСТИННЫЙ владелец
	if occupier == core_owner:
		province_data[key]["against_occupation"] = ""
		province_occupants.erase(province_id)
		capture_province(province_id, occupier)
		province_occupied.emit(province_id, "")
		print("[Registry] Провинция %d освобождена и возвращена %s" % [province_id, occupier])
		return

	# Полосы ВСЕГДА показывают истинного владельца, а не последнего контролёра
	province_data[key]["against_occupation"] = core_owner
	province_occupants[province_id] = core_owner
	capture_province(province_id, occupier)
	province_occupied.emit(province_id, core_owner)

	print("[Registry] Провинция %d захвачена %s (полосы: %s)" % [province_id, occupier, core_owner])
	

## Снять оккупацию (например при освобождении провинции)
func liberate_province(province_id: int) -> void:
	var key = str(province_id)
	if not province_data.has(key):
		return

	province_occupants.erase(province_id)
	province_data[key]["against_occupation"] = ""

	print("[Registry] Оккупация снята с провинции %d" % province_id)
	province_occupied.emit(province_id, "")

## Аннексировать все оккупированные провинции одной страны.
## Вызывать при мирном договоре или кнопкой в тестовом режиме.
func annex_all_occupied_by(occupier: String) -> void:
	print("=== ANNEX === occupier:", occupier)
	print("=== ANNEX === province_occupants:", province_occupants)
	
	var to_annex: Array[int] = []
	for p_id in province_occupants:
		if province_occupants[p_id] != "":
			var current_owner = province_data[str(p_id)].get("owner", "")
			print("p_id:", p_id, " owner:", current_owner)
			if current_owner == occupier:
				to_annex.append(p_id)

	for p_id in to_annex:
		province_data[str(p_id)]["against_occupation"] = ""
		province_data[str(p_id)]["core_owner"] = occupier   # аннексия узаконивает нового владельца
		province_occupants.erase(p_id)
		province_occupied.emit(p_id, "")

	print("[Registry] Полосы убраны с %d провинций %s" % [to_annex.size(), occupier])

## Проверить — оккупирована ли провинция
func is_occupied(province_id: int) -> bool:
	return province_occupants.has(province_id) and province_occupants[province_id] != ""

## Получить оккупанта провинции (или "" если не оккупирована)
func get_occupant(province_id: int) -> String:
	return province_occupants.get(province_id, "")

# ─── ВОЙНА ────────────────────────────────────────────────────────────────────

func declare_war(attacker: String, defender: String):
	if not war_relations.has(attacker):
		war_relations[attacker] = []
	if not war_relations.has(defender):
		war_relations[defender] = []

	if not defender in war_relations[attacker]:
		war_relations[attacker].append(defender)
	if not attacker in war_relations[defender]:
		war_relations[defender].append(attacker)

	countries_data[attacker]["is_at_war"] = true
	countries_data[defender]["is_at_war"] = true

	print("War: ", attacker, " vs ", defender)

func is_at_war(country_a: String, country_b: String) -> bool:
	return war_relations.get(country_a, []).has(country_b)

func end_war(country_a: String, country_b: String) -> void:
	if war_relations.has(country_a):
		war_relations[country_a].erase(country_b)
	if war_relations.has(country_b):
		war_relations[country_b].erase(country_a)

	if war_relations.get(country_a, []).is_empty():
		if countries_data.has(country_a):
			countries_data[country_a]["is_at_war"] = false

	if war_relations.get(country_b, []).is_empty():
		if countries_data.has(country_b):
			countries_data[country_b]["is_at_war"] = false

	# === Белый мир: провинции возвращаются своим корам ===
	var provinces_to_liberate = []
	for p_id in province_occupants.keys():
		var key = str(p_id)
		var core = province_data[key].get("core_owner", province_occupants[p_id])
		var current_owner = province_data[key].get("owner", "")

		if current_owner == core:
			continue  # уже и так у себя дома, нечего освобождать

		var core_is_party = (core == country_a or core == country_b)
		var occupier_is_party = (current_owner == country_a or current_owner == country_b)

		if core_is_party or occupier_is_party:
			provinces_to_liberate.append(p_id)

	for p_id in provinces_to_liberate:
		var key = str(p_id)
		var core = province_data[key].get("core_owner", "")

		province_data[key]["against_occupation"] = ""
		province_occupants.erase(p_id)
		capture_province(p_id, core)
		province_occupied.emit(p_id, "")

	print("[Registry] Война завершена: %s и %s (возвращено провинций: %d)" % [country_a, country_b, provinces_to_liberate.size()])
	
func _check_capital_transfer(captured_p_id: int, old_owner: String) -> void:
	if not countries_data.has(old_owner):
		return
		
	var current_capital = int(countries_data[old_owner].get("capital", 0))
	
	# Если захваченная провинция — это столица
	if current_capital == captured_p_id:
		var available_provinces = []
		
		# Собираем все оставшиеся провинции страны
		for p_id in province_data.keys():
			if province_data[p_id].get("owner", "") == old_owner and int(p_id) != captured_p_id:
				available_provinces.append(int(p_id))
				
		# Если есть куда переносить — выбираем случайную
		if not available_provinces.is_empty():
			var new_capital = available_provinces.pick_random()
			countries_data[old_owner]["capital"] = new_capital
			print("[Registry] Столица %s перенесена в провинцию %d" % [old_owner, new_capital])
		else:
			print("[Registry] Страна %s потеряла последнюю провинцию (столицу)" % old_owner)


# ЭКОНОМИКА
func _process_economy() -> void:
	var production_by_country: Dictionary = {}
	
	# Обнуляем количество фабрик у всех стран перед подсчетом
	for country in countries_data:
		countries_data[country]["factories"] = 0
	
	for key in province_data:
		var p = province_data[key]
		
		# 1. Просчет очереди строительства
		if p.has("factory_queue") and p["factory_queue"].size() > 0:
			p["factory_queue"][0] += 1
			
			if p["factory_queue"][0] >= 15:
				p["factory_queue"].pop_front()
				p["factories"] = p.get("factories", 0) + 1
				
		# 2. Подсчет готовых заводов (только в неоккупированных)
		var owner = p.get("owner", "")
		if owner != "" and p.get("against_occupation", "") == "":
			var f_count = p.get("factories", 0)
			if f_count > 0:
				production_by_country[owner] = production_by_country.get(owner, 0) + f_count
				
	# 3. Начисление продуктов и запись количества фабрик в данные страны
	for country in countries_data:
		var total_factories = production_by_country.get(country, 0)
		countries_data[country]["factories"] = total_factories
		
		if total_factories > 0:
			var daily_product = total_factories / 30.0
			countries_data[country]["products"] = countries_data[country].get("products", 0.0) + daily_product

func start_factory_construction(p_id: int, country: String) -> bool:
	var p = province_data[str(p_id)]
	
	# ПРОВЕРКА 1: Ограничение очереди в 5 заводов
	if p.has("factory_queue") and p["factory_queue"].size() >= 5:
		return false
		
	var cost = settings.factory_cost
	if countries_data[country].get("balance", 0.0) < cost:
		return false
		
	if not p.has("factory_queue"):
		p["factory_queue"] = []
		
	countries_data[country]["balance"] -= cost
	p["factory_queue"].append(0)

	return true

	
# ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
# Универсальная функция для разделения разрядов
func _format_number(value: Variant, separator: String = " ") -> String:
	var n = int(value) # Принудительно приводим к int (защита от float)
	var s = str(abs(n))
	var res = ""
	var i = s.length()
	
	while i > 3:
		i -= 3
		res = separator + s.substr(i, 3) + res
	res = s.substr(0, i) + res
	
	if n < 0:
		res = "-" + res
	return res
