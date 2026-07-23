# =============================================================================
# AIManager.gd
# Управляет поведением всех стран кроме активной.
#
# СТРУКТУРА:
#   1. Константы и состояние
#   2. Инициализация и тики
#   3. ЭКОНОМИКА  — строительство фабрик
#   4. ВОЕНКА     — найм войск и движение армий (ежедневно)
#   5. ДИПЛОМАТИЯ — объявление войн, мир, санкции, дрейф отношений (ежемесячно)
#   6. НАСЕЛЕНИЕ  — рост, потери, беженцы
#   7. ТОРГОВЛЯ   — продажа накопленных товаров
#   8. Вспомогательные функции
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
# ПРОБЛЕМА: _get_country_provinces() раньше сканировал ВЕСЬ province_data
# (сейчас ~10000 записей) на каждый вызов, а вызывается он по 3-5 раз на
# КАЖДУЮ страну КАЖДЫЙ день (экономика, рекрутинг, армия, движение войск,
# поиск соседей). Итого O(countries * provinces) вместо O(provinces).
# При 300 провинциях это было незаметно, при 10000 — фризы каждый тик.
#
# РЕШЕНИЕ: один раз в день (O(provinces)) строим индекс "страна -> её
# провинции" и множество "безопасных" провинций (без боёв/оккупации),
# дальше весь день читаем из кэша за O(1)/O(k).

## country -> Array[int] провинций страны. Пересобирается в _rebuild_daily_caches().
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
const FACTORY_BUDGET_FRACTION = 0.6 # ИИ тратит на фабрики до 60% текущего баланса за один заход (было: 1 фабрика на весь баланс)
const MAX_QUEUE_PER_PROVINCE = 5    # максимум фабрик в очереди одной провинции
const RECRUIT_COOLDOWN_DAYS = 5     # раз в 5 дней нанимаем войска
const MIN_RECRUIT_SIZE      = 50    # минимальный размер призыва
const RECRUIT_BUDGET_FRACTION = 0.3 # тратим на армию 30% текущего баланса

# На сколько падает счастье провинции за каждую 1000 набранных солдат
const HAPPINESS_DRAIN_PER_1K_RECRUITS = 0.1

# --- НОВЫЙ ЛИМИТ АРМИИ НА ОСНОВЕ ВВП ---
# Коэффициент пересчёта ВВП в лимит армии (1 солдат на ~14 000 ВВП)
const ARMY_LIMIT_GDP_RATIO = 0.0000714

# --- БПЛА-ПРОГРАММА ИИ ---
# Доля СЕГОДНЯШНЕЙ выработки товаров, которую ИИ каждый день откладывает
# в резерв под дронов ДО того, как _process_trade продаст остаток товаров
# за деньги. Резерв копится изо дня в день и не обнуляется торговлей —
# тратится целиком раз в 6 дней в _process_uav_program().
const UAV_RESERVE_PEACETIME = 0.3   # 30% дневных товаров в резерв в мирное время
const UAV_RESERVE_WARTIME   = 0.6   # 60% дневных товаров в резерв во время войны

const UAV_LAUNCH_COOLDOWN_DAYS  = 4   # раз в 4 дня — новый залп
const UAV_MIN_BATCH_PER_TARGET  = 5   # меньше этого по одной цели не бьём (не распыляемся)
const UAV_MAX_PER_TARGET        = 20  # не тратим на одну провинцию весь запас разом
const UAV_MAX_TARGETS_PER_STRIKE = 3  # бьём максимум по стольким провинциям за раз

# --- РАКЕТНАЯ ПРОГРАММА ИИ ---
# Доля СЕГОДНЯШНЕЙ выработки товаров, которую ИИ каждый день откладывает
# в резерв под ракеты, ДО того как _process_trade продаст остаток товаров за
# деньги. Считается ОДНОВРЕМЕННО с резервом под БПЛА (см. _skim_production_reserves,
# один проход по "products" вместо двух — меньше обращений к Dictionary на страну
# в день, что заметно на большом числе стран). Резерв копится изо дня в день и
# не обнуляется торговлей — тратится целиком раз в MISSILE_ORDER_INTERVAL_DAYS
# дней в _process_missile_program().
const MISSILE_RESERVE_PEACETIME = 0.05  # 5% дневных товаров в резерв в мирное время
const MISSILE_RESERVE_WARTIME   = 0.10  # 10% дневных товаров в резерв во время войны

const MISSILE_ORDER_INTERVAL_DAYS = 7   # раз в 7 дней пробуем купить компанию / оформить заказ ракет

# Удар ракетой полностью сносит фабрики провинции и убивает MISSILE_KILL_RATIO
# войск в ней за ОДИН залп (см. ProvinceRegistry.missile_strike) — в отличие от
# БПЛА тут не нужно копить много ракет на одну цель, хватает 1 ракеты на цель.
const MISSILE_STRIKE_COOLDOWN_DAYS  = 6  # раз в 6 дней — новый ракетный залп
const MISSILE_MAX_TARGETS_PER_STRIKE = 3 # бьём максимум по стольким провинциям за раз (1 ракета на провинцию)

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

