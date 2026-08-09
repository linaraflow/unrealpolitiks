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

        # --- ИИ никогда не заключает мир с игроком ---
        if target_enemy == AIManager.settings.active_country:
            return

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

        if true:
            # Если у одной из сторон есть провинция, до которой нельзя добраться
            # нормально (только через свои провинции или море) — мир не заключаем,
            # война продолжается (например, страна разрезана надвое оккупацией).
            if not Pathfinder.is_capital_connected(country) \
            or not Pathfinder.is_capital_connected(target_enemy):
                return

            # only_from ограничивает аннексию провинциями именно этой пары
            # воюющих сторон — иначе, если country/target_enemy параллельно
            # оккупируют земли третьей страны в ДРУГОЙ войне, этот мир мог
            # случайно аннексировать и её последнюю провинцию, стерев её из
            # countries_data (см. разбор бага "страна пропала, но её земли
            # остались на карте").
            ProvinceRegistry.annex_all_occupied_by(country, target_enemy)
            ProvinceRegistry.annex_all_occupied_by(target_enemy, country)

            # Подстраховка: аннексия теоретически может по цепочке (через
            # _check_capital_transfer) элиминировать одну из сторон ЭТОГО
            # мира. Если так — end_war() для неё уже бессмысленен и не нужен.
            if not ProvinceRegistry.countries_data.has(country) \
            or not ProvinceRegistry.countries_data.has(target_enemy):
                return

            ProvinceRegistry.end_war(country, target_enemy)

## Во сколько раз умножается шанс объявления войны соседу, у которого
## санкции >= DiplomacyManager.HIGH_SANCTIONS_THRESHOLD.
const HIGH_SANCTIONS_WAR_MULT := 2.5

## Базовый (до применения war_mult идеологии) шанс/день, что НЕ граничащая
## страна тоже объявит войну сильно засанкционированной стране.
const HIGH_SANCTIONS_DISTANT_WAR_CHANCE := 0.00375

static func try_declare_war(country: String, c_data: Dictionary) -> void:
    var ideology = c_data.get("ideology", "liberalism")
    var war_mult = DiplomacyManager.IDEOLOGIES[ideology]["war"]

    # --- Обычная логика: сосед с плохими отношениями (+бонус за санкции) ---
    var neighbor = AIManager.get_random_neighbor_country(country)
    if neighbor != "" and neighbor != country:
        var declare_chance = _get_neighbor_war_chance(country, ideology, neighbor, war_mult)

        if DiplomacyManager.has_high_sanctions(neighbor):
            declare_chance *= HIGH_SANCTIONS_WAR_MULT

        if randf() < declare_chance:
            ProvinceRegistry.declare_war(country, neighbor)
            return

    # --- Санкционные войны: если в мире есть сильно засанкционированная страна,
    #     на неё может напасть и НЕ граничащий с ней сосед ---
    _try_declare_war_on_distant_sanctioned(country, ideology, neighbor, war_mult)

static func _get_neighbor_war_chance(country: String, ideology: String, neighbor: String, war_mult: float) -> float:
    var relations         = DiplomacyManager.get_relation(country, neighbor)
    var neighbor_ideology = ProvinceRegistry.countries_data[neighbor].get("ideology", "liberalism")

    var base_chance = 0.0
    if relations >= 0:
        base_chance = 0.0
    elif relations > -30:
        base_chance = 0.0025
    elif relations > -70:
        base_chance = 0.0125
    else:
        base_chance = 0.0375

    var declare_chance = base_chance * war_mult

    if ideology == neighbor_ideology and relations >= -20.0:
        declare_chance *= 0.5

    return declare_chance

## Даёт шанс объявить войну засанкционированной (кэш DiplomacyManager.high_sanctions_countries)
## стране, даже если с ней нет общей границы. skip_neighbor исключает страну,
## которую уже проверили как соседа (чтобы не откатывать бросок дважды).
## Использует готовый кэш вместо перебора всех countries_data — быстро даже
## при большом числе стран в мире.
static func _try_declare_war_on_distant_sanctioned(country: String, ideology: String, skip_neighbor: String, war_mult: float) -> void:
    var candidates: Array = []
    for other in DiplomacyManager.get_high_sanctions_countries():
        if other == country or other == skip_neighbor:
            continue
        if ProvinceRegistry.owner_province_count.get(other, 0) <= 0:
            continue
        # Уже воюем — новую войну не объявляем
        if ProvinceRegistry.war_relations.get(country, []).has(other):
            continue
        candidates.append(other)

    if candidates.is_empty():
        return

    var target = candidates.pick_random()

    if randf() < HIGH_SANCTIONS_DISTANT_WAR_CHANCE * war_mult:
        ProvinceRegistry.declare_war(country, target)

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
