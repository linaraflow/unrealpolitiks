extends Node2D
## CountryLabelsLayer
## ────────────────────────────────────────────────────────────────────────
## Рисует название страны над КАЖДЫМ связным куском её территории отдельно,
## поворачивая надпись по главной оси кластера (PCA) и вписывая её размер
## в реальные габариты территории. Масштаб РАВНОМЕРНЫЙ (без сжатия/растяжки
## текста по одной из осей) — буквы всегда сохраняют нормальные пропорции.
##
## При отдалении камеры (zoom.x растёт) надписи плавно теряют прозрачность
## по стадиям из fade_stops (см. ниже) и полностью пропадают на последней.
##
## КЭШИРОВАНИЕ КЛАСТЕРОВ (важно для производительности):
##   - _labels_by_country: country -> Array[Dictionary] — уже посчитанные
##     кластеры/геометрия КАЖДОЙ страны. Это и есть "кэш кластеров всех
##     стран" — при изменении владельца ОДНОЙ провинции пересчитывается
##     ТОЛЬКО запись для затронутых 1-2 стран, все остальные страны в этом
##     словаре не трогаются и не пересчитываются.
##   - _dirty_countries: набор стран, ожидающих пересчёта.
##   - НОВОЕ: пересчёт "грязных" стран больше не происходит немедленно на
##     каждое отдельное событие (call_deferred на каждый кадр), а собирается
##     в течение recompute_interval секунд и делается ОДНИМ пересчётом.
##     Это гасит ситуацию "линия фронта дёргается провинция за провинцией
##     много раз в секунду" — вместо пересчёта той же страны на каждом
##     кадре, она пересчитывается не чаще, чем раз в recompute_interval.
##
## Данные, на которые опирается:
##   - ProvinceMap.adjacency          — граф соседства провинций (p_id -> [p_id, ...])
##   - ProvinceRegistry.province_data / countries_data — для первичного
##     построения кэша владения (один раз) и для отображаемых имён/цветов
##   - Map.province_centers           — центр каждой провинции в локальных
##                                       координатах Map (эта нода должна быть
##                                       ребёнком Map с той же трансформацией)
##
## Подключение — как раньше, без изменений:
##   country_labels_layer = preload("res://scripts/country_labels_layer.gd").new()
##   country_labels_layer.name = "CountryLabelsLayer"
##   add_child(country_labels_layer)
##   country_labels_layer.setup(self)
##   country_labels_layer.rebuild()
##
## ВАЖНО: именно ПУБЛИЧНЫЙ rebuild() (не внутренний дебаунс) принудительно
## перестраивает ВСЁ (кэш владения + кластеры всех стран) с нуля — вызывать
## после массовых изменений "в обход" сигналов (например, после
## ProvinceRegistry.reset() в map.gd::restart()).

# ─── НАСТРОЙКИ ────────────────────────────────────────────────────────────

## Кастомный шрифт (необязательно). Если не задан — берётся дефолтный.
@export var font: Font

## Какую долю ширины/высоты bounding box'а кластера (вдоль/поперёк главной
## оси) должна занимать надпись. 1.0 = впритык к краям, меньше — с полями.
@export var width_fill_ratio: float = 0.85
@export var height_fill_ratio: float = 0.55

## Общий множитель итогового размера шрифта.
@export var size_scale: float = 0.55

## Абсолютные пределы размера шрифта в МИРОВЫХ единицах.
@export var min_font_world_size: float = 12.0
@export var max_font_world_size: float = 260.0

## "Виртуальные" габариты для вырожденных кластеров (1 провинция).
@export var min_cluster_dimension: float = 60.0

## Насколько мельче делать надпись у некрупных кусков земли.
@export var minor_cluster_font_scale: float = 0.85

## Кластеры мельче этого числа провинций вообще не подписываются никогда.
@export var min_provinces_for_label: int = 9

## LOD для мелких анклавов.
@export var minor_cluster_ratio_threshold: float = 0.12
@export var close_zoom_threshold: float = 0.6

@export var fill_color: Color = Color(1, 1, 1, 0.95)
@export var outline_color: Color = Color(0, 0, 0, 0.85)
@export var outline_width: int = 15
@export var use_country_color: bool = false

## НОВОЕ: минимальный интервал (в секундах) между пересчётами кластеров
## ОДНОЙ И ТОЙ ЖЕ страны. Если страна помечается "грязной" чаще, чем раз в
## этот интервал (например, фронт колеблется province-by-province несколько
## раз в секунду), реальный пересчёт всё равно случится не чаще этого
## интервала — промежуточные события просто накапливаются в _dirty_countries
## и обрабатываются одним пересчётом.
@export var recompute_interval: float = 0.15

