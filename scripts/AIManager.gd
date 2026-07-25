# =============================================================================
# AIManager.gd
# Управляет поведением всех стран кроме активной.
#
# Это autoload-синглтон. Хранит ОБЩЕЕ состояние (кулдауны, кэши, settings,
# ссылки на сцену) и раз в день/месяц раздаёт работу по модулям — сами модули
# состояния не хранят и обращаются к нему как к "AIManager.xxx" напрямую,
# т.к. он глобально доступен по имени (см. Project Settings → Autoload).
#
# МОДУЛИ (каждый — RefCounted-класс со static-функциями):
#   AIEconomy    — строительство фабрик
#   AIWeapons    — БПЛА и ракетные программы (закупка, резервы, удары)
#   AIMilitary   — найм войск и движение армий
#   AIDiplomacy  — войны, мир, санкции, дрейф отношений
#   AIPopulation — рост/потери населения, беженцы
#   AITrade      — продажа накопленных товаров
#
# ЗДЕСЬ ОСТАЁТСЯ:
#   1. Общее состояние (кулдауны, кэши, settings, Map)
#   2. Инициализация и тики (_ready, _process, _on_day_passed, _on_month_passed)
#   3. Доход (начисляется каждый кадр только активному игроку)
#   4. Общие вспомогательные функции (кэш провинций страны и т.п.),
#      которыми пользуются несколько модулей сразу
# =============================================================================

extends Node

var settings = preload("res://new_resource.tres")

@onready var balance_label = get_node_or_null(
    "/root/Game/CanvasLayer/TopMenu/TopPanel/BalanceLabel"
)

## Нужен, чтобы визуально запускать спрайты дронов (как это делает uav_menu.gd)
@onready var Map = get_node_or_null("/root/Game/Map")

const UAVDroneScript = preload("res://scripts/uav_drone.gd")
const MissileScript   = preload("res://scripts/missile.gd")

# -----------------------------------------------------------------------------
# 1. СОСТОЯНИЕ И КОНСТАНТЫ
# -----------------------------------------------------------------------------

## Кулдаун строительства фабрик: country -> дней до следующего строительства
var factory_cooldowns: Dictionary = {}

## Кулдаун найма войск: country -> дней до следующего найма
var recruitment_cooldowns: Dictionary = {}

## Кулдаун ударов БПЛА: country -> дней до следующего залпа
var uav_launch_cooldowns: Dictionary = {}

## Кулдаун ракетных ударов: country -> дней до следующего залпа
var missile_launch_cooldowns: Dictionary = {}

# -----------------------------------------------------------------------------
# ОПТИМИЗАЦИЯ: ежедневные кэши
# -----------------------------------------------------------------------------
# ПРОБЛЕМА: get_country_provinces() раньше сканировал ВЕСЬ province_data
# (сейчас ~10000 записей) на каждый вызов, а вызывается он по 3-5 раз на
# КАЖДУЮ страну КАЖДЫЙ день (экономика, рекрутинг, армия, движение войск,
# поиск соседей). Итого O(countries * provinces) вместо O(provinces).
# При 300 провинциях это было незаметно, при 10000 — фризы каждый тик.
#
# РЕШЕНИЕ: один раз в день (O(provinces)) строим индекс "страна -> её
# провинции" и множество "безопасных" провинций (без боёв/оккупации),
# дальше весь день читаем из кэша за O(1)/O(k).

## country -> Array[int] провинций страны. Пересобирается в _build_initial_country_cache().
var country_provinces_cache: Dictionary = {}

# Переменные для разделения нагрузки обсчета населения (чангинг)
var pop_chunks: Array = []
var pop_chunk_index: int = 0
const POP_CHUNKS_COUNT = 10

## p_id(int) -> true для провинций без активных боёв и без оккупации.
## Используется для быстрого поиска "безопасной" провинции беженцами.
var safe_provinces_cache: Dictionary = {}

## Плоский список ключей safe_provinces_cache — для быстрого pick_random()
## без BFS, когда рядом безопасной провинции не нашлось.
var safe_provinces_list: Array = []

# Минимальный баланс-резерв, который ИИ НЕ тратит на фабрики (чтобы не уходить в ноль)
const RESERVE_RATIO        = 0.05   # 5% резерва сверх стоимости
const FACTORY_COOLDOWN_DAYS = 30    # раз в 30 дней запускаем цикл строительства фабрик
const FACTORY_BUDGET_FRACTION = 0.4 # ИИ тратит на фабрики до 40% текущего баланса за один заход
const MAX_QUEUE_PER_PROVINCE = 5    # максимум фабрик в очереди одной провинции
const RECRUIT_COOLDOWN_DAYS = 5     # раз в 5 дней нанимаем войска
const MIN_RECRUIT_SIZE      = 50    # минимальный размер призыва
const RECRUIT_BUDGET_FRACTION = 0.3 # тратим на армию 30% текущего баланса