# ── Ежедневный тик (Максимально разгруженный) ──────────────────────────────────
func _on_day_passed(_date: Dictionary) -> void:
    # Принудительно приводим день к int
    var current_day: int = int(_date.get("day", 1))

    for country in ProvinceRegistry.countries_data:
        if country == settings.active_country:
            continue
            
        var c_data = ProvinceRegistry.countries_data[country]
        
        # 0. Начисляем дневной доход ИИ
        var monthly = c_data.get("monthly_income", 100000.0)
        c_data["balance"] = c_data.get("balance", 0.0) + (monthly / 30.0)

        # Принудительно приводим индекс страны к int, даже если он прилетел как float
        var country_index: int = int(ProvinceRegistry.country_index.get(country, 0))
        
        # 1. Быстрые кулдауны
        _tick_recruitment_cooldown(country)
        _tick_factory_cooldown(country)
        _tick_uav_launch_cooldown(country)
        _tick_missile_launch_cooldown(country)

        # 2. Резервы под БПЛА и ракеты: КАЖДЫЙ день откладываем часть сегодняшней
        # выработки товаров в накопительные резервы ДО того, как торговля продаст
        # их за деньги (см. _skim_production_reserves — считает оба резерва за
        # один проход по "products"/"war_relations", что дешевле двух отдельных
        # функций на большом числе стран). Раз в N дней тратим накопленное:
        # БПЛА — каждые 6 дней, ракеты — каждые MISSILE_ORDER_INTERVAL_DAYS дней.
        # ВАЖНО: skim должен идти ДО _process_trade() — иначе торговля каждый
        # день продаёт весь склад products в balance и обнуляет его, а дроны
        # и ракеты покупаются именно за products, а не за balance.
        _skim_production_reserves(country)
        if (current_day + country_index) % 6 == 0:
            _process_uav_program(country)
        if (current_day + country_index) % MISSILE_ORDER_INTERVAL_DAYS == 0:
            _process_missile_program(country)

        # 3. Торговля — продажа того, что осталось от товаров после резервов под БПЛА и ракеты
        _process_trade(country)

        # 4. Экономика — раз в 5 дней
        if (current_day + country_index) % 5 == 0:
            _process_economy(country)              

        # 5. Рекрутинг — раз в 3 дня
        if (current_day + country_index) % 3 == 0:
            _process_recruitment(country)          

        # 6. ДВИЖЕНИЕ ВОЙСК — раз в 4 дня
        if (current_day + country_index) % 4 == 0:
            _process_military_movement(country)    

        # 7. Запуск БПЛА по врагу — раз в 2 дня (сам залп ограничен кулдауном выше)
        if (current_day + country_index) % 2 == 0:
            _process_uav_strikes(country)

        # 7.5 Запуск ракет по врагу — раз в 5 дней, со сдвигом от БПЛА, чтобы не
        # бить в один и тот же день (сам залп ограничен кулдауном выше)
        if (current_day + country_index + 1) % 5 == 0:
            _process_missile_strikes(country)

    # 5. Обсчет населения
    _process_population()

# ── Ежемесячный тик ───────────────────────────────────────────────────────────
func _on_month_passed(_date: Dictionary) -> void:
    for country in ProvinceRegistry.countries_data:
        _update_monthly_income(country)

    for country in ProvinceRegistry.countries_data:
        if country == settings.active_country:
            continue
        _process_diplomacy(country)
        _process_relations_drift(country)

# -----------------------------------------------------------------------------
# 3. ЭКОНОМИКА — строительство фабрик
# -----------------------------------------------------------------------------

func _tick_factory_cooldown(country: String) -> void:
    if factory_cooldowns.has(country):
        factory_cooldowns[country] -= 1
        if factory_cooldowns[country] <= 0:
            factory_cooldowns.erase(country)

func _process_economy(country: String) -> void:
    # Ждём кулдауна
    if factory_cooldowns.has(country):
        return

    var c_data   = ProvinceRegistry.countries_data[country]
    var ideology = c_data.get("ideology", "liberalism")
    var eco_mult = DiplomacyManager.IDEOLOGIES[ideology]["eco"]
    var balance  = c_data.get("balance", 0.0)

    var factory_cost = settings.factory_cost * eco_mult

    # Строим только если баланс перекрывает стоимость + резерв
    var required = factory_cost * (1.0 + RESERVE_RATIO)
    if balance < required:
        return

    # Ищем подходящую провинцию
    var candidates = _get_safe_buildable_provinces(country)
    if candidates.is_empty():
        return

    # Раньше ИИ строил ровно 1 фабрику за цикл (тратил минимум денег).
    # Теперь тратим на фабрики намного бОльшую часть баланса за раз — строим
    # столько фабрик, на сколько хватает FACTORY_BUDGET_FRACTION от баланса.
    # Очередь в одной провинции вмещает до 5 фабрик, поэтому распределяем
    # постройки round-robin по провинциям, но позволяем провинции набрать
    # все 5, если бюджет и/или число доступных провинций это требуют.
    var budget = balance * FACTORY_BUDGET_FRACTION
    var affordable = max(1, int(budget / factory_cost))

    # Свободное место в очереди каждой кандидатной провинции
    var queue_room: Dictionary = {}
    for p_id in candidates:
        var p_data = ProvinceRegistry.province_data.get(p_id, {})
        queue_room[p_id] = MAX_QUEUE_PER_PROVINCE - p_data.get("factory_queue", []).size()

    candidates.shuffle()

    var built = 0
    var idx = 0
    var stall = 0
    while built < affordable and stall < candidates.size():
        var target_p = candidates[idx % candidates.size()]
        idx += 1

        if queue_room.get(target_p, 0) <= 0:
            stall += 1
            continue

        if c_data.get("balance", 0.0) < required:
            break

        if ProvinceRegistry.start_factory_construction(target_p, country):
            queue_room[target_p] -= 1
            built += 1
            stall = 0
        else:
            # Провинция почему-то не приняла стройку — больше не пытаемся её использовать
            queue_room[target_p] = 0
            stall += 1

    if built > 0:
        factory_cooldowns[country] = FACTORY_COOLDOWN_DAYS

