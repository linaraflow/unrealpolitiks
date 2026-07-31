extends Node2D
## Одноразовая анимация "удара" при попадании ракеты/БПЛА по провинции:
## маленькая яркая красная точка в центре + красное зарево вокруг неё.
## Искры (CPUParticles2D) отключены по умолчанию, но их можно включить
## флагом WITH_SPARKS ниже.
##
## Полностью самодостаточна: генерирует свои текстуры в коде, никаких
## внешних ассетов не требует. Добавляется как child в Map в той же
## локальной системе координат, что и province_centers/missile.
##
## Использование:
##   var fx = preload("res://scripts/explosion_effect.gd").new()
##   fx.position = Map.province_centers[p_id]
##   Map.add_child(fx)

## Включить/выключить разлетающиеся искры вокруг точки удара.
const WITH_SPARKS: bool = false

const DOT_LIFETIME: float = 1.0     # яркая красная точка в центре
const GLOW_LIFETIME: float = 1.2    # красное зарево вокруг
const PARTICLE_LIFETIME: float = 0.5
const TOTAL_LIFETIME: float = 1.6   # когда узел самоуничтожится

const DOT_MAX_SCALE: float = 0.18   # точка совсем маленькая
const GLOW_MAX_SCALE: float = 0.7   # зарево компактнее, чуть шире точки
const BASE_PIXEL_SIZE: int = 64     # размер сгенерированной текстуры (px)

var _dot: Sprite2D
var _glow: Sprite2D
var _particles: CPUParticles2D


func _ready() -> void:
    z_index = 100  # поверх карты и границ

    var soft_tex := _make_radial_texture(BASE_PIXEL_SIZE)

    # ── Красное зарево вокруг точки (широкое, мягкое, гаснет медленнее) ──
    _glow = Sprite2D.new()
    _glow.texture = soft_tex
    _glow.modulate = Color(1.0, 0.15, 0.1, 0.95)
    _glow.scale = Vector2.ZERO
    add_child(_glow)

    # ── Яркая маленькая почти-белая точка в центре ────────────────────
    # (специально светлее самого зарева — так она сильнее "выстреливает"
    # на глаз, как раскалённое ядро внутри красного облака)
    _dot = Sprite2D.new()
    _dot.texture = soft_tex
    _dot.modulate = Color(1.0, 0.92, 0.85, 1.0)
    _dot.scale = Vector2.ZERO
    add_child(_dot)

    if WITH_SPARKS:
        _particles = CPUParticles2D.new()
        _particles.texture = _make_radial_texture(16)
        _particles.amount = 14
        _particles.lifetime = PARTICLE_LIFETIME
        _particles.one_shot = true
        _particles.explosiveness = 1.0
        _particles.emitting = true
        _particles.direction = Vector2.UP
        _particles.spread = 180.0
        _particles.gravity = Vector2.ZERO
        _particles.initial_velocity_min = 30.0
        _particles.initial_velocity_max = 100.0
        _particles.scale_amount_min = 0.25
        _particles.scale_amount_max = 0.6
        _particles.color = Color(1.0, 0.25, 0.15, 1.0)
        var grad := Gradient.new()
        grad.set_color(0, Color(1.0, 0.4, 0.2, 1.0))
        grad.set_color(1, Color(0.8, 0.05, 0.05, 0.0))
        _particles.color_ramp = grad
        add_child(_particles)

    _animate()


func _animate() -> void:
    var tw := create_tween()
    tw.set_parallel(true)

    # Точка: быстро появляется, держится ярко, затем гаснет
    tw.tween_property(_dot, "scale", Vector2.ONE * DOT_MAX_SCALE, DOT_LIFETIME * 0.25) \
        .set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
    tw.tween_property(_dot, "modulate:a", 0.0, DOT_LIFETIME * 0.6) \
        .set_delay(DOT_LIFETIME * 0.4)

    # Зарево: расширяется медленнее и гаснет плавнее, чем точка
    tw.tween_property(_glow, "scale", Vector2.ONE * GLOW_MAX_SCALE, GLOW_LIFETIME * 0.5) \
        .set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
    tw.tween_property(_glow, "modulate:a", 0.0, GLOW_LIFETIME * 0.7) \
        .set_delay(GLOW_LIFETIME * 0.3)

    # Подстраховка: гарантированно убираем узел через TOTAL_LIFETIME,
    # даже если что-то пошло не так с tween'ами.
    var timer := get_tree().create_timer(TOTAL_LIFETIME)
    timer.timeout.connect(func():
        if is_instance_valid(self):
            queue_free()
    )


## Генерирует мягкую радиальную текстуру (белый центр -> прозрачный край),
## чтобы не тянуть внешние PNG. Используется и для вспышки, и для частиц.
func _make_radial_texture(size: int) -> ImageTexture:
    var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
    var center := Vector2(size / 2.0, size / 2.0)
    var max_dist := size / 2.0

    for y in size:
        for x in size:
            var dist := Vector2(x, y).distance_to(center) / max_dist
            var a = clamp(1.0 - dist, 0.0, 1.0)
            a = pow(a, 1.6)  # чуть более плотное ядро, мягкий спад к краю
            img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))

    return ImageTexture.create_from_image(img)
