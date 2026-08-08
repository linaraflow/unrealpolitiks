extends Control

@onready var panel: Control = $NotificationPanel
@onready var close_button: Button = $NotificationPanel/TopPanel/CloseButton
@onready var list: VBoxContainer = $NotificationPanel/ScrollContainer/List

const SLIDE_OFFSET := 325.0
const NOTIFICATION_LIFETIME := 20.0  # сек, 0 — не исчезает само

var is_closed := false
var _base_x: float

func _ready() -> void:
    hide()
    
    _base_x = panel.position.x
    close_button.pressed.connect(_on_close_pressed)

    ProvinceRegistry.war_declared.connect(_on_war_declared)
    ProvinceRegistry.war_ended.connect(_on_war_ended)
    DiplomacyManager.sanctions_imposed.connect(_on_sanctions_imposed)
    DiplomacyManager.sanctions_removed.connect(_on_sanctions_removed)
    DiplomacyManager.regime_collapsed.connect(_on_regime_collapsed)

func _on_close_pressed() -> void:
    is_closed = !is_closed
    var target_x = (_base_x + SLIDE_OFFSET) if is_closed else _base_x

    close_button.text = "<" if is_closed else ">"

    var tween := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
    tween.tween_property(panel, "position:x", target_x, 0.35)

## Приводит owner_id к виду ключа локализации CTRY_<...> (родительный падеж),
## как в DivisionManager.gd / statistics_menu.gd — переиспользуем тот же CSV.
func _ctry_key(owner_id: String) -> String:
    return owner_id.replace(" ", "_").replace("'", "").replace("-", "_")

func _on_war_declared(attacker: String, defender: String) -> void:
    var title_text := tr("NOTIF_WAR_DECLARED_FMT") % [tr(attacker.to_upper()), tr("CTRY_" + _ctry_key(defender))]
    _add_notification(attacker, defender, title_text, Color(0.85, 0.2, 0.2))

func _on_war_ended(country_a: String, country_b: String) -> void:
    var title_text := tr("NOTIF_PEACE_MADE_FMT") % [tr(country_a.to_upper()), tr(country_b.to_upper())]
    _add_notification(country_a, country_b, title_text, Color(0.3, 0.75, 0.3))

func _on_sanctions_imposed(attacker: String, target: String) -> void:
    # Мировые санкции за агрессию (WORLD_SANCTION_KEY) в уведомлениях не показываем
    if attacker == DiplomacyManager.WORLD_SANCTION_KEY:
        return
    var title_text := tr("NOTIF_SANCTIONS_IMPOSED_FMT") % [tr(attacker.to_upper()), tr("CTRY_" + _ctry_key(target))]
    _add_notification(attacker, target, title_text, Color(0.85, 0.65, 0.15))

func _on_sanctions_removed(attacker: String, target: String) -> void:
    # Мировые санкции за агрессию (WORLD_SANCTION_KEY) в уведомлениях не показываем
    if attacker == DiplomacyManager.WORLD_SANCTION_KEY:
        return
    var title_text := tr("NOTIF_SANCTIONS_REMOVED_FMT") % [tr(attacker.to_upper()), tr("CTRY_" + _ctry_key(target))]
    _add_notification(attacker, target, title_text, Color(0.55, 0.55, 0.55))

func _on_regime_collapsed(country: String, old_ideology: String, new_ideology: String) -> void:
    _add_single_notification(
        country,
        tr("NOTIF_REGIME_COLLAPSED_FMT") % [tr(country.to_upper()), tr(old_ideology.to_upper()), tr(new_ideology.to_upper())],
        Color(0.6, 0.15, 0.75)
    )

func _add_notification(country_a: String, country_b: String, text: String, accent: Color) -> void:
    var item := _build_item(country_a, country_b, text, accent)
    list.add_child(item)
    list.move_child(item, 0)  # новые сверху

    if NOTIFICATION_LIFETIME > 0.0:
        var timer := get_tree().create_timer(NOTIFICATION_LIFETIME)
        timer.timeout.connect(func():
            if is_instance_valid(item):
                _remove_item(item)
        )

