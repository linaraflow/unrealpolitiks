extends Panel

@export var settings: Resource

@onready var CountryLabel = $CountryLabel
@onready var ProvincesLabel = $VBoxContainer1/ProvincesLabel
@onready var PopulationLabel = $VBoxContainer1/PopulationLabel
@onready var FactoriesLabel = $VBoxContainer1/FactoriesLabel

@onready var IdeologyLabel = $VBoxContainer1/IdeologyLabel
@onready var RelationsLabel = $VBoxContainer1/RelationsLabel
@onready var SanctionsLabel = $VBoxContainer1/SanctionsLabel

@onready var InfluenceLabel = $VBoxContainer2/InfluenceLabel
@onready var StabilityLabel = $VBoxContainer2/StabilityLabel

@onready var NegotiationBtn = $Negotiation
@onready var NegotiationMenu  = get_node("/root/Game/CanvasLayer/NegotiationMenu")

@onready var ImproveBtn = $ImproveRelationsBtn
@onready var WorsenBtn = $WorsenRelationsBtn
@onready var SanctionBtn = $ImposeSanctionsBtn
@onready var ChangeIdeologyBtn = $ChangeIdeologyBtn

@export var ideology_panel: Panel
@export var ideology_list: VBoxContainer
@export var change_btn: Button
@export var close_btn: Button

var owner_name
var selected_ideology: String = ""

func _ready() -> void:
    NegotiationBtn.hide()
    hide()
    add_to_group("CountryMenuPanel")
    GameClock.on_day_passed.connect(_on_day_passed)
    _setup_progress_overlay(ImproveBtn)
    _setup_progress_overlay(WorsenBtn)
    
    ideology_panel.visible = false
    
    change_btn.pressed.connect(_on_change_btn_pressed)
    close_btn.pressed.connect(_on_close_btn_pressed)

func _on_day_passed(_date: Dictionary) -> void:
    if visible:
        update_info()
    _update_relation_progress_overlay(ImproveBtn)
    _update_relation_progress_overlay(WorsenBtn)

func _setup_progress_overlay(btn: Button) -> void:
    var overlay = ColorRect.new()
    overlay.name = "ProgressOverlay"
    overlay.color = Color(0, 0, 0, 0.6)
    overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
    overlay.anchor_left = 0.0
    overlay.anchor_right = 1.0
    overlay.anchor_bottom = 1.0
    overlay.anchor_top = 1.0
    overlay.offset_left = 0
    overlay.offset_right = 0
    overlay.offset_top = 0
    overlay.offset_bottom = 0
    btn.add_child(overlay)

func _update_relation_progress_overlay(btn: Button) -> void:
    var overlay = btn.get_node_or_null("ProgressOverlay") as ColorRect
    if overlay == null or owner_name == null:
        return
    var progress = DiplomacyManager.get_process_progress(settings.active_country, owner_name)
    overlay.anchor_top = 1.0 - progress

func update_info():
    owner_name = ProvinceRegistry.province_data[str(settings.last_clicked_province_id)].get("owner", "unknown")
    var data = ProvinceRegistry.countries_data[owner_name]
    
    CountryLabel.text = owner_name
    ProvincesLabel.text = "Provinces: " + str(ProvinceRegistry.owner_province_count[owner_name])
    PopulationLabel.text = "Population 👥: " + ProvinceRegistry._format_number(ProvinceRegistry.get_country_population(owner_name), " ")
    var GDP = (ProvinceRegistry.countries_data[owner_name].get("factories", 0) * settings.product_cost + data.get("monthly_income", 0)) * 12
    FactoriesLabel.text = "GDP: " + ProvinceRegistry._format_number(GDP, ".") + "$"
    
    IdeologyLabel.text = "Ideology: " + str(data.get("ideology", "liberalism")).capitalize()
    RelationsLabel.text = "Relations: " + str(DiplomacyManager.get_relation(settings.active_country, owner_name))
    SanctionsLabel.text = "Sanctions: " + str(int(round(data.get("sanctions", 0.0)))) + "%"
    
    InfluenceLabel.text = 'Influence 🌐: ' + str(ProvinceRegistry.countries_data[owner_name]['influence']) + '%'
    StabilityLabel.text = 'Stability 🛡️: ' + str(ProvinceRegistry.countries_data[owner_name]['stability']) + '%'
    
    if ProvinceRegistry.is_at_war(settings.active_country, owner_name):
        NegotiationBtn.show()
    else:
        NegotiationBtn.hide()
        
    if settings.can_draw == false:
        RelationsLabel.visible = false
        ImproveBtn.visible = false
        WorsenBtn.visible = false
        SanctionBtn.visible = false
        ChangeIdeologyBtn.visible = false
        return
    var is_myself = (owner_name == settings.active_country)
    RelationsLabel.visible = !is_myself
    ImproveBtn.visible = !is_myself
    WorsenBtn.visible = !is_myself
    SanctionBtn.visible = !is_myself
    ChangeIdeologyBtn.visible = is_myself

func _on_negotiation_pressed() -> void:
    NegotiationMenu.open_negotiation(owner_name)

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
    # Очищаем предыдущие кнопки
    for child in ideology_list.get_children():
        child.queue_free()
    
    var ideologies = DiplomacyManager.IDEOLOGIES.keys()
    var current_ideology = ProvinceRegistry.countries_data[settings.active_country].get("ideology", "liberalism")
    
    for ideo in ideologies:
        var btn = Button.new()
        btn.text = ideo.capitalize()
        btn.pressed.connect(_on_ideology_button_pressed.bind(btn, ideo))  # передаём кнопку и название
        ideology_list.add_child(btn)
    
    # После создания всех кнопок — подсвечиваем текущую
    _highlight_ideology(current_ideology)

# Сбрасывает подсветку у всех кнопок и подсвечивает выбранную
func _highlight_ideology(ideo: String) -> void:
    for child in ideology_list.get_children():
        if child is Button:
            if child.text == ideo.capitalize():
                child.modulate = Color.YELLOW  # яркий цвет
            else:
                child.modulate = Color.WHITE   # обычный цвет

# Обработчик нажатия на кнопку идеологии
func _on_ideology_button_pressed(btn: Button, ideo: String) -> void:
    selected_ideology = ideo
    _highlight_ideology(ideo)  # подсвечиваем выбранную, остальные сбрасываем

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
