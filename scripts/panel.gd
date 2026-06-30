extends Panel

@export var settings: Resource

@onready var CountryLabel = $VBoxContainer1/CountryLabel
@onready var ProvincesLabel = $VBoxContainer1/ProvincesLabel
@onready var PopulationLabel = $VBoxContainer1/PopulationLabel

@onready var InfluenceLabel = $VBoxContainer2/InfluenceLabel
@onready var StabilityLabel = $VBoxContainer2/StabilityLabel

@onready var NegotiationBtn = $Negotiation
@onready var NegotiationMenu  = get_node("/root/Game/CanvasLayer/NegotiationMenu")

var owner_name

func _ready() -> void:
    NegotiationBtn.hide()
    hide()
    add_to_group("CountryMenuPanel")
    GameClock.on_day_passed.connect(_on_day_passed)

func _on_day_passed(_date: Dictionary) -> void:
    if visible:
        update_info()

func _format_population(n: int) -> String:
    var s = str(n)
    var result = ""
    var count = 0
    for i in range(s.length() - 1, -1, -1):
        result = s[i] + result
        count += 1
        if count % 3 == 0 and i != 0:
            result = " " + result
    return result

func update_info():
    owner_name = ProvinceRegistry.province_data[str(settings.last_clicked_province_id)].get("owner", "unknown")
    
    CountryLabel.text = owner_name
    ProvincesLabel.text = "Provinces: " + str(ProvinceRegistry.owner_province_count[owner_name])
    PopulationLabel.text = "Population 👥: " + _format_population(ProvinceRegistry.get_country_population(owner_name))
    
    InfluenceLabel.text = 'Influence 🌐: ' + str(ProvinceRegistry.countries_data[owner_name]['influence']) + '%'
    StabilityLabel.text = 'Stability 🛡️: ' + str(ProvinceRegistry.countries_data[owner_name]['stability']) + '%'
    
    if ProvinceRegistry.is_at_war(settings.active_country, owner_name):
        NegotiationBtn.show()
    else:
        NegotiationBtn.hide()

func _on_negotiation_pressed() -> void:
    NegotiationMenu.open_negotiation(owner_name)