# На сколько падает счастье провинции за каждую 1000 набранных солдат
const HAPPINESS_DRAIN_PER_1K_RECRUITS = 0.1

# --- ЛИМИТ АРМИИ НА ОСНОВЕ ВВП ---
const ARMY_LIMIT_GDP_RATIO = 0.0000714

# --- БПЛА-ПРОГРАММА ИИ ---
const UAV_RESERVE_PEACETIME = 0.3   # 30% дневных товаров в резерв в мирное время
const UAV_RESERVE_WARTIME   = 0.6   # 60% дневных товаров в резерв во время войны

const UAV_LAUNCH_COOLDOWN_DAYS  = 4   # раз в 4 дня — новый залп
const UAV_MIN_BATCH_PER_TARGET  = 5   # меньше этого по одной цели не бьём
const UAV_MAX_PER_TARGET        = 20  # не тратим на одну провинцию весь запас разом
const UAV_MAX_TARGETS_PER_STRIKE = 3  # бьём максимум по стольким провинциям за раз

# --- РАКЕТНАЯ ПРОГРАММА ИИ ---
const MISSILE_RESERVE_PEACETIME = 0.05  # 5% дневных товаров в резерв в мирное время
const MISSILE_RESERVE_WARTIME   = 0.10  # 10% дневных товаров в резерв во время войны

const MISSILE_ORDER_INTERVAL_DAYS = 7   # раз в 7 дней пробуем купить компанию / заказать ракеты

const MISSILE_STRIKE_COOLDOWN_DAYS  = 6  # раз в 6 дней — новый ракетный залп
const MISSILE_MAX_TARGETS_PER_STRIKE = 3 # бьём максимум по стольким провинциям за раз

# -----------------------------------------------------------------------------
# 2. ИНИЦИАЛИЗАЦИЯ И ТИКИ
# -----------------------------------------------------------------------------

func _ready() -> void:
    GameClock.on_day_passed.connect(_on_day_passed)
    GameClock.on_month_passed.connect(_on_month_passed)

    # Следим за захватом провинций, чтобы сразу обновлять кэш, а не пересчитывать его с нуля
    ProvinceRegistry.province_captured.connect(_on_province_captured)

    # Строим стартовый кэш провинций для ИИ
    _build_initial_country_cache()

    # Разбиваем массив провинций на 10 частей для оптимизации населения
    for i in range(POP_CHUNKS_COUNT):
        pop_chunks.append([])

    var idx = 0
    for p_id_str in ProvinceRegistry.province_data:
        pop_chunks[idx % POP_CHUNKS_COUNT].append(p_id_str)
        idx += 1

    # Считаем доход при старте
    for country in ProvinceRegistry.countries_data:
        _update_monthly_income(country)

func _process(delta: float) -> void:
    if GameClock.paused:
        return
    _tick_income(delta)

# ── Ежедневный тик (раздаёт работу по модулям) ──────────────────────────────
func _on_day_passed(_date: Dictionary) -> void:
    var current_day: int = int(_date.get("day", 1))

    for country in ProvinceRegistry.countries_data:
        if country == settings.active_country:
            continue

        var c_data = ProvinceRegistry.countries_data[country]

        # 0. Начисляем дневной доход ИИ
        var monthly = c_data.get("monthly_income", 100000.0)
        c_data["balance"] = c_data.get("balance", 0.0) + (monthly / 30.0)

        var country_index: int = int(ProvinceRegistry.country_index.get(country, 0))

        # 1. Быстрые кулдауны
        AIMilitary.tick_recruitment_cooldown(country)
        AIEconomy.tick_factory_cooldown(country)
        AIWeapons.tick_uav_launch_cooldown(country)
        AIWeapons.tick_missile_launch_cooldown(country)

        # 2. Резервы под БПЛА и ракеты — ДО торговли, иначе торговля продаст
        # весь склад products в balance раньше, чем БПЛА/ракеты успеют его забрать
        AIWeapons.skim_production_reserves(country)
        if (current_day + country_index) % 6 == 0:
            AIWeapons.process_uav_program(country)
        if (current_day + country_index) % MISSILE_ORDER_INTERVAL_DAYS == 0:
            AIWeapons.process_missile_program(country)

        # 3. Торговля — продажа того, что осталось от товаров после резервов
        AITrade.process_trade(country)

        # 4. Экономика — раз в 5 дней
        if (current_day + country_index) % 5 == 0:
            AIEconomy.process_economy(country)

        # 5. Рекрутинг — раз в 3 дня
        if (current_day + country_index) % 3 == 0:
            AIMilitary.process_recruitment(country)

        # 6. Движение войск — раз в 4 дня
        if (current_day + country_index) % 4 == 0:
            AIMilitary.process_military_movement(country)

        # 7. Запуск БПЛА по врагу — раз в 2 дня
        if (current_day + country_index) % 2 == 0:
            AIWeapons.process_uav_strikes(country)

        # 7.5 Запуск ракет по врагу — раз в 5 дней, со сдвигом от БПЛА
        if (current_day + country_index + 1) % 5 == 0:
            AIWeapons.process_missile_strikes(country)

    # 8. Обсчет населения
    AIPopulation.process_population()

