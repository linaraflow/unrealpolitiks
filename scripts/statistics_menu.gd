extends Control

# ──────────────────────────────────────────────────────────────────────────────
# statistics_menu.gd — панель "Внутренняя статистика страны"
#
# Никакого отдельного автолоада — вся статистика считается прямо здесь, по
# сигналам ProvinceRegistry / CombatManager / GameClock.
#
# ВАЖНО: этот Control должен существовать в дереве сцены С НАЧАЛА ИГРЫ (просто
# скрыт через visible = false), а не создаваться заново каждый раз при открытии
# меню — иначе он пропустит сигналы (war_declared и т.д.), пока его не было в
# дереве, и статистика будет неполной.
#
# Структура нод (как в вашей сцене StatisticsMenu):
#   Panel/MarginContainer/VBoxContainer/ScrollContainer/VBoxContainer/WarContainer
#     -> шаблон одной "панельки войны", внутри неё (не важно на какой глубине):
#        AgainLabel, DayLabel, YourLabel, EnemyLabel
#   Panel/MarginContainer/VBoxContainer/FactoriesContainer/BuiltFactories
#   Panel/MarginContainer/VBoxContainer/FactoriesContainer/DestroyedFactories
#   Panel/MarginContainer/VBoxContainer/StrikesContainer/BuiltFactories   (UAV)
#   Panel/MarginContainer/VBoxContainer/StrikesContainer/DestroyedFactories (ракеты)
#     -> в каждой такой панельке два Label: один "число" (любое имя, кроме
#        "Label"), второй статичная подпись, буквально называется "Label".
#        Число ищется автоматически (см. _find_value_label), поэтому не важно,
#        как оно называется внутри (FactoriesLabe, UAVLabel и т.п.)
#
# Если у вас другие пути — поправьте константы ниже, один раз.
# ──────────────────────────────────────────────────────────────────────────────

var settings = preload("res://new_resource.tres")

@onready var _active_wars_count_label: Label = $Panel/MarginContainer/VBoxContainer/HeadContainer/NumberLabel



@onready var _panel: Control = $Panel
@onready var _negotiation_menu = get_node("/root/Game/CanvasLayer/NegotiationMenu")

@onready var _wars_list: Node = $Panel/MarginContainer/VBoxContainer/ScrollContainer/VBoxContainer
@onready var _war_template: Control = $Panel/MarginContainer/VBoxContainer/ScrollContainer/VBoxContainer/WarContainer

@onready var _built_panel: Control = $Panel/MarginContainer/VBoxContainer/FactoriesContainer/BuiltFactories
@onready var _destroyed_panel: Control = $Panel/MarginContainer/VBoxContainer/FactoriesContainer/DestroyedFactories
@onready var _uav_panel: Control = $Panel/MarginContainer/VBoxContainer/StrikesContainer/UAVPanel
@onready var _rockets_panel: Control = $Panel/MarginContainer/VBoxContainer/StrikesContainer/RocketsPanel

# Пул панелек войн: [0] — сам оригинальный WarContainer, дальше — его дубликаты.
# Лишние на данный момент просто прячутся, а не удаляются — чтобы не плодить
# duplicate()/queue_free() при каждом изменении числа войн.
var _war_entries: Array[Control] = []

# country -> {"built": int, "destroyed": int, "uav_received": int, "missile_received": int}
var weekly_stats: Dictionary = {}

# war_key("A|B") -> {"attacker", "defender", "losses": {country:int}, "start_day/month/year"}
var war_stats: Dictionary = {}


func _ready() -> void:
    print("STATS MENU settings id: ", settings.get_instance_id())

    show() # корневой узел всегда должен оставаться видимым, прячем только _panel
    _panel.visible = false

    _war_template.visible = false
    _war_entries = [_war_template]

    GameClock.on_month_passed.connect(_on_month_passed)
    ProvinceRegistry.war_declared.connect(_on_war_declared)
    ProvinceRegistry.war_ended.connect(_on_war_ended)
    ProvinceRegistry.factory_built.connect(_on_factory_built)
    ProvinceRegistry.factory_destroyed.connect(_on_factory_destroyed)
    ProvinceRegistry.uav_strike_landed.connect(_on_uav_strike_landed)
    ProvinceRegistry.missile_strike_landed.connect(_on_missile_strike_landed)
    CombatManager.casualties_inflicted.connect(_on_casualties_inflicted)

    visibility_changed.connect(func():
        if visible:
            _refresh()
        else:
            close_menu()
    )

    # Закрываем панель при нажатии ЛЮБОЙ кнопки в TopMenu (UAV/Missile/Flag/Production и т.д.)
    # Путь ниже — как в uav_menu.gd/missile_menu.gd/negotiation_menu.gd. Если у вас
    # TopMenu лежит по другому пути — поправьте здесь.
    var top_menu = get_node_or_null("/root/Game/CanvasLayer/TopMenu")
    if top_menu:
        _connect_close_on_buttons(top_menu)

    _refresh()


