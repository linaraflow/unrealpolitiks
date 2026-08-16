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

var balance_label: Label = null

## Нужен, чтобы визуально запускать спрайты дронов (как это делает uav_menu.gd)
var Map: Sprite2D

const UAVDroneScript = preload("res://scripts/uav_drone.gd")
const MissileScript   = preload("res://scripts/missile.gd")

# -----------------------------------------------------------------------------
# 1. СОСТОЯНИЕ И КОНСТАНТЫ
# -----------------------------------------------------------------------------

## Кулдаун строительства фабрик: country -> дней до следующего строительства
var factory_cooldowns: Dictionary = {}

## Кулдаун найма войск: country -> дней до следующего найма
var recruitment_cooldowns: Dictionary = {}

## Кулдаун строительства укреплений: country -> дней до следующей попытки
var fortification_cooldowns: Dictionary = {}

## Если true — армия игрока (settings.active_country) тоже двигается автоматически,
## как у обычного ИИ (управляется чекбоксом ai_army_tick в TopMenu).
var player_ai_army_enabled: bool = false

## Позиция слайдера "агрессии" ИИ (0.0 .. 1.0), выставляется слайдером
## на экране выбора страны (opening.gd). Сама по себе НЕ является множителем —
## используйте get_aggression_multiplier() для получения множителя шанса войны.
var ai_aggression: float = 1.0

## Переводит позицию слайдера (0.0 .. 1.0) в множитель шанса объявления войны
## по нелинейной кривой:
##   0%   (0.0) -> ×0    (ИИ никогда не объявляет войну сам)
##   50%  (0.5) -> ×1.5  (+50% к базовому шансу)
##   100% (1.0) -> ×10   (в 10 раз выше базового шанса)
## На отрезке [0%, 50%] рост линейный (0 -> 1.5), на отрезке [50%, 100%]
## рост экспоненциальный (1.5 -> 10), чтобы вторая половина слайдера
## ощутимо "разгоняла" агрессивность ИИ, а не просто продолжала линейный рост.
static func aggression_to_war_mult(x: float) -> float:
    var t = clampf(x, 0.0, 1.0)
    if t <= 0.5:
        return 3.0 * t
    var progress = (t - 0.5) / 0.5
    return 1.5 * pow(10.0 / 1.5, progress)

func get_aggression_multiplier() -> float:
    return aggression_to_war_mult(ai_aggression)

## Кулдаун ударов БПЛА: country -> дней до следующего залпа
var uav_launch_cooldowns: Dictionary = {}

## Кулдаун ракетных ударов: country -> дней до следующего залпа
var missile_launch_cooldowns: Dictionary = {}

## ОПТИМИЗАЦИЯ: p_id (провинция, где стоит "залипшая" армия) -> дней до
## следующей попытки BFS-поиска врага. Если find_nearest_enemy_province()
## не нашёл достижимого врага (остров без флота, блокада третьей страной
## и т.п.), армия остаётся неподвижной, и БЕЗ этого кэша AIMilitary заново
## гонял бы полный BFS до MAX_BFS_NODES КАЖДЫЙ игровой день, бесконечно —
## именно это давало устойчивый фриз (см. AI PROFILE в логах: одни и те же
## страны с одним и тем же числом армий тормозят одинаково каждый ход подряд).
var stuck_army_cooldowns: Dictionary = {}
const STUCK_ARMY_RETRY_DAYS = 15

# -----------------------------------------------------------------------------
# ОПТИМИЗАЦИЯ: размазывание дневного тика ИИ по нескольким кадрам
# -----------------------------------------------------------------------------
# ПРОБЛЕМА: раньше _on_day_passed() обрабатывал ВСЕ страны мира одним
# синхронным циклом в ОДНОМ кадре смены дня. Каждая отдельная операция внутри
# уже была оптимизирована (O(1)/O(k) кэши), но при большой войне у крупной
# страны (много провинций/армий) сумма работы по всем воюющим странам в этот
# единственный кадр всё равно давала заметный фриз — именно он ощущался
# "каждый день", и рос вместе с масштабом войны.
#
# РЕШЕНИЕ: смена дня по-прежнему происходит раз в игровой день (частота не
# меняется), но обработка стран внутри дня растягивается на несколько
# ПОСЛЕДУЮЩИХ кадров вместо одного — по AI_COUNTRIES_PER_FRAME стран за кадр.
# При типичных 60 fps и разумном бюджете вся очередь стран проходит за доли
# секунды реального времени — на игровой смене дня это незаметно, а пиковая
# нагрузка на кадр падает в разы.
const AI_COUNTRIES_PER_FRAME = 3

var _pending_ai_countries: Array = []
var _pending_ai_date: Dictionary = {}
var _ai_day_in_progress: bool = false

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

