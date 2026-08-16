extends Control

@export var settings: GameSettings

# Реальный ID страны (владелец провинции), НЕ подлежит переводу — используется
# для settings.active_country и т.д. Отдельно от text, который переводится
# через tr() и показывается игроку (см. set_country()).
var country_id: String = ""

@onready var BLUE = $BLUE
@onready var ProvinceMenu = get_node("/root/Game/CanvasLayer/VBoxContainer/ProvinceMenu")
@onready var DivisionMenu = get_node("/root/Game/CanvasLayer/VBoxContainer/DivisionMenu")
@onready var TopMenu = get_node("/root/Game/CanvasLayer/TopMenu")
@onready var recruit_btn = get_node("/root/Game/CanvasLayer/VBoxContainer/ProvinceMenu/Panel/RecruitButton")
@onready var CountryPanel = get_node("/root/Game/CanvasLayer/VBoxContainer/CountryMenu/Panel")
@onready var NotificationMenu = get_node("/root/Game/CanvasLayer/NotificationMenu")
@onready var fog_button: Button = $PanelContainer/MarginContainer/VBoxContainer/FogContainer/FogButton
@onready var difficulty_option: OptionButton = $PanelContainer/MarginContainer/VBoxContainer/DifficultyContainer/OptionButton
@onready var difficulty_details: RichTextLabel = $PanelContainer/MarginContainer/VBoxContainer/DifficultyContainer/DifficultyDetails
@onready var aggression_slider: HSlider = $PanelContainer/MarginContainer/VBoxContainer/AggressivenessContainer/HSlider
@onready var aggression_value_label: Label = $PanelContainer/MarginContainer/VBoxContainer/AggressivenessContainer/PercentLabel

var fog_button_style_normal: StyleBoxFlat
var fog_button_style_hover: StyleBoxFlat
var fog_button_style_pressed: StyleBoxFlat
var fog_button_style_off: StyleBoxFlat
var fog_button_style_off_hover: StyleBoxFlat
var fog_button_style_off_pressed: StyleBoxFlat
var fog_is_off: bool = false


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
    # Обновление текстов статических узлов интерфейса
    $StartButton.text = tr("START")
    $PanelContainer/MarginContainer/VBoxContainer/FogContainer/Label.text = tr("FOG_OF_WAR")
    $PanelContainer/MarginContainer/VBoxContainer/DifficultyContainer/Label.text = tr("DIFFICULTY")
    $PanelContainer/MarginContainer/VBoxContainer/AggressivenessContainer/Label.text = tr("AGGRESSIVENESS")
    $PanelContainer/MarginContainer/VBoxContainer/AggressivenessContainer/RangeRow/MinLabel.text = tr("PASSIVE")
    $PanelContainer/MarginContainer/VBoxContainer/AggressivenessContainer/RangeRow/MaxLabel.text = tr("RUTHLESS")
    
    BLUE.add_to_group("choose_button")
    # Загружаем JSON
    var file = FileAccess.open("res://scripts/countries.json", FileAccess.READ)
    var json = JSON.parse_string(file.get_as_text())
    file.close()

    # Сохраняем исходные стили кнопки Fog (ON) и готовим "красные" стили для OFF-состояния
    fog_button_style_normal = fog_button.get_theme_stylebox("normal")
    fog_button_style_hover = fog_button.get_theme_stylebox("hover")
    fog_button_style_pressed = fog_button.get_theme_stylebox("pressed")

    fog_button_style_off = fog_button_style_normal.duplicate()
    fog_button_style_off.bg_color = Color(0.75, 0.15, 0.15, 1)

    fog_button_style_off_hover = fog_button_style_off.duplicate()
    fog_button_style_off_hover.bg_color = fog_button_style_off.bg_color.darkened(0.15)

    fog_button_style_off_pressed = fog_button_style_off.duplicate()
    fog_button_style_off_pressed.bg_color = fog_button_style_off.bg_color.darkened(0.3)

    # Стартовое состояние кнопки — Fog ON, синхронизируем с ProvinceRegistry
    # (актуально на случай, если сцена opening переиспользуется/сбрасывается).
    ProvinceRegistry.fog_of_war_enabled = not fog_is_off
    fog_button.text = tr("OFF") if fog_is_off else tr("ON")

    # Заполняем список сложности через tr() и выставляем Standard по умолчанию.
    difficulty_option.clear()
    difficulty_option.add_item(tr("EASY"), GameSettings.Difficulty.EASY)
    difficulty_option.add_item(tr("STANDARD"), GameSettings.Difficulty.STANDARD)
    difficulty_option.add_item(tr("HARD"), GameSettings.Difficulty.HARD)
    difficulty_option.add_item(tr("HARDCORE"), GameSettings.Difficulty.HARDCORE)
    difficulty_option.select(difficulty_option.get_item_index(GameSettings.Difficulty.STANDARD))
    if settings:
        settings.difficulty = GameSettings.Difficulty.STANDARD
    difficulty_option.item_selected.connect(_on_difficulty_selected)

    # Тултипы на пунктах выпадающего списка сложности (всплывают при наведении
    # на конкретный пункт в открытом попапе OptionButton).
    var difficulty_popup: PopupMenu = difficulty_option.get_popup()
    for i in range(difficulty_option.item_count):
        var item_difficulty := difficulty_option.get_item_id(i) as GameSettings.Difficulty
        difficulty_popup.set_item_tooltip(i, _get_difficulty_tooltip(item_difficulty))

    # Подпись с характеристиками сложности под самим OptionButton — сразу
    # показываем данные для сложности по умолчанию (STANDARD).
    _update_difficulty_details(GameSettings.Difficulty.STANDARD)

    # Стартовое значение берём из самого слайдера (задано в сцене), а не
    # перезаписываем его текущим AIManager.ai_aggression — иначе слайдер
    # всегда прыгал бы на 100%, затирая значение по умолчанию из .tscn.
    AIManager.ai_aggression = clampf(aggression_slider.value / 100.0, 0.0, 1.0)
    aggression_value_label.text = "%d%%" % int(round(aggression_slider.value))
    # Подключаем сигнал и из кода — подстраховка на случай, если коннект
    # в .tscn отсутствует/будет случайно удалён в редакторе.
    if not aggression_slider.value_changed.is_connected(_on_aggression_slider_changed):
        aggression_slider.value_changed.connect(_on_aggression_slider_changed)


