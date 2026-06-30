shader_type canvas_item;

uniform sampler2D tech_map       : filter_nearest;
uniform sampler2D data_texture   : filter_nearest;   // r=owner_idx, a>0.5 = owned
uniform sampler2D occup_texture  : filter_nearest;   // r=occupier_idx, a>0.5 = occupied
uniform sampler2D neg_texture : filter_nearest;

uniform vec4  country_colors[256];
uniform vec3  selected_province_color = vec3(-1.0);
uniform float highlight_time = -1.0;
uniform vec2  camera_pos = vec2(0.0);
uniform vec2  texture_size = vec2(1.0);

uniform float stripe_width   : hint_range(2.0, 20.0) = 5.0;
uniform float stripe_opacity : hint_range(0.0, 1.0)  = 0.45;

uniform bool negotiation_mode = false;

void fragment() {
    vec4 mask = texture(tech_map,    UV);
    vec4 tex  = texture(TEXTURE,     UV);
    vec2 data_uv = vec2(mask.r, mask.g);

    vec4 status = texture(data_texture,  data_uv);
    vec4 occup  = texture(occup_texture, data_uv);

    // ── Базовый цвет провинции ────────────────────────────────────────────────
    vec3 base_color;
    if (status.a > 0.5) {
        int owner_idx = int(status.r * 255.0 + 0.5);
        base_color = country_colors[owner_idx].rgb;
    } else {
        base_color = tex.rgb;
    }

    // ── Оккупация: теперь используются stripe_width и stripe_opacity ────────
    if (occup.a > 0.5) {
        vec2 world_uv = UV * texture_size + camera_pos;
        float slot = mod(world_uv.y / stripe_width, 2.0);

        if (slot < 1.0) {
            // Мягко накладываем серый цвет полос с заданной прозрачностью
            base_color = mix(base_color, vec3(0.55), stripe_opacity);
        }
    }

    // ── Выделение провинции (пульсация) ──────────────────────────────────────
    int selected_r = int(selected_province_color.r * 255.0 + 0.5);
    int mask_r     = int(mask.r * 255.0 + 0.5);
    int selected_g = int(selected_province_color.g * 255.0 + 0.5);
    int mask_g     = int(mask.g * 255.0 + 0.5);
    int selected_b = int(selected_province_color.b * 255.0 + 0.5);
    int mask_b     = int(mask.b * 255.0 + 0.5);

    if (selected_r >= 0 && selected_r == mask_r && selected_g == mask_g && selected_b == mask_b) {
        float t     = highlight_time;
        float alpha = 0.2;
        if (t > 3.0) {
            float pulse = sin((t - 3.0) * 2.5) * 0.5 + 0.5;
            alpha = mix(0.05, 0.25, pulse);
        }
        base_color = mix(base_color, vec3(0.0), alpha);
    }
    
    // ── Режим переговоров: затемняем чужие провинции ─────────────────────────
    if (negotiation_mode) {
        vec4 neg = texture(neg_texture, data_uv);
        if (neg.a < 0.5) {
            base_color = base_color * 0.25;
        }
    }

    COLOR = vec4(base_color, tex.a);
}