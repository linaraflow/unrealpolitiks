extends Node

var settings = preload("res://new_resource.tres")

signal on_day_passed(date)
signal on_month_passed(date)
signal on_year_passed(date)
signal on_speed_changed(speed)
signal on_pause_changed(paused)

const SPEEDS = [0, 1, 3, 5, 7, 9]  # x0 (пауза), x1, x3, x5, x10
const SECONDS_PER_DAY = 2.0       # сколько реальных секунд = 1 игровой день на x1

var day: int = 1
var month: int = 1
var year: int = 2013

var speed_index: int = 1          # текущая скорость (индекс в SPEEDS)
var paused: bool = true

var _accumulated: float = 0.0

func _ready():
    pass

func _process(delta: float):
    if paused or speed_index == 0:
        return
    
    _accumulated += delta * SPEEDS[speed_index]
    
    while _accumulated >= SECONDS_PER_DAY:
        _accumulated -= SECONDS_PER_DAY
        _advance_day()

func _advance_day():
    day += 1
    var days_in_month = _days_in_month(month, year)
    
    if day > days_in_month:
        day = 1
        month += 1
        if month > 12:
            month = 1
            year += 1
            on_year_passed.emit(get_date())
        on_month_passed.emit(get_date())
    
    on_day_passed.emit(get_date())

func get_date() -> Dictionary:
    return {"day": day, "month": month, "year": year}

func get_date_string() -> String:
    return "%02d.%02d.%d" % [day, month, year]

func set_speed(index: int):
    speed_index = clamp(index, 0, SPEEDS.size() - 1)
    emit_signal("on_speed_changed", SPEEDS[speed_index])

func toggle_pause():
    if settings.negotiation_mode == false:
        if not settings.can_draw:
            return
        paused = !paused
        emit_signal("on_pause_changed", paused)

func auto_pause():          # вызывать при важных событиях
    paused = true
    emit_signal("on_pause_changed", paused)

func _days_in_month(m: int, y: int) -> int:
    var days = [31,28,31,30,31,30,31,31,30,31,30,31]
    if m == 2 and (y % 4 == 0 and (y % 100 != 0 or y % 400 == 0)):
        return 29
    return days[m - 1]

func _input(event):

    if event is InputEventKey:
        
        if not event.pressed or event.is_echo():
            return
        
        match event.keycode:
            KEY_SPACE: toggle_pause()
            KEY_1: set_speed(1)
            KEY_2: set_speed(2)
            KEY_3: set_speed(3)
            KEY_4: set_speed(4)
            KEY_5: set_speed(5)
