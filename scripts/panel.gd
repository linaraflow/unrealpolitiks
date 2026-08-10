extends Panel
@export var settings: Resource

# --- Header ---
@export var FlagRect: TextureRect
@export var CountryLabel: Label
@export var CountryLabelScroll: ScrollContainer
@export var ProvincesLabel: Label

# --- Marquee (бегущая строка для названия страны) ---
var _marquee_tween: Tween
const MARQUEE_SPEED: float = 40.0   # пикселей в секунду
const MARQUEE_PAUSE: float = 1.0    # пауза у краёв в секундах

# --- Stat cards ---
@export var PopulationLabel: Label
@export var FactoriesLabel: Label

# --- Bars ---
@export var HappinessLabel: Label
@export var HappinessBar: ProgressBar

@export var WarExhaustionValueLabel: Label
@export var WarExhaustionBar: ProgressBar

@export var SanctionsValueLabel: Label
@export var SanctionsBar: ProgressBar

# --- Relations ---
@export var RelationsRow: Control
@export var RelationsValueLabel: Label
@export var RelationsBarBox: Control
@export var RelationsMarker: Control

# --- Diplomacy actions ---
@export var DiplomacyActionsGrid: Control
@export var ImproveBtn: Button
@export var WorsenBtn: Button
@export var SanctionBtn: Button
@export var DeclareWarBtn: Button
@export var NegotiationBtn: Button
@onready var NegotiationMenu = get_node("/root/Game/CanvasLayer/NegotiationMenu")

# --- Статистика ---
@onready var StatisticsMenu = get_node("/root/Game/CanvasLayer/StatisticsMenu")

# --- Ideology ---
@export var IdeologyCard: Control
@export var IdeologyLabel: Label
@export var ChangeIdeologyBtn: Button

@export var ideology_panel: PanelContainer
@export var ideology_list: VBoxContainer
@export var change_btn: Button
@export var close_btn: Button

# --- Colors ---
const COLOR_GOOD = Color(0.23, 0.54, 0.23)
const COLOR_MID = Color(0.85, 0.6, 0.17)
const COLOR_BAD = Color(0.75, 0.22, 0.17)

var owner_name
var selected_ideology: String = ""


func _ready() -> void:
    _check_nodes()
    hide()
    add_to_group("CountryMenuPanel")
    GameClock.on_day_passed.connect(_on_day_passed)
    visibility_changed.connect(_on_visibility_changed)

    for btn in [ImproveBtn, WorsenBtn, SanctionBtn, DeclareWarBtn, NegotiationBtn]:
        btn.clip_text = true

    ideology_panel.visible = false

    change_btn.pressed.connect(_on_change_btn_pressed)
    close_btn.pressed.connect(_on_close_btn_pressed)
    ImproveBtn.pressed.connect(_on_improve_relations_btn_pressed)
    WorsenBtn.pressed.connect(_on_worsen_relations_btn_pressed)
    SanctionBtn.pressed.connect(_on_improve_sanctions_btn_pressed)
    ChangeIdeologyBtn.pressed.connect(_on_change_ideology_btn_pressed)
    DeclareWarBtn.pressed.connect(_on_declare_war_btn_pressed)
    NegotiationBtn.pressed.connect(_on_negotiation_pressed)


func _check_nodes() -> void:
    var to_check = {
        "FlagRect": FlagRect,
        "CountryLabel": CountryLabel,
        "CountryLabelScroll": CountryLabelScroll,
        "ProvincesLabel": ProvincesLabel,
        "PopulationLabel": PopulationLabel,
        "FactoriesLabel": FactoriesLabel,
        "HappinessLabel": HappinessLabel,
        "HappinessBar": HappinessBar,
        "WarExhaustionValueLabel": WarExhaustionValueLabel,
        "WarExhaustionBar": WarExhaustionBar,
        "SanctionsValueLabel": SanctionsValueLabel,
        "SanctionsBar": SanctionsBar,
        "RelationsRow": RelationsRow,
        "RelationsValueLabel": RelationsValueLabel,
        "RelationsBarBox": RelationsBarBox,
        "RelationsMarker": RelationsMarker,
        "DiplomacyActionsGrid": DiplomacyActionsGrid,
        "ImproveBtn": ImproveBtn,
        "WorsenBtn": WorsenBtn,
        "SanctionBtn": SanctionBtn,
        "DeclareWarBtn": DeclareWarBtn,
        "NegotiationBtn": NegotiationBtn,
        "IdeologyCard": IdeologyCard,
        "IdeologyLabel": IdeologyLabel,
        "ChangeIdeologyBtn": ChangeIdeologyBtn,
        "ideology_panel": ideology_panel,
        "ideology_list": ideology_list,
        "change_btn": change_btn,
        "close_btn": close_btn,
    }
    for key in to_check.keys():
        if to_check[key] == null:
            push_error("panel.gd: узел '%s' не найден — проверь путь @onready и имя ноды в сцене." % key)