# ─── ЗАТУХАНИЕ ПРОЗРАЧНОСТИ ПРИ ОТДАЛЕНИИ КАМЕРЫ ─────────────────────────
@export var fade_stops: Array[Vector2] = [
    Vector2(1.15, 1.0),
    Vector2(1.35, 0.75),
    Vector2(1.5, 0.4),
    Vector2(1.622566, 0.0),
]

const REF_FONT_SIZE: int = 100


# ─── ВНУТРЕННЕЕ СОСТОЯНИЕ ─────────────────────────────────────────────────

var _map: Node2D
var _cam: Camera2D

## Инкрементальный кэш владения провинциями.
var _province_owner_cache: Dictionary = {}   # p_id -> country
var _provinces_by_country: Dictionary = {}   # country -> Dictionary{p_id: true}
var _cache_built: bool = false

## Кэш кластеров/геометрии по каждой стране (см. класс-комментарий выше).
var _labels_by_country: Dictionary = {}      # country -> Array[Dictionary]

## Страны, ожидающие пересчёта кластеров.
var _dirty_countries: Dictionary = {}

## НОВОЕ: таймер дебаунса — сколько секунд прошло с последнего реального
## пересчёта "грязных" стран.
var _time_since_recompute: float = 0.0


func setup(map_node: Node2D) -> void:
    _map = map_node


func _ready() -> void:
    z_index = 200
    top_level = false  # обязано жить в той же системе координат, что и Map

    if ProvinceRegistry.has_signal("province_captured"):
        ProvinceRegistry.province_captured.connect(_on_owner_changed)

    _cam = get_viewport().get_camera_2d()
    if _cam:
        _cam.zoom_changed.connect(_on_camera_zoom_changed)


## НОВОЕ: раз в кадр проверяем, накопились ли "грязные" страны и прошло ли
## достаточно времени с последнего пересчёта — если да, обрабатываем их
## одним пакетом. Пока recompute_interval не истёк, события просто копятся
## в _dirty_countries без единого лишнего пересчёта кластеров.
func _process(delta: float) -> void:
    if _dirty_countries.is_empty():
        return

    _time_since_recompute += delta
    if _time_since_recompute < recompute_interval:
        return

    _time_since_recompute = 0.0
    _process_dirty_countries()


## Обрабатывает ОДНО событие смены владельца провинции за O(1) — без единого
## обхода province_data. Если провинция реально сменила владельца, помечает
## ТОЛЬКО старого и нового владельца как "грязных".
func _on_owner_changed(p_id: int, new_owner: String) -> void:
    _ensure_owner_cache()

    var old_owner: String = _province_owner_cache.get(p_id, "")
    if old_owner == new_owner:
        return  # никакого реального изменения — например, повторный capture_province

    var is_old_real: bool = old_owner != "" and old_owner != ProvinceRegistry.SEA_OWNER
    var is_new_real: bool = new_owner != "" and new_owner != ProvinceRegistry.SEA_OWNER

    if is_old_real and _provinces_by_country.has(old_owner):
        _provinces_by_country[old_owner].erase(p_id)
        if _provinces_by_country[old_owner].is_empty():
            _provinces_by_country.erase(old_owner)

    if is_new_real:
        if not _provinces_by_country.has(new_owner):
            _provinces_by_country[new_owner] = {}
        _provinces_by_country[new_owner][p_id] = true
        _province_owner_cache[p_id] = new_owner
    else:
        _province_owner_cache.erase(p_id)

    if is_old_real:
        _dirty_countries[old_owner] = true
    if is_new_real:
        _dirty_countries[new_owner] = true
    # Пересчёт запустится сам в _process(), не чаще recompute_interval —
    # никакого call_deferred/queue_redraw здесь специально не делаем.


func _process_dirty_countries() -> void:
    if not _has_required_data():
        return

    for country in _dirty_countries.keys():
        _recompute_country_labels(country)
    _dirty_countries.clear()

    queue_redraw()


## Строит кэш владения с нуля ОДНИМ проходом по province_data — O(провинций).
func _rebuild_owner_cache() -> void:
    _province_owner_cache.clear()
    _provinces_by_country.clear()

    for key in ProvinceRegistry.province_data:
        var p_id: int = int(key)
        var owner: String = ProvinceRegistry.province_data[key].get("owner", "")
        if owner == "" or owner == ProvinceRegistry.SEA_OWNER:
            continue

        _province_owner_cache[p_id] = owner
        if not _provinces_by_country.has(owner):
            _provinces_by_country[owner] = {}
        _provinces_by_country[owner][p_id] = true

    _cache_built = true


func _ensure_owner_cache() -> void:
    if not _cache_built:
        _rebuild_owner_cache()


func _on_camera_zoom_changed(_new_zoom: Vector2) -> void:
    queue_redraw()


