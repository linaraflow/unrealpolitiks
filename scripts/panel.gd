extends Panel

@export var settings: Resource

# --- Header ---
@export var FlagRect: TextureRect
@export var CountryLabel: Label
@export var ProvincesLabel: Label

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

# --- Ideology ---
@export var IdeologyCard: Control
@export var IdeologyLabel: Label
@export var ChangeIdeologyBtn: Button

@export var ideology_panel: Panel
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

    for btn in [ImproveBtn, WorsenBtn, SanctionBtn, DeclareWarBtn, NegotiationBtn]:
        btn.custom_minimum_size.y = 40
        btn.clip_text = true

    for btn in [ImproveBtn, WorsenBtn, SanctionBtn, DeclareWarBtn, NegotiationBtn]:
        btn.custom_minimum_size.y = 40
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


func _update_relations_bar(value: int) -> void:
    RelationsValueLabel.text = ("+" if value > 0 else "") + str(value)

    await get_tree().process_frame # ждём, чтобы layout уже посчитал размеры
    var ratio = clamp((value + 100) / 200.0, 0.0, 1.0)
    var track_width = RelationsBarBox.size.x
    RelationsMarker.position.x = ratio * track_width - RelationsMarker.size.x / 2.0
    RelationsMarker.position.y = (RelationsBarBox.size.y - RelationsMarker.size.y) / 2.0


# ---------------- Main update ----------------

func update_info():
    owner_name = ProvinceRegistry.province_data[str(settings.last_clicked_province_id)].get("owner", "unknown")
    var data = ProvinceRegistry.countries_data[owner_name]

    CountryLabel.text = owner_name
    ProvincesLabel.text = "Provinces: " + str(ProvinceRegistry.owner_province_count[owner_name]) + "   " + str(data.get("ideology", "liberalism")).capitalize()
    PopulationLabel.text = ProvinceRegistry._format_number(ProvinceRegistry.get_country_population(owner_name), " ")

    var GDP = (ProvinceRegistry.countries_data[owner_name].get("factories", 0) * settings.product_cost + data.get("monthly_income", 0)) * 12
    FactoriesLabel.text = ProvinceRegistry._format_number(GDP, ".") + "$"

    var flag_path = "res://assets/flags/" + owner_name + ".png"
    FlagRect.texture = load(flag_path)

    _update_happiness(round(data.get("happiness", 0)))
    _set_stat_bar(WarExhaustionBar, WarExhaustionValueLabel, data.get("war_exhaustion", 0.0), true)
    _set_stat_bar(SanctionsBar, SanctionsValueLabel, data.get("sanctions", 0.0), true)

    IdeologyLabel.text = str(data.get("ideology", "liberalism")).capitalize()

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
    ProvinceRegistry.declare_war(settings.active_country, owner_name)
    var WarBanner = get_node("/root/Game/WarBanner")
    WarBanner.show_declaration(settings.active_country, owner_name)
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
    var current_ideology = ProvinceRegistry.countries_data[settings.active_country].get("ideology", "liberalism")

    for ideo in ideologies:
        var btn = Button.new()
        btn.text = ideo.capitalize()
        btn.pressed.connect(_on_ideology_button_pressed.bind(btn, ideo))
        ideology_list.add_child(btn)

    _highlight_ideology(current_ideology)


func _highlight_ideology(ideo: String) -> void:
    for child in ideology_list.get_children():
        if child is Button:
            child.modulate = Color.YELLOW if child.text == ideo.capitalize() else Color.WHITE


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
