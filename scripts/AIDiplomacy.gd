# =============================================================================
# AIDiplomacy.gd
# ИИ: объявление войн, мир, санкции, дрейф отношений (бывший раздел 5).
#
# Класс не хранит состояния — читает/пишет его через синглтон AIManager.
# =============================================================================
class_name AIDiplomacy
extends RefCounted

static func process_diplomacy(country: String) -> void:
    var c_data  = ProvinceRegistry.countries_data[country]
    var enemies = ProvinceRegistry.war_relations.get(country, [])

    process_sanctions(country)

    if not enemies.is_empty():
        try_make_peace(country, c_data, enemies)
        return  # воюем — новые войны не объявляем

    try_declare_war(country, c_data)

static func try_make_peace(country: String, c_data: Dictionary, enemies: Array) -> void:
    var ideology    = c_data.get("ideology", "liberalism")
    var peace_mult  = DiplomacyManager.IDEOLOGIES[ideology]["peace"]

    if randf() < (0.10 * peace_mult):
        var target_enemy = enemies.pick_random()

        # --- Если у одной из сторон 0 провинций — мир заключается безусловно ---
        var country_provinces = ProvinceRegistry.owner_province_count.get(country, 0)
        var enemy_provinces    = ProvinceRegistry.owner_province_count.get(target_enemy, 0)

        if country_provinces > 0 and enemy_provinces > 0:
            # --- НОВАЯ ЛОГИКА ОЦЕНКИ ПРЕИМУЩЕСТВА ---
            var ai_army = float(AIManager.get_country_total_soldiers(country))
            var enemy_army = float(AIManager.get_country_total_soldiers(target_enemy))

            var ai_gdp = ProvinceRegistry.get_gdp(country)
            var enemy_gdp = ProvinceRegistry.get_gdp(target_enemy)

            # Если армия ИИ >= 1.5 от вражеской ИЛИ ВВП ИИ >= 1.5 от вражеского, 
            # то ИИ отказывается заключать мир.
            if ai_army >= enemy_army * 1.5 or ai_gdp >= enemy_gdp * 1.5:
                return
        # ------------------------------------------

        if target_enemy != AIManager.settings.active_country:
            # Если у одной из сторон есть провинция, до которой нельзя добраться
            # нормально (только через свои провинции или море) — мир не заключаем,
            # война продолжается (например, страна разрезана надвое оккупацией).
            if not Pathfinder.is_capital_connected(country) \
            or not Pathfinder.is_capital_connected(target_enemy):
                return

            ProvinceRegistry.annex_all_occupied_by(country)
            ProvinceRegistry.annex_all_occupied_by(target_enemy)
            ProvinceRegistry.end_war(country, target_enemy)

static func try_declare_war(country: String, c_data: Dictionary) -> void:
    var ideology          = c_data.get("ideology", "liberalism")
    var war_mult          = DiplomacyManager.IDEOLOGIES[ideology]["war"]
    var neighbor          = AIManager.get_random_neighbor_country(country)

    if neighbor == "" or neighbor == country:
        return

    var relations         = DiplomacyManager.get_relation(country, neighbor)
    var neighbor_ideology = ProvinceRegistry.countries_data[neighbor].get("ideology", "liberalism")

    var base_chance = 0.0
    if relations >= 0:
        base_chance = 0.0
    elif relations > -30:
        base_chance = 0.01
    elif relations > -70:
        base_chance = 0.05
    else:
        base_chance = 0.15

    var declare_chance = base_chance * war_mult

    if ideology == neighbor_ideology and relations >= -20.0:
        declare_chance *= 0.5

    if randf() < declare_chance:
        ProvinceRegistry.declare_war(country, neighbor)

## Ответные санкции
static func process_sanctions(country: String) -> void:
    var c_data        = ProvinceRegistry.countries_data[country]
    var sanctioned_by = c_data.get("sanctioned_by", {})
    if sanctioned_by.is_empty():
        return

    for attacker in sanctioned_by:
        var attacker_data = ProvinceRegistry.countries_data.get(attacker, {})
        if not attacker_data.get("sanctioned_by", {}).has(country):
            var sanction_cost = 150000.0
            if c_data.get("balance", 0.0) >= sanction_cost * (1.0 + AIManager.RESERVE_RATIO):
                DiplomacyManager.toggle_sanctions(country, attacker, sanction_cost)

## Ежемесячный дрейф отношений
static func process_relations_drift(country: String) -> void:
    var neighbor = AIManager.get_random_neighbor_country(country)
    if neighbor == "" or neighbor == country:
        return

    var ideology          = ProvinceRegistry.countries_data[country].get("ideology", "liberalism")
    var neighbor_ideology = ProvinceRegistry.countries_data[neighbor].get("ideology", "liberalism")

    var drift: float = randf_range(-2.0, 3.0) if ideology == neighbor_ideology else randf_range(-5.0, 2.0)

    DiplomacyManager.change_relation(country, neighbor, drift)