## ПУБЛИЧНЫЙ метод — вызывать после массовых изменений владения "в обход"
## сигналов province_captured (например, после ProvinceRegistry.reset() в
## map.gd::restart()). ПРИНУДИТЕЛЬНО перестраивает и кэш владения, и
## кластеры АБСОЛЮТНО ВСЕХ стран, немедленно (без дебаунса).
func rebuild() -> void:
    _dirty_countries.clear()
    _time_since_recompute = 0.0

    _rebuild_owner_cache()
    _labels_by_country.clear()

    if not _has_required_data():
        queue_redraw()
        return

    for country in _provinces_by_country.keys():
        _recompute_country_labels(country)

    queue_redraw()


## Пересчитывает кластеры/геометрию ОДНОЙ страны и кладёт результат в
## _labels_by_country[country] (или убирает страну из кэша).
func _recompute_country_labels(country: String) -> void:
    if not ProvinceRegistry.countries_data.has(country):
        _labels_by_country.erase(country)
        return

    var owned_set: Dictionary = _provinces_by_country.get(country, {})
    if owned_set.is_empty():
        _labels_by_country.erase(country)
        return

    var province_centers: Dictionary = _map.province_centers

    var clusters := _find_territory_clusters(owned_set)
    if clusters.is_empty():
        _labels_by_country.erase(country)
        return

    clusters.sort_custom(func(a, b): return a.size() > b.size())
    var main_size: int = clusters[0].size()
    var display_name: String = _get_display_name(country)

    var country_labels: Array = []
    for i in clusters.size():
        var cluster: Array = clusters[i]
        if cluster.size() < min_provinces_for_label:
            continue

        var geo: Dictionary = _compute_cluster_geometry(cluster, province_centers)
        if geo.is_empty():
            continue

        country_labels.append({
            "country": country,
            "text": display_name,
            "center": geo.center,
            "angle": geo.angle,
            "width": geo.width,
            "height": geo.height,
            "is_main": i == 0,
            "ratio": float(cluster.size()) / float(max(main_size, 1)),
        })

    if country_labels.is_empty():
        _labels_by_country.erase(country)
    else:
        _labels_by_country[country] = country_labels


func _has_required_data() -> bool:
    if not is_instance_valid(_map):
        return false
    if _map.province_centers.is_empty():
        return false
    return true


## BFS/DFS по графу соседства ТОЛЬКО среди провинций owned_set этой страны.
## Принимает Dictionary{p_id: true} напрямую (это уже готовый _provinces_by_country[country]) —
## чтобы не пересобирать тот же набор заново из Array на каждый пересчёт.
func _find_territory_clusters(owned_set: Dictionary) -> Array:
    var visited: Dictionary = {}
    var clusters: Array = []

    for start_id in owned_set.keys():
        if visited.has(start_id):
            continue

        var cluster: Array = []
        var stack: Array = [start_id]
        visited[start_id] = true

        while not stack.is_empty():
            var current: int = stack.pop_back()
            cluster.append(current)

            var neighbors: Array = ProvinceMap.adjacency.get(current, [])
            for neighbor in neighbors:
                var n: int = int(neighbor)
                if owned_set.has(n) and not visited.has(n):
                    visited[n] = true
                    stack.append(n)

        clusters.append(cluster)

    return clusters


func _compute_cluster_geometry(cluster: Array, province_centers: Dictionary) -> Dictionary:
    var points: Array = []
    for pid in cluster:
        if province_centers.has(pid):
            points.append(province_centers[pid])

    if points.is_empty():
        return {}

    # Один проход: сразу считаем sum_x/sum_y и sum_xx/sum_yy/sum_xy,
    # mean и центральные вторые моменты выводим из них по формуле
    # Var(X) = E[X^2] - E[X]^2 — без отдельного прохода на центрирование.
    var sum_x := 0.0
    var sum_y := 0.0
    var sum_xx := 0.0
    var sum_yy := 0.0
    var sum_xy := 0.0
    for p in points:
        sum_x += p.x
        sum_y += p.y
        sum_xx += p.x * p.x
        sum_yy += p.y * p.y
        sum_xy += p.x * p.y

    var n: float = float(points.size())
    var mean := Vector2(sum_x / n, sum_y / n)

    if points.size() == 1:
        return {
            "center": mean,
            "angle": 0.0,
            "width": min_cluster_dimension,
            "height": min_cluster_dimension * 0.5,
        }

    var sxx: float = sum_xx / n - mean.x * mean.x
    var syy: float = sum_yy / n - mean.y * mean.y
    var sxy: float = sum_xy / n - mean.x * mean.y

    var angle := 0.0
    if abs(sxx - syy) > 0.0001 or abs(sxy) > 0.0001:
        angle = 0.5 * atan2(2.0 * sxy, sxx - syy)

    while angle > PI / 2.0:
        angle -= PI
    while angle < -PI / 2.0:
        angle += PI

    var cos_a := cos(angle)
    var sin_a := sin(angle)

    var min_u := INF
    var max_u := -INF
    var min_v := INF
    var max_v := -INF
    for p in points:
        var d: Vector2 = p - mean
        var u: float = d.x * cos_a + d.y * sin_a
        var v: float = -d.x * sin_a + d.y * cos_a
        min_u = min(min_u, u)
        max_u = max(max_u, u)
        min_v = min(min_v, v)
        max_v = max(max_v, v)

    var width: float = max_u - min_u
    var height: float = max_v - min_v

    if width < min_cluster_dimension:
        width = min_cluster_dimension
    if height < min_cluster_dimension * 0.4:
        height = min_cluster_dimension * 0.4

    return {
        "center": mean,
        "angle": angle,
        "width": width,
        "height": height,
    }


