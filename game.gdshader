shader_type canvas_item;

uniform sampler2D tech_map       : filter_nearest;
uniform sampler2D data_texture   : filter_nearest;   // r=owner_idx, a>0.5 = owned
uniform sampler2D occup_texture  : filter_nearest;   // r=occupier_idx, a>0.5 = occupied
uniform sampler2D neg_texture : filter_nearest;
uniform sampler2D capital_texture : filter_nearest;  // a>0.5 = провинция является столицей

uniform vec4  country_colors[256];
uniform vec3  selected_province_color = vec3(-1.0);
uniform float highlight_time = -1.0;
uniform vec2  camera_pos = vec2(0.0);
uniform vec2  texture_size = vec2(1.0);

uniform float stripe_width   : hint_range(2.0, 20.0) = 5.0;
uniform float stripe_opacity : hint_range(0.0, 1.0)  = 0.45;

uniform bool negotiation_mode = false;

// ── Границы провинций/стран ──────────────────────────────────────────────────
uniform bool  draw_borders          = true;
uniform bool  draw_coast_border     = false;   // рисовать ли границу суша/море
uniform vec4  province_border_color : source_color = vec4(0.0, 0.0, 0.0, 0.35);
uniform float province_border_width : hint_range(0.5, 4.0) = 1.0;   // в тексклях tech_map
uniform vec4  country_border_color  : source_color = vec4(0.0, 0.0, 0.0, 0.85);
uniform float country_border_width  : hint_range(0.5, 6.0) = 2.0;   // в тексклях tech_map

// ── Столичные провинции: та же граница провинции, но ШИРЕ ───────────────────
uniform float capital_border_width : hint_range(0.5, 12.0) = 3.0;   // в тексклях tech_map, вместо province_border_width для столиц

void fragment() {
    vec4 mask = texture(tech_map,    UV);
    vec4 tex  = texture(TEXTURE,     UV);
    vec2 data_uv = vec2(mask.r, mask.g);

    vec4 status = texture(data_texture,  data_uv);
    vec4 occup  = texture(occup_texture, data_uv);
    vec4 capital_status = texture(capital_texture, data_uv);
    bool is_capital_province = capital_status.a > 0.5;
    int  owner_idx_for_border = int(status.r * 255.0 + 0.5);

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

    // ── Границы провинций/стран ──────────────────────────────────────────────
    if (draw_borders) {
        vec2 texel = 1.0 / vec2(textureSize(tech_map, 0));

        int own_id = int(mask.r * 255.0 + 0.5) | (int(mask.g * 255.0 + 0.5) << 8) | (int(mask.b * 255.0 + 0.5) << 16);
        bool own_is_sea = (own_id == 0);

        // ── Тонкая граница провинций (любое различие id соседа) ───────────────
        // Для столичной провинции берём увеличенную ширину — та же линия, но толще,
        // и теперь это СПЛОШНАЯ полоса (сканируем каждый тексель от границы вглубь,
        // а не проверяем только одну точку на фиксированном расстоянии).
        bool is_province_edge = false;
        {
            float used_width = is_capital_province ? capital_border_width : province_border_width;
            int steps = int(ceil(used_width));

            for (int i = 1; i <= 12; i++) {
                if (i > steps) break;

                vec2 pw = texel * float(i);
                vec4 n0 = texture(tech_map, UV + vec2( pw.x, 0.0));
                vec4 n1 = texture(tech_map, UV + vec2(-pw.x, 0.0));
                vec4 n2 = texture(tech_map, UV + vec2(0.0,  pw.y));
                vec4 n3 = texture(tech_map, UV + vec2(0.0, -pw.y));

                if (any(notEqual(mask.rgb, n0.rgb)) && (draw_coast_border || (!own_is_sea && n0.r + n0.g + n0.b > 0.0))) is_province_edge = true;
                if (any(notEqual(mask.rgb, n1.rgb)) && (draw_coast_border || (!own_is_sea && n1.r + n1.g + n1.b > 0.0))) is_province_edge = true;
                if (any(notEqual(mask.rgb, n2.rgb)) && (draw_coast_border || (!own_is_sea && n2.r + n2.g + n2.b > 0.0))) is_province_edge = true;
                if (any(notEqual(mask.rgb, n3.rgb)) && (draw_coast_border || (!own_is_sea && n3.r + n3.g + n3.b > 0.0))) is_province_edge = true;

                if (is_province_edge) break;
            }
        }

        // ── Толстая граница стран (сосед принадлежит другому владельцу) ───────
        bool is_country_edge = false;
        {
            vec2 cw = texel * country_border_width;
            vec4 n0 = texture(tech_map, UV + vec2( cw.x, 0.0));
            vec4 n1 = texture(tech_map, UV + vec2(-cw.x, 0.0));
            vec4 n2 = texture(tech_map, UV + vec2(0.0,  cw.y));
            vec4 n3 = texture(tech_map, UV + vec2(0.0, -cw.y));

            if (status.a > 0.5) {
                vec4 s0 = texture(data_texture, vec2(n0.r, n0.g));
                vec4 s1 = texture(data_texture, vec2(n1.r, n1.g));
                vec4 s2 = texture(data_texture, vec2(n2.r, n2.g));
                vec4 s3 = texture(data_texture, vec2(n3.r, n3.g));

                if (any(notEqual(mask.rgb, n0.rgb)) && s0.a > 0.5 && int(s0.r * 255.0 + 0.5) != owner_idx_for_border) is_country_edge = true;
                if (any(notEqual(mask.rgb, n1.rgb)) && s1.a > 0.5 && int(s1.r * 255.0 + 0.5) != owner_idx_for_border) is_country_edge = true;
                if (any(notEqual(mask.rgb, n2.rgb)) && s2.a > 0.5 && int(s2.r * 255.0 + 0.5) != owner_idx_for_border) is_country_edge = true;
                if (any(notEqual(mask.rgb, n3.rgb)) && s3.a > 0.5 && int(s3.r * 255.0 + 0.5) != owner_idx_for_border) is_country_edge = true;
            }
        }

        if (is_country_edge) {
            base_color = mix(base_color, country_border_color.rgb, country_border_color.a);
        } else if (is_province_edge) {
            base_color = mix(base_color, province_border_color.rgb, province_border_color.a);
        }
    }

    COLOR = vec4(base_color, tex.a);
}