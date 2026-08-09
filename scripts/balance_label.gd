extends Label

@export var settings: Resource

const FLASH_COLOR := Color(1.0, 0.25, 0.2)
const NORMAL_COLOR := Color(1, 1, 1)
const FLASH_PULSES := 1
const FLASH_IN_TIME := 0.12
const FLASH_OUT_TIME := 0.22

var flash_tween: Tween


func _ready() -> void:
    AIManager.balance_label = self
    SaveManager.balance_label = self
    balance_update()


func balance_update():
    if ProvinceRegistry.countries_data.has(settings.active_country):
        var balance_val = ProvinceRegistry.countries_data[settings.active_country]['balance']
        text = '💵 ' + ProvinceRegistry._format_number(balance_val, ".")

# Пульсирующая красная подсветка — вызывать сразу после balance_update()
# в местах, где деньги реально списались (призыв, постройка завода и т.п.)
func flash_spent() -> void:
    if flash_tween and flash_tween.is_valid():
        flash_tween.kill()

    modulate = NORMAL_COLOR
    flash_tween = create_tween()
    flash_tween.set_trans(Tween.TRANS_SINE)
    flash_tween.set_loops(FLASH_PULSES)
    flash_tween.tween_property(self, "modulate", FLASH_COLOR, FLASH_IN_TIME).set_ease(Tween.EASE_OUT)
    flash_tween.tween_property(self, "modulate", NORMAL_COLOR, FLASH_OUT_TIME).set_ease(Tween.EASE_IN)
