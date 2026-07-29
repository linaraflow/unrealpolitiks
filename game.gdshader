shader_type canvas_item;

uniform sampler2D tech_map       : filter_nearest;
uniform sampler2D data_texture   : filter_nearest;   // r=owner_idx, a>0.5 = owned
uniform sampler2D occup_texture  : filter_nearest;   // r=occupier_idx, a>0.5 = occupied
uniform sampler2D neg_texture : filter_nearest;
uniform sampler2D uav_texture : filter_nearest;
uniform sampler2D distribute_texture : filter_nearest;
uniform bool distribute_mode = false;
uniform sampler2D capital_texture : filter_nearest;  // a>0.5 = провинция является столицей

// ── Режимы карты (экономика и т.п.): r=нормализованное значение 0..1, a>0.5 = участвует ──
uniform sampler2D mode_texture : filter_nearest;
uniform bool  map_mode_active = false;
uniform vec3  mode_color_low  : source_color = vec3(1.0, 1.0, 1.0);   // белый  = 0 фабрик
uniform vec3  mode_color_high : source_color = vec3(1.0, 0.55, 0.0);  // оранжевый = много фабрик

uniform vec4  country_colors[256];
uniform vec3  selected_province_color = vec3(-1.0);
uniform float highlight_time = -1.0;
uniform vec2  camera_pos = vec2(0.0);
uniform vec2  texture_size = vec2(1.0);

// ── Зелёная вспышка "завод построен" ─────────────────────────────────────────
// Кольцевой буфер из FLASH_SLOTS одновременных подсветок. Незанятый слот
// имеет flash_ids[i] == vec3(0.0), что соответствует id=0 (море/игнор),
// поэтому он никогда не совпадёт с реальной провинцией.
const int FLASH_SLOTS = 8;
const float FLASH_DURATION = 2.5; // сек: время полного цикла вспышки
uniform vec3  flash_ids[FLASH_SLOTS];
uniform float flash_starts[FLASH_SLOTS];
uniform float game_time = 0.0;
uniform vec4  flash_color : source_color = vec4(0.15, 1.0, 0.25, 1.0);

// ── Красная вспышка "удар ракетой / БПЛА" ─────────────────────────────────────
// Работает точно так же, как зелёная вспышка выше, но со своим отдельным
// кольцевым буфером слотов и цветом — чтобы обе вспышки могли идти
// одновременно и не конфликтовали друг с другом.
uniform vec3  red_flash_ids[FLASH_SLOTS];
uniform float red_flash_starts[FLASH_SLOTS];
uniform vec4  red_flash_color : source_color = vec4(1.0, 0.15, 0.1, 1.0);

uniform float stripe_width   : hint_range(2.0, 20.0) = 5.0;
uniform float stripe_opacity : hint_range(0.0, 1.0)  = 0.45;

