shader_type canvas_item;

// Текстура экрана под ColorRect
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

// Настройки эффекта
uniform float blur_amount : hint_range(0.0, 5.0) = 5;
uniform float distortion_strength : hint_range(0.0, 0.1) = 0.03;
uniform vec4 tint_color : source_color = vec4(1.0, 1.0, 1.0, 0.1);
uniform vec4 edge_color : source_color = vec4(1.0, 1.0, 1.0, 0.6);
uniform float edge_thickness : hint_range(0.0, 0.5) = 0.05;

void fragment() {
    // Вектор от центра к текущему UV (от -0.5 до 0.5)
    vec2 center_uv = UV - vec2(0.5);
    
    // Создаем выпуклое искажение (эффект линзы/жидкого стекла)
    float distort = pow(length(center_uv), 2.0) * distortion_strength;
    vec2 distorted_uv = SCREEN_UV + (center_uv * distort);
    
    // Считываем размытый фон с учетом искажения
    vec4 glass_bg = textureLod(screen_texture, distorted_uv, blur_amount);
    
    // Рассчитываем маску для блика по краям
    float edge_mask = smoothstep(0.5 - edge_thickness, 0.5, max(abs(center_uv.x), abs(center_uv.y)));
    
    // Смешиваем фон, тонирование и подсветку краев
    vec4 final_color = mix(glass_bg, tint_color, tint_color.a);
    final_color = mix(final_color, edge_color, edge_mask * edge_color.a);
    
    COLOR = final_color;
}