# Провинции без активных боёв, без оккупации, с очередью < 5
func _get_safe_buildable_provinces(country: String) -> Array:
    var result = []
    for p_id in _get_country_provinces(country):
        if CombatManager.active_battles.has(p_id):
            continue
        if ProvinceRegistry.is_occupied(p_id):
            continue
        var p_data = ProvinceRegistry.province_data.get(p_id, {})
        if p_data.get("factory_queue", []).size() < 5:
            result.append(p_id)
    return result

# -----------------------------------------------------------------------------
# 3.5 БПЛА — своя компания дронов, закупка и удары по фабрикам врага
# -----------------------------------------------------------------------------

func _tick_missile_launch_cooldown(country: String) -> void:
    if missile_launch_cooldowns.has(country):
        missile_launch_cooldowns[country] -= 1
        if missile_launch_cooldowns[country] <= 0:
            missile_launch_cooldowns.erase(country)

func _tick_uav_launch_cooldown(country: String) -> void:
    if uav_launch_cooldowns.has(country):
        uav_launch_cooldowns[country] -= 1
        if uav_launch_cooldowns[country] <= 0:
            uav_launch_cooldowns.erase(country)

## Каждый день откладывает часть СЕГОДНЯШНЕЙ выработки товаров в накопительные
## резервы под дронов и под ракеты — ДО того, как _process_trade продаст остаток
## товаров за деньги. Резервы (c_data["uav_reserve"] / c_data["missile_reserve"])
## не обнуляются торговлей и копятся изо дня в день, пока _process_uav_program /
## _process_missile_program их не потратят на заказ.
## ОБЪЕДИНЕНО с ракетным резервом в один проход (одно чтение "products" и
## "war_relations" вместо двух отдельных функций) — на большом числе стран
## это ощутимо дешевле, чем два раздельных Dictionary-обращения в день на страну.
func _skim_production_reserves(country: String) -> void:
    var c_data = ProvinceRegistry.countries_data[country]
    var stock  = c_data.get("products", 0.0)
    if stock <= 0.0:
        return

    var is_at_war = not ProvinceRegistry.war_relations.get(country, []).is_empty()

    var uav_fraction     = UAV_RESERVE_WARTIME if is_at_war else UAV_RESERVE_PEACETIME
    var missile_fraction = MISSILE_RESERVE_WARTIME if is_at_war else MISSILE_RESERVE_PEACETIME

    var uav_skim     = stock * uav_fraction
    var missile_skim = stock * missile_fraction

    c_data["products"]        = stock - uav_skim - missile_skim
    c_data["uav_reserve"]     = c_data.get("uav_reserve", 0.0) + uav_skim
    c_data["missile_reserve"] = c_data.get("missile_reserve", 0.0) + missile_skim

## Покупка компании БПЛА (один раз) + заказ дронов на накопленный резерв товаров.
func _process_uav_program(country: String) -> void:
    var c_data  = ProvinceRegistry.countries_data[country]
    var balance = c_data.get("balance", 0.0)

    # 1. Если компании ещё нет — покупаем её, если хватает денег + резерв
    if not c_data.get("uav_company", false):
        var company_cost = settings.UAV_COMPANY_COST
        if balance >= company_cost * (1.0 + RESERVE_RATIO):
            c_data["balance"] -= company_cost
            c_data["uav_company"] = true
        # В день покупки заказ дронов не оформляем — резерв продолжает копиться,
        # снова попробуем через 6 дней
        return

    # 2. Компания уже есть — заказываем дроны, если сейчас нет активного заказа
    if ProvinceRegistry.has_active_uav_order(country):
        return

    var uav_cost: float = settings.uav_cost
    if uav_cost <= 0.0:
        return

    # Тратим накопленный за последние ~6 дней резерв товаров на дронов целиком
    var reserve = c_data.get("uav_reserve", 0.0)
    var amount = int(reserve / uav_cost)
    if amount <= 0:
        return

    var cost = amount * uav_cost

    # ВАЖНО: start_uav_order() в ProvinceRegistry проверяет платёжеспособность
    # и списывает деньги именно из countries_data[country]["products"], а не
    # из нашего отдельного "uav_reserve". Резерв мы копили ОТДЕЛЬНО от products
    # (см. _skim_production_reserves), поэтому нужную сумму нужно на секунду вернуть
    # обратно в products — иначе start_uav_order всегда будет проваливать
    # проверку "products < cost", ведь в products к этому моменту почти пусто.
    c_data["products"] = c_data.get("products", 0.0) + cost

    if ProvinceRegistry.start_uav_order(country, amount):
        c_data["uav_reserve"] = reserve - cost
    else:
        # Не получилось (например, нет производственных мощностей) — возвращаем
        # деньги обратно в резерв, чтобы они не потерялись
        c_data["products"] = c_data.get("products", 0.0) - cost

