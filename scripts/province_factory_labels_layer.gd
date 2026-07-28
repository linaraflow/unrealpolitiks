extends Node2D

## Слой с подписями "число заводов" поверх вражеских провинций.
## Используется в режимах прицеливания БПЛА/ракеты (map.gd:
## _show_enemy_factory_labels / _clear_enemy_factory_labels) — координаты
## те же локальные, что и province_centers, т.к. этот узел — child карты Map.

const LABEL_FONT_SIZE: int = 18
const LABEL_SIZE: Vector2 = Vector2(40, 24)

## p_id -> Label, чтобы не пересоздавать ноды заново на каждый вызов, если
## набор целей не сильно меняется (сейчас всё равно чистим и строим заново —
## оставлено на будущее, если понадобится точечное обновление).
var _labels_by_id: Dictionary = {}


func _make_label() -> Label:
    var lbl := Label.new()
    lbl.add_theme_font_size_override("font_size", LABEL_FONT_SIZE)
    lbl.add_theme_color_override("font_color", Color(1, 1, 1))
    lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
    lbl.z_index = 100
    lbl.size = LABEL_SIZE
    return lbl


## entries: Array[Dictionary] с полями {p_id:int, pos:Vector2, count:int}.
## pos — локальные координаты провинции (как в province_centers).
func set_labels(entries: Array) -> void:
    clear_labels()
    for e in entries:
        var lbl := _make_label()
        lbl.text = str(e.count)
        # Центрируем подпись на центре провинции.
        lbl.position = e.pos - LABEL_SIZE / 2.0
        add_child(lbl)
        _labels_by_id[e.p_id] = lbl


## Убирает все подписи (выход из режима прицеливания / смена набора целей).
func clear_labels() -> void:
    for child in get_children():
        child.queue_free()
    _labels_by_id.clear()