## Единая точка установки страны на кнопке: id — идёт в логику (country_id),
## отображаемый text — переведённое название (или "CHOOSE_COUNTRY", если id пуст).
func set_country(id: String) -> void:
    country_id = id
    BLUE.text = tr(id.to_upper()) if id != "" else tr("CHOOSE_COUNTRY")


func _on_difficulty_selected(index: int) -> void:
    var selected_difficulty := difficulty_option.get_item_id(index) as GameSettings.Difficulty
    if settings:
        settings.difficulty = selected_difficulty
    _update_difficulty_details(selected_difficulty)


## Возвращает текст тултипа для конкретного уровня сложности — краткая
## сводка модификатора цены построек/призыва, статуса санкций и сохранений.
func _get_difficulty_tooltip(d: GameSettings.Difficulty) -> String:
    var key: String
    var fallback: String
    match d:
        GameSettings.Difficulty.EASY:
            key = "DIFFICULTY_TOOLTIP_EASY"
            fallback = "Постройки и призыв войск дешевле на 25%.\nМировые санкции (__WORLD__) не действуют.\nСохранение доступно."
        GameSettings.Difficulty.HARD:
            key = "DIFFICULTY_TOOLTIP_HARD"
            fallback = "Постройки и призыв войск дороже на 25%.\nМировые санкции действуют.\nСохранение доступно."
        GameSettings.Difficulty.HARDCORE:
            key = "DIFFICULTY_TOOLTIP_HARDCORE"
            fallback = "Постройки и призыв войск дороже на 50%.\nМировые санкции действуют.\nСохранение ОТКЛЮЧЕНО (ни ручное, ни авто)."
        _:
            key = "DIFFICULTY_TOOLTIP_STANDARD"
            fallback = "Обычные цены на постройки и призыв войск.\nМировые санкции действуют.\nСохранение доступно."

    var translated := tr(key)
    # Если перевода для ключа нет в CSV — Godot вернёт сам ключ; в этом
    # случае показываем заготовленный текст, чтобы тултип не был пустым/сырым.
    return fallback if translated == key else translated