## Удары БПЛА по самым "жирным" (по числу фабрик) провинциям врага.
## Работает только во время войны и только если накоплено достаточно дронов.
func _process_uav_strikes(country: String) -> void:
    if uav_launch_cooldowns.has(country):
        return

    var enemies = ProvinceRegistry.war_relations.get(country, [])
    if enemies.is_empty():
        return

    var c_data   = ProvinceRegistry.countries_data[country]
    var available = int(c_data.get("uav", 0))
    if available < UAV_MIN_BATCH_PER_TARGET:
        return

    var targets = _get_richest_enemy_factory_provinces(enemies, UAV_MAX_TARGETS_PER_STRIKE)
    if targets.is_empty():
        return

    var drones_per_target = min(UAV_MAX_PER_TARGET, available / targets.size())
    if drones_per_target < UAV_MIN_BATCH_PER_TARGET:
        # На все выбранные цели дронов не хватает — бьём только по самой жирной
        targets = [targets[0]]
        drones_per_target = min(UAV_MAX_PER_TARGET, available)
        if drones_per_target < UAV_MIN_BATCH_PER_TARGET:
            return

    var cap_id = int(c_data.get("capital", 0))
    if not settings.province_centers.has(cap_id):
        return
    var start_pos: Vector2 = settings.province_centers[cap_id]

    var total_used = 0
    for target_id in targets:
        if not settings.province_centers.has(target_id):
            continue
        _launch_uav_wave(start_pos, target_id, drones_per_target)
        total_used += drones_per_target

    if total_used > 0:
        c_data["uav"] = available - total_used
        ProvinceRegistry.uav_order_changed.emit(country)
        uav_launch_cooldowns[country] = UAV_LAUNCH_COOLDOWN_DAYS

## Спавнит один "залп" дронов (тот же visual-скрипт, что и у игрока в uav_menu.gd),
## который долетает до цели и сам вызывает ProvinceRegistry.destroy_factory().
func _launch_uav_wave(start_pos: Vector2, target_id: int, amount: int) -> void:
    if not is_instance_valid(Map):
        return

    var drone = Sprite2D.new()
    drone.set_script(UAVDroneScript)
    drone.position    = start_pos
    drone.target_pos  = settings.province_centers[target_id]
    drone.target_p_id = target_id
    drone.amount      = amount

    Map.add_child(drone)

## Вражеские провинции (по всем врагам страны), отсортированные по убыванию
## количества фабрик — то есть самые "жирные" промышленные цели.
## Возвращает список province_id длиной не более max_count.
func _get_richest_enemy_factory_provinces(enemies: Array, max_count: int) -> Array:
    var candidates: Array = []  # [{"id": p_id, "factories": n}]

    for enemy in enemies:
        for p_id in _get_country_provinces(enemy):
            var p_data   = ProvinceRegistry.province_data.get(p_id, {})
            var factories = int(p_data.get("factories", 0))
            if factories > 0:
                candidates.append({"id": p_id, "factories": factories})

    candidates.sort_custom(func(a, b): return a["factories"] > b["factories"])

    var result: Array = []
    for entry in candidates:
        result.append(entry["id"])
        if result.size() >= max_count:
            break
    return result

# -----------------------------------------------------------------------------
# 3.6 РАКЕТЫ — своя ракетная компания, закупка, производство и удары ракетами
# -----------------------------------------------------------------------------
# Резерв под ракеты (5% вне войны / 10% во время войны) считается вместе с
# резервом под БПЛА в одной функции _skim_production_reserves() (см. раздел 3.5).

## Покупка ракетной компании (один раз) + заказ ракет на накопленный резерв товаров.
## Полностью зеркалит _process_uav_program(), только с ракетными полями/стоимостями.
func _process_missile_program(country: String) -> void:
    var c_data  = ProvinceRegistry.countries_data[country]
    var balance = c_data.get("balance", 0.0)

    # 1. Если компании ещё нет — покупаем её, если хватает денег + резерв
    if not c_data.get("missile_company", false):
        var company_cost = settings.MISSILE_COMPANY_COST
        if balance >= company_cost * (1.0 + RESERVE_RATIO):
            c_data["balance"] -= company_cost
            c_data["missile_company"] = true
        # В день покупки заказ ракет не оформляем — резерв продолжает копиться,
        # снова попробуем через MISSILE_ORDER_INTERVAL_DAYS дней
        return

    # 2. Компания уже есть — заказываем ракеты, если сейчас нет активного заказа
    if ProvinceRegistry.has_active_missile_order(country):
        return

    var missile_cost: float = settings.missile_cost
    if missile_cost <= 0.0:
        return

    # Тратим накопленный за последние ~MISSILE_ORDER_INTERVAL_DAYS дней резерв
    # товаров на ракеты целиком
    var reserve = c_data.get("missile_reserve", 0.0)
    var amount = int(reserve / missile_cost)
    if amount <= 0:
        return

    var cost = amount * missile_cost

    # ВАЖНО: start_missile_order() в ProvinceRegistry проверяет платёжеспособность
    # и списывает деньги именно из countries_data[country]["products"], а не
    # из нашего отдельного "missile_reserve". Резерв мы копили ОТДЕЛЬНО от
    # products (см. _skim_production_reserves), поэтому нужную сумму нужно на
    # секунду вернуть обратно в products — иначе start_missile_order всегда
    # будет проваливать проверку "products < cost", ведь в products к этому
    # моменту почти пусто.
    c_data["products"] = c_data.get("products", 0.0) + cost

    if ProvinceRegistry.start_missile_order(country, amount):
        c_data["missile_reserve"] = reserve - cost
    else:
        # Не получилось (например, нет производственных мощностей — ВВП
        # слишком мал) — возвращаем деньги обратно в резерв, чтобы они не
        # потерялись
        c_data["products"] = c_data.get("products", 0.0) - cost