const FORTIFICATION_COOLDOWN_DAYS = 20 # раз в 20 дней проверяем, не построить ли укрепление

# На сколько падает счастье провинции за каждую 1000 набранных солдат
# Берём значение напрямую из settings при каждом обращении (через get),
# а не копируем один раз при инициализации — иначе правки в GameSettings
# (или в ресурсе .tres) не будут подхватываться без перезапуска.
var HAPPINESS_DRAIN_PER_1K_RECRUITS: float:
    get:
        return settings.HAPPINESS_DRAIN_PER_1K_RECRUITS

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
    _build_safe_provinces_cache()

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

    # Размазываем обработку стран по кадрам, см. AI_COUNTRIES_PER_FRAME выше.
    if _ai_day_in_progress:
        _process_ai_day_batch()

# ── Ежедневный тик (раздаёт работу по модулям) ──────────────────────────────
# Больше НЕ обрабатывает страны синхронно сам — только готовит очередь.
# Реальная обработка идёт в _process_ai_day_batch() порциями по кадрам,
# см. блок "ОПТИМИЗАЦИЯ: размазывание дневного тика ИИ по нескольким кадрам".
func _on_day_passed(_date: Dictionary) -> void:
    # Если предыдущая дневная очередь почему-то не успела доработать (не
    # должно происходить при разумном AI_COUNTRIES_PER_FRAME, но на всякий
    # случай) — доигрываем её остаток синхронно, чтобы не потерять тик
    # какой-то стране, и только потом начинаем новый день.
    if _ai_day_in_progress and not _pending_ai_countries.is_empty():
        for country in _pending_ai_countries:
            if ProvinceRegistry.countries_data.has(country):
                _process_country_day(country, _pending_ai_date)
        _pending_ai_countries.clear()

    # Снимок ключей: обработка одной страны (бой/уничтожение) может стереть
    # ДРУГУЮ страну из countries_data прямо во время этого тика — итерация
    # по живому словарю в такой ситуации небезопасна и может пропустить
    # часть стран.
    _pending_ai_countries = ProvinceRegistry.countries_data.keys().duplicate()
    _pending_ai_date = _date
    _ai_day_in_progress = true

## Обрабатывает до AI_COUNTRIES_PER_FRAME стран из очереди этого дня.
## Вызывается каждый кадр из _process(), пока очередь не опустеет.
##
## ВРЕМЕННЫЙ ПРОФИЛИРОВЩИК: печатает в консоль (Output), сколько миллисекунд
## занял КАЖДЫЙ отдельный вызов _process_country_day() для КАЖДОЙ страны,
## если это дольше PROFILE_THRESHOLD_MS. Так сразу видно: (а) виновата ли
## конкретная страна (и какая) или тормозит "размазанно" много стран сразу,
# (б) сколько реально миллисекунд уходит — это уже не гадание "фриз есть/нет",
## а конкретные цифры. Убрать этот блок (или PROFILE_AI_DAY = false) после
## того, как источник найден.
const PROFILE_AI_DAY := true
const PROFILE_THRESHOLD_MS := 4.0

func _process_ai_day_batch() -> void:
    var processed := 0
    while processed < AI_COUNTRIES_PER_FRAME and not _pending_ai_countries.is_empty():
        var country: String = _pending_ai_countries.pop_back()
        processed += 1
        if not ProvinceRegistry.countries_data.has(country):
            continue  # страна была уничтожена раньше в этом же дне — пропускаем

        if PROFILE_AI_DAY:
            var t0 := Time.get_ticks_usec()
            _process_country_day(country, _pending_ai_date)
            var elapsed_ms := (Time.get_ticks_usec() - t0) / 1000.0
            if elapsed_ms >= PROFILE_THRESHOLD_MS:
                var n_provinces := get_country_provinces(country).size()
                var n_armies := DivisionManager.get_country_provinces_with_armies(country).size()
                print("[AI PROFILE] %s: %.2f ms (провинций=%d, провинций_с_армиями=%d)" % [country, elapsed_ms, n_provinces, n_armies])
        else:
            _process_country_day(country, _pending_ai_date)

    if _pending_ai_countries.is_empty():
        _ai_day_in_progress = false
        var t0 := Time.get_ticks_usec()
        _finish_ai_day()
        if PROFILE_AI_DAY:
            var elapsed_ms := (Time.get_ticks_usec() - t0) / 1000.0
            if elapsed_ms >= PROFILE_THRESHOLD_MS:
                print("[AI PROFILE] _finish_ai_day (население/кэш): %.2f ms" % elapsed_ms)