func _on_visibility_changed() -> void:
    if not visible and _marquee_tween:
        _marquee_tween.kill()
        _marquee_tween = null


func _on_day_passed(_date: Dictionary) -> void:
    if visible:
        update_info()


# ---------------- Visual helpers ----------------

# Красит заливку ProgressBar в зависимости от значения.
# bad_when_high = true для статов, где чем больше — тем хуже (усталость, санкции).
func _set_stat_bar(bar: ProgressBar, value_label: Label, value: float, bad_when_high: bool = false) -> void:
    bar.min_value = 0
    bar.max_value = 100
    bar.value = clamp(value, 0, 100)

    var color: Color
    if bad_when_high:
        color = COLOR_GOOD if value < 25 else (COLOR_MID if value < 60 else COLOR_BAD)
    else:
        color = COLOR_BAD if value < 25 else (COLOR_MID if value < 60 else COLOR_GOOD)

    var sb = StyleBoxFlat.new()
    sb.bg_color = color
    sb.corner_radius_top_left = 3
    sb.corner_radius_top_right = 3
    sb.corner_radius_bottom_left = 3
    sb.corner_radius_bottom_right = 3
    bar.add_theme_stylebox_override("fill", sb)

    if value_label != null:
        value_label.text = str(int(round(value))) + "%"


const MARQUEE_MIN_WIDTH: float = 212.0  # порог ширины CountryLabel, после которого включается бегущая строка
const MARQUEE_GAP: float = 40.0         # пустой промежуток между концом и началом текста при зацикливании

var _marquee_request_id: int = 0        # чтобы устаревшие (перегнанные) вызовы сами себя отменяли
var _last_marquee_text: String = ""     # чтобы не перезапускать марки, если текст не менялся