## Уведомление про событие, которое касается ОДНОЙ страны (не пары), например свержение режима.
func _add_single_notification(country: String, text: String, accent: Color) -> void:
    var item := _build_single_item(country, text, accent)
    list.add_child(item)
    list.move_child(item, 0)

    if NOTIFICATION_LIFETIME > 0.0:
        var timer := get_tree().create_timer(NOTIFICATION_LIFETIME)
        timer.timeout.connect(func():
            if is_instance_valid(item):
                _remove_item(item)
        )

func _remove_item(item: Control) -> void:
    var tween := create_tween()
    tween.tween_property(item, "modulate:a", 0.0, 0.25)
    tween.tween_callback(item.queue_free)

func _build_item(country_a: String, country_b: String, text: String, accent: Color) -> Control:
    var root := PanelContainer.new()
    root.custom_minimum_size = Vector2(0, 56)

    var style := StyleBoxFlat.new()
    style.bg_color = Color(0.12, 0.12, 0.14, 0.95)
    style.border_color = accent
    style.set_border_width(SIDE_LEFT, 4)
    style.corner_radius_top_left = 6
    style.corner_radius_top_right = 6
    style.corner_radius_bottom_left = 6
    style.corner_radius_bottom_right = 6
    style.content_margin_left = 8
    style.content_margin_right = 8
    style.content_margin_top = 6
    style.content_margin_bottom = 6
    root.add_theme_stylebox_override("panel", style)

    var hbox := HBoxContainer.new()
    hbox.add_theme_constant_override("separation", 8)
    root.add_child(hbox)

    hbox.add_child(_make_flag(country_a))

    var vbox := VBoxContainer.new()
    vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    vbox.add_theme_constant_override("separation", 2)
    hbox.add_child(vbox)

    var title := Label.new()
    title.text = text
    title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    vbox.add_child(title)

    var date_label := Label.new()
    date_label.text = GameClock.get_date_string()
    date_label.add_theme_font_size_override("font_size", 12)
    date_label.add_theme_color_override("font_color", Color(0.65, 0.65, 0.7))
    vbox.add_child(date_label)

    hbox.add_child(_make_flag(country_b))

    return root

func _build_single_item(country: String, text: String, accent: Color) -> Control:
    var root := PanelContainer.new()
    root.custom_minimum_size = Vector2(0, 56)

    var style := StyleBoxFlat.new()
    style.bg_color = Color(0.12, 0.12, 0.14, 0.95)
    style.border_color = accent
    style.set_border_width(SIDE_LEFT, 4)
    style.corner_radius_top_left = 6
    style.corner_radius_top_right = 6
    style.corner_radius_bottom_left = 6
    style.corner_radius_bottom_right = 6
    style.content_margin_left = 8
    style.content_margin_right = 8
    style.content_margin_top = 6
    style.content_margin_bottom = 6
    root.add_theme_stylebox_override("panel", style)

    var hbox := HBoxContainer.new()
    hbox.add_theme_constant_override("separation", 8)
    root.add_child(hbox)

    hbox.add_child(_make_flag(country))

    var vbox := VBoxContainer.new()
    vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    vbox.add_theme_constant_override("separation", 2)
    hbox.add_child(vbox)

    var title := Label.new()
    title.text = text
    title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    vbox.add_child(title)

    var date_label := Label.new()
    date_label.text = GameClock.get_date_string()
    date_label.add_theme_font_size_override("font_size", 12)
    date_label.add_theme_color_override("font_color", Color(0.65, 0.65, 0.7))
    vbox.add_child(date_label)

    return root

func _make_flag(owner_name: String) -> TextureRect:
    var rect := TextureRect.new()
    rect.custom_minimum_size = Vector2(32, 22)
    rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER

    var flag_path := "res://assets/flags/" + owner_name + ".png"
    if ResourceLoader.exists(flag_path):
        rect.texture = load(flag_path)
    return rect