## Открыть/закрыть панель статистики. Вызывайте это из кнопки, где бы она теперь
## ни лежала (сейчас — panel.gd, $HeaderRow/StatisticButton).
func toggle_menu() -> void:
    # ВАЖНО: map.gd:_close_all_menus() (вызывается из restart()) обходит
    # CanvasLayer и делает child.hide() на КОРНЕВОМ узле StatisticsMenu
    # (а не на _panel) — т.к. сам StatisticsMenu это Control, а не Container.
    # Из-за этого после рестарта visible=false остаётся у родителя навсегда,
    # и _panel.visible=true уже ничего не даёт — скрытый родитель не рисует
    # детей. Поэтому здесь всегда возвращаем видимость самому узлу.
    show()
    _panel.visible = not _panel.visible
    if _panel.visible:
        _refresh()


## Закрыть панель статистики (вызывается извне: при входе в режимы БПЛА/ракет/переговоров,
## а также автоматически при нажатии любой кнопки в TopMenu — см. _connect_close_on_buttons)
func close_menu() -> void:
    _panel.visible = false


## Полный сброс статистики (вызывать из map.gd:restart()).
## Обнуляет и войны, и еженедельные цифры, прячет лишние war-панельки из
## пула обратно до одного (оригинального) шаблона и, если панель сейчас
## открыта, сразу перерисовывает её нулями.
func reset() -> void:
    weekly_stats.clear()
    war_stats.clear()

    # Лишние задублированные war-панельки не удаляем (см. комментарий у
    # _war_entries выше — чтобы не плодить duplicate()/queue_free()), просто
    # прячем все, кроме оригинального шаблона, и откатываем пул к [_war_template].
    for entry in _war_entries:
        entry.visible = false
    _war_entries = [_war_template]

    if _active_wars_count_label:
        _active_wars_count_label.text = "0"

    _set_value_label(_built_panel, "+0")
    _set_value_label(_destroyed_panel, "-0")
    _set_value_label(_uav_panel, "0")
    _set_value_label(_rockets_panel, "0")

    if _panel.visible:
        _refresh()


## Рекурсивно подключает close_menu() к сигналу pressed каждой кнопки внутри node.
## Flag исключён: он теперь сам открывает/закрывает статистику через toggle_menu()
## (см. top_menu.gd, _on_flag_button_pressed) — если подключить сюда ещё и close_menu,
## обработчики будут конфликтовать друг с другом.
func _connect_close_on_buttons(node: Node) -> void:
    for child in node.get_children():
        if child is BaseButton and child.name != "Flag" and not child.pressed.is_connected(close_menu):
            child.pressed.connect(close_menu)
        _connect_close_on_buttons(child)


## Страна игрока — всегда актуальная, как во всех остальных скриптах проекта.
func _player_country() -> String:
    return settings.active_country


func _refresh() -> void:
    if _player_country() == "":
        return
    _refresh_wars()
    _refresh_weekly()


# ─── СБОР ДАННЫХ: сигналы ────────────────────────────────────────────────────

func _on_month_passed(_date: Dictionary) -> void:
    weekly_stats.clear()
    _refresh_weekly()


func _on_war_declared(attacker: String, defender: String) -> void:
    var key = _war_key(attacker, defender)
    var date = GameClock.get_date()
    war_stats[key] = {
        "attacker": attacker,
        "defender": defender,
        "losses": {attacker: 0, defender: 0},
        "start_day": date["day"],
        "start_month": date["month"],
        "start_year": date["year"],
    }
    _refresh_wars()


func _on_war_ended(country_a: String, country_b: String) -> void:
    war_stats.erase(_war_key(country_a, country_b))
    _refresh_wars()


func _on_factory_built(_p_id: int, country: String) -> void:
    if country == "":
        return
    _get_weekly(country)["built"] += 1
    _refresh_weekly()


func _on_factory_destroyed(_p_id: int, country: String, amount: int) -> void:
    if country == "" or amount <= 0:
        return
    _get_weekly(country)["destroyed"] += amount
    _refresh_weekly()


func _on_uav_strike_landed(p_id: int) -> void:
    var owner = ProvinceRegistry.province_data.get(p_id, {}).get("owner", "")
    if not ProvinceRegistry._is_real_country_owner(owner):
        return
    _get_weekly(owner)["uav_received"] += 1
    _refresh_weekly()


func _on_missile_strike_landed(p_id: int) -> void:
    var owner = ProvinceRegistry.province_data.get(p_id, {}).get("owner", "")
    if not ProvinceRegistry._is_real_country_owner(owner):
        return
    _get_weekly(owner)["missile_received"] += 1
    _refresh_weekly()


func _on_casualties_inflicted(country: String, amount: int) -> void:
    if amount <= 0:
        return
    for key in war_stats:
        var w: Dictionary = war_stats[key]
        if w["attacker"] == country or w["defender"] == country:
            w["losses"][country] = w["losses"].get(country, 0) + amount
    _refresh_wars()


# ─── ВОЙНЫ: заполнение UI ────────────────────────────────────────────────────