## Ракетные удары по самым "жирным" (по числу фабрик) провинциям врага —
## та же логика выбора целей, что и у БПЛА (переиспользуем
## _get_richest_enemy_factory_provinces). В отличие от БПЛА ракета не несёт
## "amount": один залп missile_strike() сразу сносит ВСЕ фабрики провинции и
## убивает MISSILE_KILL_RATIO войск в ней (см. ProvinceRegistry.missile_strike),
## поэтому копить много ракет на одну цель не нужно — хватает 1 ракеты на цель,
## и мы просто бьём по нескольким целям сразу (до MISSILE_MAX_TARGETS_PER_STRIKE).
## Работает только во время войны и только если есть хотя бы 1 ракета в запасе.
func _process_missile_strikes(country: String) -> void:
    if missile_launch_cooldowns.has(country):
        return

    var enemies = ProvinceRegistry.war_relations.get(country, [])
    if enemies.is_empty():
        return

    var c_data   = ProvinceRegistry.countries_data[country]
    var available = int(c_data.get("missile", 0))
    if available < 1:
        return

    var max_targets = min(MISSILE_MAX_TARGETS_PER_STRIKE, available)
    var targets = _get_richest_enemy_factory_provinces(enemies, max_targets)
    if targets.is_empty():
        return

    var cap_id = int(c_data.get("capital", 0))
    if not settings.province_centers.has(cap_id):
        return
    var start_pos: Vector2 = settings.province_centers[cap_id]

    var total_used = 0
    for target_id in targets:
        if not settings.province_centers.has(target_id):
            continue
        _launch_missile_wave(start_pos, target_id)
        total_used += 1

    if total_used > 0:
        c_data["missile"] = available - total_used
        ProvinceRegistry.missile_order_changed.emit(country)
        missile_launch_cooldowns[country] = MISSILE_STRIKE_COOLDOWN_DAYS

## Спавнит одну ракету (тот же visual-скрипт, что и у игрока в missile_menu.gd),
## которая долетает до цели и сама вызывает ProvinceRegistry.missile_strike().
func _launch_missile_wave(start_pos: Vector2, target_id: int) -> void:
    if not is_instance_valid(Map):
        return

    var target_pos: Vector2 = settings.province_centers[target_id]

    var missile = Sprite2D.new()
    missile.set_script(MissileScript)
    missile.start_pos    = start_pos
    missile.target_pos   = target_pos
    missile.control_pos  = MissileLinesLayer.compute_arc_control(start_pos, target_pos)
    missile.target_p_id  = target_id

    Map.add_child(missile)

# -----------------------------------------------------------------------------
# 4. ВОЕНКА — найм войск и движение армий
# -----------------------------------------------------------------------------

func _tick_recruitment_cooldown(country: String) -> void:
    if recruitment_cooldowns.has(country):
        recruitment_cooldowns[country] -= 1
        if recruitment_cooldowns[country] <= 0:
            recruitment_cooldowns.erase(country)

func _process_recruitment(country: String) -> void:
    # 1. Проверка кулдауна
    if recruitment_cooldowns.has(country):
        return

    var c_data   = ProvinceRegistry.countries_data[country]
    var ideology = c_data.get("ideology", "liberalism")
    var mil_mult = DiplomacyManager.IDEOLOGIES[ideology]["mil"]
    var balance  = c_data.get("balance", 0.0)

    # 2. Расчёт лимита армии (снимается во время войны)
    var total_soldiers = _get_country_total_soldiers(country)
    var is_at_war = not ProvinceRegistry.war_relations.get(country, []).is_empty()
    var army_limit = 1e9 if is_at_war else _get_army_limit(country)   # огромное число во время войны

    if total_soldiers >= army_limit:
        return

    # 3. Поиск лучшей провинции для найма
    var best_p_id = _get_best_recruitment_province(country)
    if best_p_id == -1:
        return

    var p_data = ProvinceRegistry.province_data[best_p_id]
    var pop    = p_data.get("population", 0)
    var province_happiness = float(p_data.get("happiness", 50.0))

    # 4. Расчёт желаемого количества (1% населения, но не менее MIN_RECRUIT_SIZE),
    #    урезаем так, чтобы не пробить потолок армии страны
    var desired_amount = max(MIN_RECRUIT_SIZE, int(pop * 0.01))
    desired_amount = min(desired_amount, int(army_limit - total_soldiers))
    if desired_amount < MIN_RECRUIT_SIZE:
        return

    var cost_per_unit = settings.COST_PER_SOLDIER * mil_mult

    # 5. Тратим только 30% текущего баланса
    var available_for_recruitment = balance * RECRUIT_BUDGET_FRACTION
    var affordable_amount = int(available_for_recruitment / cost_per_unit)
    var recruit_amount = min(desired_amount, affordable_amount)

    # 6. Если получается меньше MIN_RECRUIT_SIZE — пропускаем найм
    if recruit_amount < MIN_RECRUIT_SIZE:
        return

    # 7. Списываем деньги и вызываем DivisionManager
    var cost = recruit_amount * cost_per_unit
    c_data["balance"] -= cost
    var local_pos = settings.province_centers.get(best_p_id, Vector2.ZERO)
    DivisionManager.recruit(best_p_id, local_pos, recruit_amount)

    # 8. Призыв истощает счастье провинции
    var happiness_drain = (float(recruit_amount) / 1000.0) * HAPPINESS_DRAIN_PER_1K_RECRUITS
    p_data["happiness"] = max(0.0, province_happiness - happiness_drain)

    # 9. Устанавливаем кулдаун
    recruitment_cooldowns[country] = RECRUIT_COOLDOWN_DAYS