# ── Ежемесячный тик ───────────────────────────────────────────────────────────
func _on_month_passed(_date: Dictionary) -> void:
    for country in ProvinceRegistry.countries_data:
        _update_monthly_income(country)

    for country in ProvinceRegistry.countries_data:
        if country == settings.active_country:
            continue
        AIDiplomacy.process_diplomacy(country)
        AIDiplomacy.process_relations_drift(country)

# -----------------------------------------------------------------------------
# 3. ДОХОД — начисление в реальном времени
# -----------------------------------------------------------------------------

func _tick_income(delta: float) -> void:
    var seconds_per_month = 30.0 * GameClock.SECONDS_PER_DAY
    var speed = GameClock.SPEEDS[GameClock.speed_index]
    var inc = (delta * speed) / seconds_per_month

    # Плавный доход только для игрока
    var active = settings.active_country
    if ProvinceRegistry.countries_data.has(active):
        var c_data = ProvinceRegistry.countries_data[active]
        var monthly = c_data.get("monthly_income", 100000.0)
        c_data["balance"] = c_data.get("balance", 0.0) + (monthly * inc)

    if is_instance_valid(balance_label) and settings.can_draw:
        balance_label.balance_update()

func _update_monthly_income(country: String) -> void:
    var c_data = ProvinceRegistry.countries_data[country]
    c_data["monthly_income"] = _calculate_monthly_income(country)

func _calculate_monthly_income(country: String) -> float:
    var total_pop = _get_country_population(country)
    var ideology  = ProvinceRegistry.countries_data[country].get("ideology", "liberalism")
    var tax_mult  = DiplomacyManager.IDEOLOGIES[ideology]["tax"]
    return float(total_pop) * 1.0 * tax_mult

# -----------------------------------------------------------------------------
# 4. ОБЩИЕ ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ (используются несколькими модулями)
# -----------------------------------------------------------------------------

func _get_country_population(country: String) -> int:
    var total = 0
    for p_id in get_country_provinces(country):
        total += int(ProvinceRegistry.province_data.get(p_id, {}).get("population", 0))
    return total

## Суммарная численность войск страны (по всем её провинциям)
func get_country_total_soldiers(country: String) -> int:
    var total := 0
    for p_id in get_country_provinces(country):
        for circle in DivisionManager.armies.get(p_id, []):
            if is_instance_valid(circle) and circle.division_owner == country:
                total += circle.soldiers
    return total

## O(1) — читает готовый индекс, собранный в _build_initial_country_cache().
func get_country_provinces(country: String) -> Array:
    return country_provinces_cache.get(country, [])

## Собирает базовое распределение провинций при старте игры
func _build_initial_country_cache() -> void:
    country_provinces_cache.clear()
    for p_id_str in ProvinceRegistry.province_data:
        var p_id = int(p_id_str)
        var owner = ProvinceRegistry.province_data[p_id_str].get("owner", "")
        if owner != "" and owner != ProvinceRegistry.SEA_OWNER:
            if not country_provinces_cache.has(owner):
                country_provinces_cache[owner] = []
            country_provinces_cache[owner].append(p_id)

## Вызывается только когда провинция РЕАЛЬНО меняет владельца (быстродействие O(1))
func _on_province_captured(p_id: int, new_owner: String) -> void:
    for country in country_provinces_cache:
        country_provinces_cache[country].erase(p_id)

    if new_owner != "":
        if not country_provinces_cache.has(new_owner):
            country_provinces_cache[new_owner] = []
        country_provinces_cache[new_owner].append(p_id)

func get_random_neighbor_country(country: String) -> String:
    var neighbors = []
    for p_id in get_country_provinces(country):
        for adj_id in ProvinceRegistry.province_adjacency.get(p_id, []):
            var clean_id = int(adj_id)
            var owner    = ProvinceRegistry.province_data.get(clean_id, {}).get("owner", "")
            if owner != "" and owner != country and ProvinceRegistry.countries_data.has(owner) and not neighbors.has(owner):
                neighbors.append(owner)

    return "" if neighbors.is_empty() else neighbors.pick_random()