## Вся дневная логика ОДНОЙ страны — раньше было телом цикла в _on_day_passed().
func _process_country_day(country: String, _date: Dictionary) -> void:
    var current_day: int = int(_date.get("day", 1))

    if country == settings.active_country:
        # Игрок обычно управляется вручную и пропускает весь ИИ-блок.
        # Но если включен чекбокс "AI Army" — обрабатываем его армию
        # точно так же, как это делает обычный ИИ (движение войск),
        # не трогая при этом экономику/дипломатию/закупки игрока.
        if player_ai_army_enabled:
            AIMilitary.process_military_movement(country)
        return

    var c_data = ProvinceRegistry.countries_data[country]

    # 0. Начисляем дневной доход ИИ
    var monthly = c_data.get("monthly_income", 100000.0)
    c_data["balance"] = c_data.get("balance", 0.0) + (monthly / 30.0)

    var country_index: int = int(ProvinceRegistry.country_index.get(country, 0))

    # 1. Быстрые кулдауны
    AIMilitary.tick_recruitment_cooldown(country)
    AIMilitary.tick_fortification_cooldown(country)
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

    # 4.5 Укрепления — раз в 7 дней (сдвиг от экономики, чтобы не биться за баланс в один день)
    if (current_day + country_index + 2) % 7 == 0:
        AIMilitary.process_fortifications(country)

    # 5. Рекрутинг — раз в 3 дня
    if (current_day + country_index) % 3 == 0:
        AIMilitary.process_recruitment(country)

    # 6. Движение войск — каждый день
    AIMilitary.process_military_movement(country)

    # 7. Запуск БПЛА по врагу — раз в 2 дня
    if (current_day + country_index) % 2 == 0:
        AIWeapons.process_uav_strikes(country)

    # 7.5 Запуск ракет по врагу — раз в 5 дней, со сдвигом от БПЛА
    if (current_day + country_index + 1) % 5 == 0:
        AIWeapons.process_missile_strikes(country)

## Выполняется один раз, когда очередь стран этого дня полностью обработана.
func _finish_ai_day() -> void:
    # 8. Обновляем кэш "безопасных" провинций — ЧАНКАМИ, а не полной
    # пересборкой всей карты каждый день.
    #
    # РАНЬШЕ: _build_safe_provinces_cache() чистила и заново собирала кэш
    # ПО ВСЕЙ карте (~10000 провинций) КАЖДЫЙ день — это и было ~11мс,
    # которые не размазывались по кадрам сами по себе (весь _finish_ai_day
    # выполняется одним куском в конце дня, после того как очередь стран
    # опустела).
    #
    # ТЕПЕРЬ: используем ТОТ ЖЕ принцип чанкования, что уже применяется для
    # населения (AIPopulation.process_population() ниже) — обновляем точечно
    # (_refresh_safe_province, O(1) на провинцию) только 1/10 карты за день,
    # ротацией по тому же индексу pop_chunk_index. За ~10 дней кэш полностью
    # проходит по всей карте, как и население. Изменения владения провинций
    # (главный источник "протухания" кэша) и так обновляются точечно и сразу
    # через _on_province_captured -> _refresh_safe_province — чанкование
    # здесь довылавливает более редкий случай (бой начался/закончился без
    # смены владельца), для которого небольшая задержка в пределах дней
    # не критична: это лишь резервный список для refugees, у которых не
    # нашлось безопасной провинции рядом через BFS.
    #
    # ВАЖНО: индекс берём ДО того, как AIPopulation.process_population()
    # его прочитает и провернёт — чтобы оба использовали ОДИН И ТОТ ЖЕ чанк
    # за этот день (не обязательно, но логично и не добавляет отдельного
    # прохода по ещё одному чанку).
    var chunk = pop_chunks[pop_chunk_index]
    for p_id_str in chunk:
        _refresh_safe_province(int(p_id_str))

    # 9. Обсчет населения
    AIPopulation.process_population()

# ── Ежемесячный тик ───────────────────────────────────────────────────────────
func _on_month_passed(_date: Dictionary) -> void:
    for country in ProvinceRegistry.countries_data.keys().duplicate():
        if not ProvinceRegistry.countries_data.has(country):
            continue
        _update_monthly_income(country)

    # Снимок ключей: try_make_peace/аннексия могут уничтожить страну
    # (см. ProvinceRegistry._eliminate_country) прямо в процессе этого цикла.
    for country in ProvinceRegistry.countries_data.keys().duplicate():
        if not ProvinceRegistry.countries_data.has(country):
            continue
        if country == settings.active_country:
            continue
        AIDiplomacy.process_diplomacy(country)
        if not ProvinceRegistry.countries_data.has(country):
            continue  # страна могла быть уничтожена внутри process_diplomacy
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

## Публичная обёртка над _update_monthly_income — форсирует немедленный пересчёт
## monthly_income (а значит и ВВП) страны, не дожидаясь ежемесячного тика.
## Вызывайте её сразу после любого изменения, которое влияет на _calculate_monthly_income
## (сейчас это идеология через tax_mult) — иначе эффект будет виден только через месяц.
func force_recalculate_income(country: String) -> void:
    if not ProvinceRegistry.countries_data.has(country):
        return
    _update_monthly_income(country)