## Провинция с максимальным населением (без боёв, оккупации и сильно просевшего счастья)
func _get_best_recruitment_province(country: String) -> int:
    var best_id  = -1
    var best_pop = -1
    var country_happiness = ProvinceRegistry.get_country_happiness(country)

    for p_id in _get_country_provinces(country):
        if CombatManager.active_battles.has(p_id):
            continue
        if ProvinceRegistry.is_occupied(p_id):
            continue

        var p_data = ProvinceRegistry.province_data.get(p_id, {})
        var province_happiness = float(p_data.get("happiness", 50.0))

        # Если счастье провинции отстаёт от среднего по стране на 10+ - она больше не "лучшая",
        # идём дальше перебирать остальные провинции
        if country_happiness - province_happiness >= 10.0:
            continue

        var pop = p_data.get("population", 0)
        if pop > best_pop:
            best_pop = pop
            best_id  = p_id

    return best_id

## Максимальный размер армии для страны (на основе ВВП и идеологии)
func _get_army_limit(country: String) -> int:
    var c_data = ProvinceRegistry.countries_data[country]
    var factories = c_data.get("factories", 0)
    var monthly_income = c_data.get("monthly_income", 0.0)
    var gdp = (factories * settings.product_cost + monthly_income) * 12.0
    var ideology = c_data.get("ideology", "liberalism")
    var mil_mult = DiplomacyManager.IDEOLOGIES[ideology]["mil"]
    var limit_float = gdp * ARMY_LIMIT_GDP_RATIO * mil_mult
    return int(limit_float)

## Движение армий во время войны (вызывается ежедневно)
## Атакуем только пограничные провинции врага (соседствующие с нашей территорией)
## и равномерно распределяем удары по всей линии фронта, чтобы наступление
## продвигалось не в одну точку, а по всему фронту сразу.
## Дивизии страны двигаются по этим же правилам независимо от того, стоят они
## на суше или в морской провинции (например, после высадки или отступления) —
## никакого отдельного "морского" поведения нет.
func _process_military_movement(country: String) -> void:
    var enemies = ProvinceRegistry.war_relations.get(country, [])
    if enemies.is_empty():
        return

    # "Своя" территория для военных целей = собственные провинции + провинции
    # контролёра (сюзерена) + провинции марионеток. Благодаря этому армии могут
    # стоять и перемещаться в т.ч. с территории контролирующей/подконтрольной страны.
    var own_provinces = _get_allied_territory_provinces(country)
    var own_set: Dictionary = {}
    for p in own_provinces:
        own_set[p] = true

    # Линия фронта: вражеские провинции, граничащие с нашей территорией
    # (включая территорию контролёра/марионеток)
    var frontier_targets = _get_frontier_enemy_provinces(enemies, own_set)
    
    # ФИКС: Если сухопутной границы нет, добавляем все провинции врагов 
    # для морских атак/высадок
    if frontier_targets.is_empty():
        for enemy in enemies:
            frontier_targets.append_array(_get_country_provinces(enemy))
            
        if frontier_targets.is_empty():
            return

    # Провинции, где физически стоят дивизии страны — это своя территория ПЛЮС
    # любая другая провинция (включая море), где сейчас есть её дивизии.
    # Так дивизия, оказавшаяся в море, обрабатывается точно так же, как обычная
    # армия на суше, без отдельных функций и кулдаунов.
    var provinces_with_armies: Dictionary = {}
    for p in own_provinces:
        provinces_with_armies[p] = true
    for p_id in DivisionManager.armies.keys():
        for army in DivisionManager.armies[p_id]:
            if is_instance_valid(army) and army.division_owner == country:
                provinces_with_armies[p_id] = true
                break

    # Счётчик уже назначенных в этом тике целей — для равномерного распределения удара
    var assigned_count: Dictionary = {}

    for p_id in provinces_with_armies:
        if CombatManager.active_battles.has(p_id):
            continue

        # Если в провинции скопилось слишком много дивизий страны — объединяем их
        # в одну, чтобы не таскать по фронту толпу мелких армий
        var own_division_count = 0
        for army_check in DivisionManager.armies.get(p_id, []):
            if is_instance_valid(army_check) and army_check.division_owner == country:
                own_division_count += 1
        if own_division_count > 4:
            DivisionManager.merge_divisions(p_id)

        # Двигаем армии страны country — они могут физически находиться
        # на своей территории, территории контролёра/марионетки или в море
        for army in DivisionManager.armies.get(p_id, []):
            if not is_instance_valid(army) or army.division_owner != country or army.is_moving:
                continue

            # Приграничные вражеские провинции, соседствующие именно с этой армией
            var adjacent_targets = []
            for adj_id in ProvinceRegistry.province_adjacency.get(p_id, []):
                var t_id = int(adj_id)
                if frontier_targets.has(t_id):
                    adjacent_targets.append(t_id)

            var target_p_id = -1
            if not adjacent_targets.is_empty():
                target_p_id = _pick_least_assigned_target(adjacent_targets, assigned_count)
            else:
                # Армия не граничит напрямую с фронтом — направляем её на самый
                # "слабоатакуемый" участок фронта, чтобы наступление подтягивалось
                # равномерно по всей линии
                target_p_id = _pick_least_assigned_target(frontier_targets, assigned_count)

            if target_p_id == -1:
                continue

            assigned_count[target_p_id] = assigned_count.get(target_p_id, 0) + 1

            var target_pos = settings.province_centers.get(target_p_id, Vector2.ZERO)
            army.start_movement_to(target_p_id, target_pos)