func _refresh_wars() -> void:
    var wars: Array = _get_active_wars(_player_country())

    if _active_wars_count_label:
        _active_wars_count_label.text = str(wars.size())

    # хватает ли у нас панелек в пуле — если нет, дублируем шаблон
    while _war_entries.size() < wars.size():
        var new_entry: Control = _war_template.duplicate()
        _wars_list.add_child(new_entry)
        _war_entries.append(new_entry)

    # прячем лишние
    for i in range(wars.size(), _war_entries.size()):
        _war_entries[i].visible = false

    # заполняем нужные
    for i in range(wars.size()):
        var entry = _war_entries[i]
        entry.visible = true
        _fill_war_entry(entry, wars[i])


## Приводит имя страны (owner_id) к виду ключа локализации CTRY_<...>,
## как в DivisionManager.gd, — чтобы переиспользовать один и тот же CSV.
func _ctry_key(owner_id: String) -> String:
    return owner_id.replace(" ", "_").replace("'", "").replace("-", "_")


func _fill_war_entry(entry: Control, war: Dictionary) -> void:
    var again_label = entry.find_child("AgainLabel", true, false)
    var day_label = entry.find_child("DayLabel", true, false)
    var your_label = entry.find_child("YourLabel", true, false)
    var enemy_label = entry.find_child("EnemyLabel", true, false)
    var negotiation_btn = entry.find_child("Negotiation", true, false)

    if again_label:
        again_label.text = tr("WAR_AGAINST_FMT") % tr("CTRY_" + _ctry_key(war["enemy"]))
    if day_label:
        day_label.text = tr("WAR_DAYS_FMT") % war["days"]
    if your_label:
        your_label.text = _format_number(war["my_losses"])
    if enemy_label:
        enemy_label.text = _format_number(war["enemy_losses"])

    if negotiation_btn:
        # Каждый раз при переиспользовании панельки враг мог поменяться —
        # отвязываем старый обработчик (если был) и вешаем новый с актуальным enemy.
        for callable in negotiation_btn.pressed.get_connections():
            negotiation_btn.pressed.disconnect(callable["callable"])
        negotiation_btn.pressed.connect(_on_negotiation_btn_pressed.bind(war["enemy"]))


## Делает то же самое, что _on_negotiation_pressed() в panel.gd:
## открывает меню переговоров с указанной страной.
func _on_negotiation_btn_pressed(enemy: String) -> void:
    close_menu()
    _negotiation_menu.open_negotiation(enemy)


func _get_active_wars(country: String) -> Array:
    var result: Array = []
    for key in war_stats:
        var w: Dictionary = war_stats[key]
        if w["attacker"] != country and w["defender"] != country:
            continue
        var enemy = w["defender"] if w["attacker"] == country else w["attacker"]
        result.append({
            "enemy": enemy,
            "days": _days_since_start(w),
            "my_losses": int(w["losses"].get(country, 0)),
            "enemy_losses": int(w["losses"].get(enemy, 0)),
        })
    return result


func _days_since_start(w: Dictionary) -> int:
    var d0 = w["start_day"] + w["start_month"] * 30 + w["start_year"] * 360
    var date = GameClock.get_date()
    var d1 = date["day"] + date["month"] * 30 + date["year"] * 360
    return max(0, d1 - d0)


# ─── СТАТИСТИКА ЗА НЕДЕЛЮ: заполнение UI ────────────────────────────────────

func _refresh_weekly() -> void:
    if _player_country() == "":
        return
    var weekly: Dictionary = _get_weekly(_player_country())

    _set_value_label(_built_panel, "+%d" % int(weekly.get("built", 0)))
    _set_value_label(_destroyed_panel, "-%d" % int(weekly.get("destroyed", 0)))
    _set_value_label(_uav_panel, _format_number(weekly.get("uav_received", 0)))
    _set_value_label(_rockets_panel, _format_number(weekly.get("missile_received", 0)))


func _get_weekly(country: String) -> Dictionary:
    if not weekly_stats.has(country):
        weekly_stats[country] = {"built": 0, "destroyed": 0, "uav_received": 0, "missile_received": 0}
    return weekly_stats[country]


## Ищет в панельке "число"-лейбл: любой Label, кроме статичной подписи с именем "Label"
func _set_value_label(panel: Control, text: String) -> void:
    var value_label = _find_value_label(panel)
    if value_label:
        value_label.text = text


func _find_value_label(node: Node) -> Label:
    for child in node.get_children():
        if child is Label and child.name != "Label":
            return child
        var found = _find_value_label(child)
        if found:
            return found
    return null


# ─── ХЕЛПЕРЫ ──────────────────────────────────────────────────────────────────

func _war_key(a: String, b: String) -> String:
    return (a + "|" + b) if a < b else (b + "|" + a)


func _format_number(value: int) -> String:
    return ProvinceRegistry._format_number(value, ".")


func _on_panel_mouse_entered() -> void:
    print("PANEL entered")
    settings.is_mouse_over_ui = true


func _on_panel_mouse_exited() -> void:
    print("PANEL exited")
    settings.is_mouse_over_ui = false