func _calculate_monthly_income(country: String) -> float:
    var c_data    = ProvinceRegistry.countries_data[country]
    var total_pop = _get_country_population(country)
    var ideology  = c_data.get("ideology", "liberalism")
    var tax_mult  = DiplomacyManager.IDEOLOGIES[ideology]["tax"]
    var base_income = float(total_pop) * 1.0 * tax_mult

    # Содержание войск начисляется точечно (O(1)) при найме/потерях через
    # ProvinceRegistry.adjust_monthly_income_for_troops(), которая копит его
    # в "troop_upkeep". Полный пересчёт ОБЯЗАН вычесть накопленный upkeep,
    # иначе он "теряется" при каждом ежемесячном пересчёте дохода
    # (баг: доход после призыва падал, а на следующий месяц откатывался назад).
    var troop_upkeep = float(c_data.get("troop_upkeep", 0.0))

    return base_income - troop_upkeep

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

    # Провинция сменила владельца — старая запись "недостижимого врага" для
    # неё больше не актуальна (расклад сил на карте изменился), пусть при
    # следующей попытке движения армия честно пересчитает BFS заново.
    stuck_army_cooldowns.erase(p_id)

    # Захват провинции почти всегда меняет и её "безопасность" (новый владелец
    # мог тут же начать оккупацию/бой) — сразу актуализируем её в кэше, чтобы
    # он не "протух" за день. Полная пересборка всё равно раз в день ниже.
    _refresh_safe_province(p_id)

## Раз в день (O(provinces)): строим p_id -> true для провинций без активных
## боёв и без оккупации + плоский список этих p_id для быстрого pick_random().
## Используется AIPopulation.find_nearest_safe_province() как фолбэк, когда
## рядом (в радиусе BFS) безопасной провинции не нашлось.
func _build_safe_provinces_cache() -> void:
    safe_provinces_cache.clear()
    safe_provinces_list.clear()
    for p_id_str in ProvinceRegistry.province_data:
        var p_id = int(p_id_str)
        if not CombatManager.active_battles.has(p_id) and not ProvinceRegistry.is_occupied(p_id):
            safe_provinces_cache[p_id] = true
            safe_provinces_list.append(p_id)

## Точечное O(1) обновление одной провинции в кэше (см. _on_province_captured).
func _refresh_safe_province(p_id: int) -> void:
    var is_safe = ProvinceRegistry.province_data.has(p_id) \
        and not CombatManager.active_battles.has(p_id) \
        and not ProvinceRegistry.is_occupied(p_id)

    if is_safe:
        if not safe_provinces_cache.has(p_id):
            safe_provinces_cache[p_id] = true
            safe_provinces_list.append(p_id)
    else:
        if safe_provinces_cache.has(p_id):
            safe_provinces_cache.erase(p_id)
            safe_provinces_list.erase(p_id)

func get_random_neighbor_country(country: String) -> String:
    var neighbors = []
    for p_id in get_country_provinces(country):
        for adj_id in ProvinceRegistry.province_adjacency.get(p_id, []):
            var clean_id = int(adj_id)
            var owner    = ProvinceRegistry.province_data.get(clean_id, {}).get("owner", "")
            if owner != "" and owner != country and ProvinceRegistry.countries_data.has(owner) and not neighbors.has(owner):
                neighbors.append(owner)

    return "" if neighbors.is_empty() else neighbors.pick_random()




## RESET
func reset() -> void:
    factory_cooldowns = {}
    recruitment_cooldowns = {}
    uav_launch_cooldowns = {}
    missile_launch_cooldowns = {}
    stuck_army_cooldowns = {}
    country_provinces_cache = {}
    safe_provinces_cache = {}
    safe_provinces_list = []

    # Сбрасываем очередь размазанного дневного тика ИИ — иначе после
    # рестарта партии могла бы доиграться очередь стран из ПРЕДЫДУЩЕЙ игры.
    _pending_ai_countries = []
    _pending_ai_date = {}
    _ai_day_in_progress = false

    _build_initial_country_cache()
    _build_safe_provinces_cache()

    pop_chunks = []
    for i in range(POP_CHUNKS_COUNT):
        pop_chunks.append([])
    var idx = 0
    for p_id_str in ProvinceRegistry.province_data:
        pop_chunks[idx % POP_CHUNKS_COUNT].append(p_id_str)
        idx += 1
    pop_chunk_index = 0

    # Пересчитываем доход всех стран заново — иначе ВВП/monthly_income
    # остаются "сырыми" дефолтами из countries.json до первого игрового месяца
    for country in ProvinceRegistry.countries_data:
        _update_monthly_income(country)