func _get_display_name(country: String) -> String:
    var data: Dictionary = ProvinceRegistry.countries_data.get(country, {})
    return tr(country.to_upper())


func _current_zoom() -> float:
    if not _cam:
        _cam = get_viewport().get_camera_2d()
    return _cam.zoom.x if _cam else 1.0


func _zoom_fade_alpha(zoom: float) -> float:
    if fade_stops.is_empty():
        return 1.0

    if zoom <= fade_stops[0].x:
        return fade_stops[0].y

    for i in range(fade_stops.size() - 1):
        var a: Vector2 = fade_stops[i]
        var b: Vector2 = fade_stops[i + 1]
        if zoom <= b.x:
            var span: float = max(b.x - a.x, 0.0001)
            var t: float = (zoom - a.x) / span
            return lerp(a.y, b.y, t)

    return fade_stops[fade_stops.size() - 1].y


func _draw() -> void:
    if _labels_by_country.is_empty():
        return

    var zoom: float = _current_zoom()

    var global_alpha: float = _zoom_fade_alpha(zoom)
    if global_alpha <= 0.001:
        return

    var use_font: Font = font if font else ThemeDB.fallback_font

    var ascent: float = use_font.get_ascent(REF_FONT_SIZE)
    var descent: float = use_font.get_descent(REF_FONT_SIZE)

    for country in _labels_by_country.keys():
        for label in _labels_by_country[country]:
            var is_main: bool = label.is_main
            var ratio: float = label.ratio

            if not is_main and ratio < minor_cluster_ratio_threshold and zoom > close_zoom_threshold:
                continue

            var text: String = label.text
            var dims: Vector2 = use_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, REF_FONT_SIZE)
            if dims.x <= 0.0 or dims.y <= 0.0:
                continue

            var cluster_scale: float = 1.0 if is_main else minor_cluster_font_scale

            var target_width: float = label.width * width_fill_ratio * cluster_scale
            var target_height: float = label.height * height_fill_ratio * cluster_scale

            var scale_by_width: float = target_width / dims.x
            var scale_by_height: float = target_height / dims.y
            var uniform_scale: float = min(scale_by_width, scale_by_height)

            var font_world_size: float = clamp(
                uniform_scale * REF_FONT_SIZE * size_scale,
                min_font_world_size,
                max_font_world_size
            )
            var eff_scale: float = font_world_size / REF_FONT_SIZE

            var xform := Transform2D(label.angle, Vector2.ZERO)
            xform.x *= eff_scale
            xform.y *= eff_scale
            xform.origin = label.center

            var local_pos: Vector2 = Vector2(-dims.x / 2.0, (ascent - descent) / 2.0)

            var text_color: Color = fill_color
            if use_country_color:
                var idx: int = ProvinceRegistry.country_index.get(label.country, -1)
                if idx >= 0 and idx < ProvinceRegistry.country_colors.size():
                    var c: Color = ProvinceRegistry.country_colors[idx]
                    text_color = Color(c.r, c.g, c.b, fill_color.a)

            var final_text_color: Color = Color(text_color.r, text_color.g, text_color.b, text_color.a * global_alpha)
            var final_outline_color: Color = Color(outline_color.r, outline_color.g, outline_color.b, outline_color.a * global_alpha)

            draw_set_transform_matrix(xform)

            if outline_width > 0:
                draw_string_outline(
                    use_font, local_pos, text,
                    HORIZONTAL_ALIGNMENT_LEFT, -1, REF_FONT_SIZE,
                    outline_width, final_outline_color
                )
            draw_string(
                use_font, local_pos, text,
                HORIZONTAL_ALIGNMENT_LEFT, -1, REF_FONT_SIZE,
                final_text_color
            )

    draw_set_transform_matrix(Transform2D.IDENTITY)