## Провинции страны + провинции её контролёра (сюзерена) + провинции всех её
## марионеток. Используется для военных передвижений: армии могут находиться
## и перемещаться по территории обеих сторон вассальных отношений.
func _get_allied_territory_provinces(country: String) -> Array:
    var result: Array = _get_country_provinces(country).duplicate()
    var seen: Dictionary = {}
    for p in result:
        seen[p] = true

    var c_data = ProvinceRegistry.countries_data.get(country, {})

    var controller = c_data.get("controller", "")
    if controller != "" and controller != country:
        for p in _get_country_provinces(controller):
            if not seen.has(p):
                seen[p] = true
                result.append(p)

    for puppet in c_data.get("control", []):
        if puppet == "" or puppet == country:
            continue
        for p in _get_country_provinces(puppet):
            if not seen.has(p):
                seen[p] = true
                result.append(p)

    return result

## Вражеские провинции, граничащие хотя бы с одной нашей провинцией
func _get_frontier_enemy_provinces(enemies: Array, own_set: Dictionary) -> Array:
    # enemies.has(owner) внутри цикла по всем соседям всех своих провинций
    # был O(n) поиском по массиву — при многосторонних войнах заметно.
    # Множество на Dictionary даёт O(1) проверку.
    var enemy_set: Dictionary = {}
    for e in enemies:
        enemy_set[e] = true

    var result = []
    var seen: Dictionary = {}
    for p_id in own_set:
        for adj_id in ProvinceRegistry.province_adjacency.get(p_id, []):
            var t_id = int(adj_id)
            if seen.has(t_id):
                continue
            var owner = ProvinceRegistry.province_data.get(t_id, {}).get("owner", "")
            if owner != "" and owner != ProvinceRegistry.SEA_OWNER and enemy_set.has(owner):
                seen[t_id] = true
                result.append(t_id)
    return result

## Выбирает цель с наименьшим числом уже направленных на неё армий в этом тике
## (перемешиваем, чтобы при равенстве счёта не всегда выбирать одну и ту же провинцию)
func _pick_least_assigned_target(candidates: Array, assigned_count: Dictionary) -> int:
    var shuffled = candidates.duplicate()
    shuffled.shuffle()

    var best_id    = -1
    var best_count = INF
    for t_id in shuffled:
        var c = assigned_count.get(t_id, 0)
        if c < best_count:
            best_count = c
            best_id    = t_id
    return best_id

# -----------------------------------------------------------------------------
# 5. ДИПЛОМАТИЯ
# -----------------------------------------------------------------------------

func _process_diplomacy(country: String) -> void:
    var c_data  = ProvinceRegistry.countries_data[country]
    var enemies = ProvinceRegistry.war_relations.get(country, [])

    _process_sanctions(country)

    if not enemies.is_empty():
        _try_make_peace(country, c_data, enemies)
        return  # воюем — новые войны не объявляем

    _try_declare_war(country, c_data)

func _try_make_peace(country: String, c_data: Dictionary, enemies: Array) -> void:
    var ideology    = c_data.get("ideology", "liberalism")
    var peace_mult  = DiplomacyManager.IDEOLOGIES[ideology]["peace"]

    if randf() < (0.10 * peace_mult):
        var target_enemy = enemies.pick_random()
        if target_enemy != settings.active_country:
            ProvinceRegistry.annex_all_occupied_by(country)
            ProvinceRegistry.annex_all_occupied_by(target_enemy)
            ProvinceRegistry.end_war(country, target_enemy)

func _try_declare_war(country: String, c_data: Dictionary) -> void:
    var ideology          = c_data.get("ideology", "liberalism")
    var war_mult          = DiplomacyManager.IDEOLOGIES[ideology]["war"]
    var neighbor          = _get_random_neighbor_country(country)

    if neighbor == "" or neighbor == country:
        return

    var relations         = DiplomacyManager.get_relation(country, neighbor)
    var neighbor_ideology = ProvinceRegistry.countries_data[neighbor].get("ideology", "liberalism")

    # Расчёт базового шанса в зависимости от отношений
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
func _process_sanctions(country: String) -> void:
    var c_data       = ProvinceRegistry.countries_data[country]
    var sanctioned_by = c_data.get("sanctioned_by", {})
    if sanctioned_by.is_empty():
        return

    for attacker in sanctioned_by:
        var attacker_data = ProvinceRegistry.countries_data.get(attacker, {})
        if not attacker_data.get("sanctioned_by", {}).has(country):
            var sanction_cost = 150000.0
            if c_data.get("balance", 0.0) >= sanction_cost * (1.0 + RESERVE_RATIO):
                DiplomacyManager.toggle_sanctions(country, attacker, sanction_cost)

## Ежемесячный дрейф отношений
func _process_relations_drift(country: String) -> void:
    var neighbor = _get_random_neighbor_country(country)
    if neighbor == "" or neighbor == country:
        return

    var ideology          = ProvinceRegistry.countries_data[country].get("ideology", "liberalism")
    var neighbor_ideology = ProvinceRegistry.countries_data[neighbor].get("ideology", "liberalism")

    var drift: float = randf_range(-2.0, 3.0) if ideology == neighbor_ideology else randf_range(-5.0, 2.0)

    DiplomacyManager.change_relation(country, neighbor, drift)