## Обновляет подпись под OptionButton — подробные характеристики выбранной
## сложности (BBCode: цвет зелёный — бонус игроку, красный — штраф/запрет).
func _update_difficulty_details(d: GameSettings.Difficulty) -> void:
    if not difficulty_details:
        return

    var cost_percent: int
    var cost_color: String
    var cost_sign: String
    match d:
        GameSettings.Difficulty.EASY:
            cost_percent = 25
            cost_color = "#7CFC7C"   # зелёный — дешевле
            cost_sign = "-"
        GameSettings.Difficulty.HARD:
            cost_percent = 25
            cost_color = "#FF8C6B"   # красный — дороже
            cost_sign = "+"
        GameSettings.Difficulty.HARDCORE:
            cost_percent = 50
            cost_color = "#FF5C5C"   # ярко-красный — дороже всего
            cost_sign = "+"
        _:
            cost_percent = 0
            cost_color = "#CFCFCF"   # серый — без изменений
            cost_sign = ""

    var cost_label := _tr_or("DIFFICULTY_COST_LABEL", "Постройки и призыв")
    var cost_line: String
    if cost_percent == 0:
        cost_line = "[color=%s]%s: 0%%[/color]" % [cost_color, cost_label]
    else:
        cost_line = "[color=%s]%s: %s%d%%[/color]" % [cost_color, cost_label, cost_sign, cost_percent]

    var sanctions_on := d != GameSettings.Difficulty.EASY
    var sanctions_color := "#FF8C6B" if sanctions_on else "#7CFC7C"
    var sanctions_label := _tr_or("DIFFICULTY_SANCTIONS_LABEL", "Мировые санкции")
    var sanctions_text := _tr_or("DIFFICULTY_SANCTIONS_ON", "действуют") if sanctions_on else _tr_or("DIFFICULTY_SANCTIONS_OFF", "отключены")
    var sanctions_line := "[color=%s]%s: %s[/color]" % [sanctions_color, sanctions_label, sanctions_text]

    var saving_disabled := d == GameSettings.Difficulty.HARDCORE
    var saving_color := "#FF5C5C" if saving_disabled else "#7CFC7C"
    var saving_label := _tr_or("DIFFICULTY_SAVING_LABEL", "Сохранение")
    var saving_text := _tr_or("DIFFICULTY_SAVING_OFF", "отключено") if saving_disabled else _tr_or("DIFFICULTY_SAVING_ON", "доступно")
    var saving_line := "[color=%s]%s: %s[/color]" % [saving_color, saving_label, saving_text]

    difficulty_details.bbcode_text = "%s\n%s\n%s" % [cost_line, sanctions_line, saving_line]


## tr() с запасным вариантом на случай отсутствия ключа в CSV переводов —
## чтобы UI не показывал "сырые" ключи вида DIFFICULTY_COST_LABEL.
func _tr_or(key: String, fallback: String) -> String:
    var translated := tr(key)
    return fallback if translated == key else translated


## Сохраняет позицию слайдера "агрессии" ИИ (0..100, слайдер) как 0.0..1.0
## в AIManager.ai_aggression. Сам множитель шанса войны — нелинейный
## (0% -> ×0, 50% -> ×1.5, 100% -> ×10) и считается в
## AIManager.get_aggression_multiplier(), а не тут.
func _on_aggression_slider_changed(value: float) -> void:
    AIManager.ai_aggression = clampf(value / 100.0, 0.0, 1.0)
    aggression_value_label.text = "%d%%" % int(round(value))


func _on_fog_button_pressed() -> void:
    fog_is_off = !fog_is_off

    # Синхронизируем реальное состояние тумана войны и пересчитываем,
    # какие дивизии сейчас должны быть видны игроку.
    ProvinceRegistry.fog_of_war_enabled = not fog_is_off
    DivisionManager.refresh_fog_of_war_visibility()

    # Меняем фон и текст кнопки
    if fog_is_off:
        fog_button.add_theme_stylebox_override("normal", fog_button_style_off)
        fog_button.add_theme_stylebox_override("hover", fog_button_style_off_hover)
        fog_button.add_theme_stylebox_override("pressed", fog_button_style_off_pressed)
        fog_button.text = tr("OFF")
    else:
        fog_button.add_theme_stylebox_override("normal", fog_button_style_normal)
        fog_button.add_theme_stylebox_override("hover", fog_button_style_hover)
        fog_button.add_theme_stylebox_override("pressed", fog_button_style_pressed)
        fog_button.text = tr("ON")

    # Анимация нажатия: кнопка немного сжимается и возвращается обратно
    var tween = create_tween()
    fog_button.pivot_offset = fog_button.size / 2
    tween.tween_property(fog_button, "scale", Vector2(0.9, 0.9), 0.08).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
    tween.tween_property(fog_button, "scale", Vector2(1.0, 1.0), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_start_button_pressed() -> void:
    if country_id != "" and ProvinceRegistry.province_data[settings.last_clicked_province_id].get("owner", "") != "sea":
        if settings:
            settings.active_country = country_id
            settings.can_draw = true
            DivisionManager.refresh_fog_of_war_visibility()
            hide()
            #get_parent().queue_free()
        GameClock.paused = false
        get_node("/root/Game/CanvasLayer/TopMenu/TopPanel/DatePanel/HBoxContainer/PauseButton").icon = load("res://assets/pause_opened.png")
        TopMenu.update(country_id)
        TopMenu.show()
        CountryPanel.update_info()
        DivisionMenu.show()
        DivisionMenu.update_info(settings.province_data[settings.last_clicked_province_id])
        ProvinceMenu.show()
        ProvinceMenu.update_info(ProvinceRegistry.province_data[settings.last_clicked_province_id])
        NotificationMenu.show()