uniform bool negotiation_mode = false;
uniform bool uav_mode = false;

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

    // ── Режим карты (экономика и т.п.): перекрашиваем сушу белый→оранжевый ────
    // Применяется ПОСЛЕ базового цвета страны, но ДО границ/подсветок/вспышек,
    // поэтому границы, выделение и вспышки остаются видимыми поверх режима.
    if (map_mode_active && status.a > 0.5) {
        vec4 mode_status = texture(mode_texture, data_uv);
        if (mode_status.a > 0.5) {
            base_color = mix(mode_color_low, mode_color_high, mode_status.r);
        }
    }

    // ── Границы провинций/стран: считаем ЗАРАНЕЕ ──────────────────────────────
    // (нужно ещё до подсветок, чтобы они не закрашивали саму линию границы)
    bool is_province_edge = false;
    bool is_country_edge  = false;
    if (draw_borders) {
        vec2 texel = 1.0 / vec2(textureSize(tech_map, 0));

        // own_is_sea = пиксель НЕ закрашен в data_texture: это либо старый фон (id 0),
        // либо новая провинция-море (owner == "sea" — её мы намеренно не пишем
        // в data_texture в map.gd, см. _paint_all_provinces_from_data).
        bool own_is_sea = status.a <= 0.5;

        // ── Тонкая граница провинций (любое различие id соседа) ───────────────
        // Для столичной провинции берём увеличенную ширину — та же линия, но толще,
        // и теперь это СПЛОШНАЯ полоса (сканируем каждый тексель от границы вглубь,
        // а не проверяем только одну точку на фиксированном расстоянии).
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

                // Раньше тут была грубая проверка "n.r+n.g+n.b > 0.0" (проверяла
                // только старый фон id==0). Теперь смотрим напрямую в data_texture:
                // это правильно исключает и фон, и провинции-море из соседей.
                bool n0_is_sea = texture(data_texture, vec2(n0.r, n0.g)).a <= 0.5;
                bool n1_is_sea = texture(data_texture, vec2(n1.r, n1.g)).a <= 0.5;
                bool n2_is_sea = texture(data_texture, vec2(n2.r, n2.g)).a <= 0.5;
                bool n3_is_sea = texture(data_texture, vec2(n3.r, n3.g)).a <= 0.5;

                if (any(notEqual(mask.rgb, n0.rgb)) && (draw_coast_border || (!own_is_sea && !n0_is_sea))) is_province_edge = true;
                if (any(notEqual(mask.rgb, n1.rgb)) && (draw_coast_border || (!own_is_sea && !n1_is_sea))) is_province_edge = true;
                if (any(notEqual(mask.rgb, n2.rgb)) && (draw_coast_border || (!own_is_sea && !n2_is_sea))) is_province_edge = true;
                if (any(notEqual(mask.rgb, n3.rgb)) && (draw_coast_border || (!own_is_sea && !n3_is_sea))) is_province_edge = true;

                if (is_province_edge) break;
            }
        }

        // ── Толстая граница стран (сосед принадлежит другому владельцу) ───────
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
    }
    bool is_border_pixel = is_province_edge || is_country_edge;

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

    if (!is_border_pixel && selected_r >= 0 && selected_r == mask_r && selected_g == mask_g && selected_b == mask_b) {
        float t     = highlight_time;
        float alpha = 0.2;
        if (t > 3.0) {
            float pulse = sin((t - 3.0) * 2.5) * 0.5 + 0.5;
            alpha = mix(0.05, 0.25, pulse);
        }
        base_color = mix(base_color, vec3(0.0), alpha);
    }

    // ── Зелёная вспышка "завод построен" ──────────────────────────────────────
    // is_border_pixel исключает саму линию границы, чтобы подсветка
    // не "вылезала" за пределы провинции и не просвечивала сквозь неё.
    if (!is_border_pixel) {
        for (int i = 0; i < FLASH_SLOTS; i++) {
            int flash_r = int(flash_ids[i].r * 255.0 + 0.5);
            int flash_g = int(flash_ids[i].g * 255.0 + 0.5);
            int flash_b = int(flash_ids[i].b * 255.0 + 0.5);

            bool id_match = (flash_r != 0 || flash_g != 0 || flash_b != 0)
                && flash_r == mask_r && flash_g == mask_g && flash_b == mask_b;

            if (id_match) {
                float t = game_time - flash_starts[i];
                if (t >= 0.0 && t < FLASH_DURATION) {
                    // Быстрый плавный подъём и такое же плавное угасание
                    float progress = t / FLASH_DURATION;
                    float envelope = sin(progress * 3.14159265);
                    base_color = mix(base_color, flash_color.rgb, envelope * flash_color.a);
                }
            }
        }
    }

    // ── Красная вспышка "удар ракетой / БПЛА" ──────────────────────────────────
    // Полностью аналогична зелёной вспышке выше, но со своим буфером слотов
    // и своим цветом — благодаря этому подсветки удара и постройки завода
    // могут идти на разных (или даже на одной) провинциях одновременно.
    if (!is_border_pixel) {
        for (int i = 0; i < FLASH_SLOTS; i++) {
            int flash_r = int(red_flash_ids[i].r * 255.0 + 0.5);
            int flash_g = int(red_flash_ids[i].g * 255.0 + 0.5);
            int flash_b = int(red_flash_ids[i].b * 255.0 + 0.5);

            bool id_match = (flash_r != 0 || flash_g != 0 || flash_b != 0)
                && flash_r == mask_r && flash_g == mask_g && flash_b == mask_b;

            if (id_match) {
                float t = game_time - red_flash_starts[i];
                if (t >= 0.0 && t < FLASH_DURATION) {
                    float progress = t / FLASH_DURATION;
                    float envelope = sin(progress * 3.14159265);
                    base_color = mix(base_color, red_flash_color.rgb, envelope * red_flash_color.a);
                }
            }
        }
    }

    // ── Режим переговоров: затемняем чужие провинции ─────────────────────────
    if (negotiation_mode) {
        vec4 neg = texture(neg_texture, data_uv);
        if (neg.a < 0.5) {
            base_color = base_color * 0.25;
        }
    }

    // ── Режим запуска БПЛА: затемняем всё, кроме своих провинций и провинций врагов ──
    if (uav_mode) {
        vec4 uav = texture(uav_texture, data_uv);
        if (uav.a < 0.5) {
            base_color = base_color * 0.25;
        }
    }
    
    // ── Режим распределения дивизий: подсвечиваем выбранные провинции ─────────
    // Используем тот же визуальный стиль, что и обычное статичное выделение
    // провинции (чёрный тинт alpha=0.2), чтобы выглядело как "selected".
    if (distribute_mode && !is_border_pixel) {
        vec4 dstat = texture(distribute_texture, data_uv);
        if (dstat.a > 0.5) {
            base_color = mix(base_color, vec3(0.0), 0.2);
        }
    }

    // ── Границы провинций/стран: применяем цвет ───────────────────────────────
    if (draw_borders) {
        if (is_country_edge) {
            base_color = mix(base_color, country_border_color.rgb, country_border_color.a);
        } else if (is_province_edge) {
            base_color = mix(base_color, province_border_color.rgb, province_border_color.a);
        }
    }

    COLOR = vec4(base_color, tex.a);
}