# -----------------------------------------------------------------------------
# 6. НАСЕЛЕНИЕ — рост, потери, беженцы (Оптимизация чанками)
# -----------------------------------------------------------------------------

func _process_population() -> void:
    var chunk = pop_chunks[pop_chunk_index]
    pop_chunk_index = (pop_chunk_index + 1) % POP_CHUNKS_COUNT
    
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
                    _distribute_refugees(p_id, loss, migration)
            elif ProvinceRegistry.is_occupied(p_id):
                var loss = int(current * 0.003)
                if loss > 0:
                    migration[p_id_str] = migration.get(p_id_str, 0) - loss
                    _distribute_refugees(p_id, loss, migration)
            else:
                var growth = int(current * 0.001)
                if growth > 0:
                    migration[p_id_str] = migration.get(p_id_str, 0) + growth

    # Применяем изменения населения только для выбранного чанка
    for p_id_str in migration:
        if ProvinceRegistry.province_data.has(p_id_str):
            var new_pop = int(ProvinceRegistry.province_data[p_id_str].get("population", 0)) + migration[p_id_str]
            ProvinceRegistry.province_data[p_id_str]["population"] = max(0, new_pop)

func _distribute_refugees(from_p_id: int, amount: int, migration_dict: Dictionary) -> void:
    var safe_p_id = _find_nearest_safe_province(from_p_id)
    if safe_p_id != -1:
        var safe_key = safe_p_id
        migration_dict[safe_key] = migration_dict.get(safe_key, 0) + amount

func _is_province_safe(p_id: int) -> bool:
    return not CombatManager.active_battles.has(p_id) and not ProvinceRegistry.is_occupied(p_id)

const MAX_REFUGEE_SEARCH_HOPS = 3

func _find_nearest_safe_province(start_p_id: int) -> int:
    var queue = [start_p_id]
    var visited = { start_p_id: true }
    var hops = 0
    var q_idx = 0

    while q_idx < queue.size() and hops < MAX_REFUGEE_SEARCH_HOPS:
        var level_size = queue.size() - q_idx
        for i in range(level_size):
            var current_id = queue[q_idx]
            q_idx += 1

            if current_id != start_p_id and _is_province_safe(current_id):
                return current_id

            for adj_id in ProvinceRegistry.province_adjacency.get(current_id, []):
                var next_id = int(adj_id)
                if not visited.has(next_id):
                    visited[next_id] = true
                    queue.append(next_id)
        hops += 1

    # Если рядом безопасной провинции нет, ищем её рандомом (максимум 15 попыток)
    var all_keys = ProvinceRegistry.province_data.keys()  # ← Array, а не Dictionary
    if all_keys.is_empty():
        return -1

    for i in range(15):
        var rand_key = all_keys.pick_random()             # ← теперь pick_random() работает
        var rand_id = int(rand_key)
        if _is_province_safe(rand_id):
            return rand_id

    return -1

# -----------------------------------------------------------------------------
# 7. ТОРГОВЛЯ — продажа накопленных товаров
# -----------------------------------------------------------------------------

func _process_trade(country: String) -> void:
    var c_data  = ProvinceRegistry.countries_data[country]
    var stock   = c_data.get("products", 0.0)
    if stock <= 0.0:
        return 

    var sanctions    = c_data.get("sanctions", 0.0)
    var actual_price = settings.product_cost * (1.0 - (sanctions / 100.0))

    c_data["products"] = 0.0
    c_data["balance"]  = c_data.get("balance", 0.0) + stock * actual_price

# -----------------------------------------------------------------------------
# 8. ДОХОД — начисление в реальном времени
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
# 8. ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
# -----------------------------------------------------------------------------

func _get_country_population(country: String) -> int:
    var total = 0
    for p_id in _get_country_provinces(country):
        total += int(ProvinceRegistry.province_data.get(p_id, {}).get("population", 0))
    return total

## Суммарная численность войск страны (по всем её провинциям)
func _get_country_total_soldiers(country: String) -> int:
    var total := 0
    for p_id in _get_country_provinces(country):
        for circle in DivisionManager.armies.get(p_id, []):
            if is_instance_valid(circle) and circle.division_owner == country:
                total += circle.soldiers
    return total

## O(1) — читает готовый индекс, собранный в _rebuild_daily_caches().
func _get_country_provinces(country: String) -> Array:
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
    # Убираем провинцию у старого хозяина
    for country in country_provinces_cache:
        country_provinces_cache[country].erase(p_id)
    
    # Добавляем новому
    if new_owner != "":
        if not country_provinces_cache.has(new_owner):
            country_provinces_cache[new_owner] = []
        country_provinces_cache[new_owner].append(p_id)

func _get_random_neighbor_country(country: String) -> String:
    var neighbors = []
    for p_id in _get_country_provinces(country):
        for adj_id in ProvinceRegistry.province_adjacency.get(p_id, []):
            var clean_id = int(adj_id)
            var owner    = ProvinceRegistry.province_data.get(clean_id, {}).get("owner", "")
            # ВАЖНО: проверяем countries_data.has(owner), а не просто owner != "" —
            # иначе owner == "sea" (морские провинции) может попасть сюда как
            # "страна-сосед", а её нет в countries_data → падение при обращении
            # к ProvinceRegistry.countries_data[neighbor] в _try_declare_war/_process_relations_drift.
            if owner != "" and owner != country and ProvinceRegistry.countries_data.has(owner) and not neighbors.has(owner):
                neighbors.append(owner)

    return "" if neighbors.is_empty() else neighbors.pick_random()