func _update_country_label_marquee() -> void:
    # Если название не поменялось с прошлого раза — ничего не трогаем,
    # иначе update_info() (вызывается каждый игровой день) будет дёргать
    # и рестартить уже идущую анимацию, отсюда рывки.
    if CountryLabel.text == _last_marquee_text and _marquee_tween and _marquee_tween.is_valid():
        return
    _last_marquee_text = CountryLabel.text

    _marquee_request_id += 1
    var my_id = _marquee_request_id

    if _marquee_tween:
        _marquee_tween.kill()
        _marquee_tween = null

    CountryLabelScroll.scroll_horizontal = 0

    # Ждём два кадра: одного не всегда хватает, чтобы контейнеры выше по
    # иерархии успели пересчитать layout после смены текста/видимости.
    await get_tree().process_frame
    await get_tree().process_frame

    # Пока ждали кадры, могла прилететь ещё одна перегонка (или панель
    # успели скрыть/удалить) — тогда этот вызов уже неактуален, выходим.
    if my_id != _marquee_request_id or not is_instance_valid(CountryLabel) or not is_instance_valid(CountryLabelScroll):
        return

    # Измеряем реальную ширину текста через шрифт, а не CountryLabel.size.x —
    # если у лейбла выставлен size flag EXPAND/FILL внутри ScrollContainer,
    # его size растягивается под контейнер и overflow всегда получался <= 0,
    # из-за чего марки то работала, то нет в зависимости от предыдущего layout.
    var font: Font = CountryLabel.get_theme_font("font")
    var font_size: int = CountryLabel.get_theme_font_size("font_size")
    var text_width: float = font.get_string_size(CountryLabel.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x

    var viewport_width: float = CountryLabelScroll.size.x

    # Если название не вылезает за границы — просто оставляем как есть, без бегущей строки.
    if text_width < MARQUEE_MIN_WIDTH or text_width <= viewport_width:
        return

    var overflow = text_width - viewport_width

    # Едет непрерывно в одну сторону (как табло в трамвае), затем резко
    # "перепрыгивает" в начало и снова едет — без движения назад.
    var total_distance = overflow + MARQUEE_GAP
    var duration = total_distance / MARQUEE_SPEED

    _marquee_tween = create_tween()
    _marquee_tween.set_loops()
    # 1. Пауза в начале перед стартом
    _marquee_tween.tween_interval(MARQUEE_PAUSE)

    # 2. Анимация движения текста до конца
    _marquee_tween.tween_property(CountryLabelScroll, "scroll_horizontal", overflow, duration * overflow / total_distance)\
        .from(0).set_trans(Tween.TRANS_LINEAR)

    # 3. Пауза, когда текст доехал до конца
    _marquee_tween.tween_interval(MARQUEE_PAUSE)

    # 4. Резкий сброс в начало
    _marquee_tween.tween_callback(func():
        if is_instance_valid(CountryLabelScroll):
            CountryLabelScroll.scroll_horizontal = 0
    )


func _update_relations_bar(value: int) -> void:
    RelationsValueLabel.text = ("+" if value > 0 else "") + str(value)

    await get_tree().process_frame # ждём, чтобы layout уже посчитал размеры
    var ratio = clamp((value + 100) / 200.0, 0.0, 1.0)
    var track_width = RelationsBarBox.size.x
    RelationsMarker.position.x = ratio * track_width - RelationsMarker.size.x / 2.0
    RelationsMarker.position.y = (RelationsBarBox.size.y - RelationsMarker.size.y) / 2.0


# ---------------- Main update ----------------

func update_info():
    owner_name = ProvinceRegistry.province_data[settings.last_clicked_province_id].get("owner", "unknown")

    # Провинция моря (owner == "sea") или ничья земля (owner == "") — это не
    # страна, в countries_data такого ключа нет. Раньше здесь падало на
    # ProvinceRegistry.countries_data[owner_name] (возвращало null, а
    # следующий data.get(...) кидал ошибку). Показывать тут нечего — просто
    # прячем панель и выходим.
    if not ProvinceRegistry.countries_data.has(owner_name):
        hide()
        return

    var data = ProvinceRegistry.countries_data[owner_name]

    CountryLabel.text = tr(owner_name.to_upper())
    ProvincesLabel.text = tr("PROVINCES") + ": " + str(ProvinceRegistry.owner_province_count[owner_name]) + "   " + tr(data.get("ideology", "liberalism").to_upper()).capitalize()
    _update_country_label_marquee()
    PopulationLabel.text = ProvinceRegistry._format_number(ProvinceRegistry.get_country_population(owner_name), " ")

    var GDP = (ProvinceRegistry.countries_data[owner_name].get("factories", 0) * settings.product_cost + data.get("monthly_income", 0)) * 12
    FactoriesLabel.text = ProvinceRegistry._format_number(GDP, ".") + "$"

    var flag_path = "res://assets/flags/" + owner_name + ".png"
    FlagRect.texture = load(flag_path)

    _update_happiness(round(data.get("happiness", 0)))
    _set_stat_bar(WarExhaustionBar, WarExhaustionValueLabel, data.get("war_exhaustion", 0.0), true)
    _set_stat_bar(SanctionsBar, SanctionsValueLabel, data.get("sanctions", 0.0), true)

    IdeologyLabel.text = tr(str(data.get("ideology", "liberalism")).to_upper()).capitalize()

    var is_myself = (owner_name == settings.active_country)
    var at_war = ProvinceRegistry.is_at_war(settings.active_country, owner_name)

    if not is_myself:
        _update_relations_bar(DiplomacyManager.get_relation(settings.active_country, owner_name))

    # --- Видимость блоков ---
    if settings.can_draw == false:
        RelationsRow.visible = false
        DiplomacyActionsGrid.visible = false
        IdeologyCard.visible = false
        return

    RelationsRow.visible = !is_myself
    DiplomacyActionsGrid.visible = !is_myself
    IdeologyCard.visible = is_myself

    if not is_myself:
        DeclareWarBtn.visible = not at_war
        NegotiationBtn.visible = at_war
        get_parent().custom_minimum_size.y = 433
        size.y = 433
    else:
        get_parent().custom_minimum_size.y = 290
        size.y = 290

func _update_happiness(happiness) -> void:
    var emoji: String
    if happiness <= 30:
        emoji = "😫"
    elif happiness <= 70:
        emoji = "😐"
    else:
        emoji = "😁"
    HappinessLabel.text = emoji + " " + str(happiness)
    _set_stat_bar(HappinessBar, null, happiness)


# ---------------- Button handlers ----------------

func _on_negotiation_pressed() -> void:
    NegotiationMenu.open_negotiation(owner_name)


func _on_declare_war_btn_pressed() -> void:
    if owner_name == "" or owner_name == settings.active_country:
        return
    # WarBanner теперь сам подписан на ProvinceRegistry.war_declared
    # и показывается независимо от того, кто объявил войну.
    ProvinceRegistry.declare_war(settings.active_country, owner_name)
    update_info()


func _on_improve_relations_btn_pressed() -> void:
    var cost = 50000.0
    var player_balance = ProvinceRegistry.countries_data[settings.active_country].get("balance", 0.0)
    if player_balance < cost:
        return
    if DiplomacyManager.start_relations_process(settings.active_country, owner_name, "improve"):
        ProvinceRegistry.countries_data[settings.active_country]["balance"] -= cost
        update_info()


func _on_worsen_relations_btn_pressed() -> void:
    DiplomacyManager.start_relations_process(settings.active_country, owner_name, "worsen")
    update_info()


func _on_improve_sanctions_btn_pressed() -> void:
    var cost = 150000.0
    if DiplomacyManager.toggle_sanctions(settings.active_country, owner_name, cost):
        update_info()


func _on_change_ideology_btn_pressed() -> void:
    _populate_ideology_list()
    ideology_panel.visible = true


func _populate_ideology_list() -> void:
    for child in ideology_list.get_children():
        child.queue_free()

    var ideologies = DiplomacyManager.IDEOLOGIES.keys()
    var current_ideology: String = ProvinceRegistry.countries_data[settings.active_country].get("ideology", "liberalism")

    for ideo in ideologies:
        var btn = Button.new()
        btn.text = tr(ideo.to_upper()).capitalize()
        btn.set_meta("ideology_key", ideo)
        btn.mouse_entered.connect(_on_ideology_selection_panel_mouse_entered)
        btn.mouse_exited.connect(_on_ideology_selection_panel_mouse_exited)
        btn.pressed.connect(_on_ideology_button_pressed.bind(btn, ideo))
        ideology_list.add_child(btn)

    _highlight_ideology(current_ideology)


func _highlight_ideology(ideo: String) -> void:
    for child in ideology_list.get_children():
        if child is Button:
            child.modulate = Color.YELLOW if child.get_meta("ideology_key", "") == ideo else Color.WHITE


func _on_ideology_button_pressed(btn: Button, ideo: String) -> void:
    selected_ideology = ideo
    _highlight_ideology(ideo)


func _on_change_btn_pressed() -> void:
    if selected_ideology.is_empty():
        print("Выберите идеологию!")
        return

    var cost = 5000000.0
    if DiplomacyManager.change_ideology(settings.active_country, selected_ideology, cost):
        update_info()
        ideology_panel.visible = false
        selected_ideology = ""
    else:
        print("Недостаточно средств!")


func _on_close_btn_pressed() -> void:
    ideology_panel.visible = false
    selected_ideology = ""





func _on_ideology_selection_panel_mouse_entered() -> void:
    settings.is_mouse_over_ui = true


func _on_ideology_selection_panel_mouse_exited() -> void:
    settings.is_mouse_over_ui = false
