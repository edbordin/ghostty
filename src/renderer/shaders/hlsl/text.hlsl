// For simplicity, common includes are handled manually in zig so we can keep using @embedFile
// #include "frame_constants.hlsi"

Texture2D<float> texture_grayscale : register(t0);
Texture2D<float4> texture_color : register(t1);
Buffer<float4> cell_bg_buf : register(t2);

static const uint CURSOR_WIDE = 1u;
static const uint USE_DISPLAY_P3 = 2u;
static const uint USE_LINEAR_BLENDING = 4u;
static const uint USE_LINEAR_CORRECTION = 8u;

static const uint NO_MIN_CONTRAST = 1u;
static const uint IS_CURSOR_GLYPH = 2u;

float3 srgb_to_display_p3(float3 srgb)
{
    const float3x3 srgb_to_dp3 = float3x3(
        0.8224621, 0.1775380, 0.0000000,
        0.0331941, 0.9668050, 0.0000000,
        0.0170827, 0.0723974, 0.9105199
    );
    return mul(srgb_to_dp3, srgb);
}

uint2 unpack2u16(uint packed_value)
{
    return uint2(
        packed_value & 0xFFFFu,
        (packed_value >> 16u) & 0xFFFFu
    );
}

uint4 unpack4u8(uint packed_value)
{
    return uint4(
        packed_value & 0xFFu,
        (packed_value >> 8u) & 0xFFu,
        (packed_value >> 16u) & 0xFFu,
        (packed_value >> 24u) & 0xFFu
    );
}

float linearize_channel(float v)
{
    return (v <= 0.04045) ? (v / 12.92) : pow((v + 0.055) / 1.055, 2.4);
}

float unlinearize_channel(float v)
{
    return (v <= 0.0031308) ? (v * 12.92) : (pow(v, 1.0 / 2.4) * 1.055 - 0.055);
}

float4 linearize_rgba(float4 srgb)
{
    return float4(
        linearize_channel(srgb.r),
        linearize_channel(srgb.g),
        linearize_channel(srgb.b),
        srgb.a
    );
}

float4 unlinearize_rgba(float4 linear_color)
{
    return float4(
        unlinearize_channel(linear_color.r),
        unlinearize_channel(linear_color.g),
        unlinearize_channel(linear_color.b),
        linear_color.a
    );
}

float luminance(float3 color)
{
    return dot(color, float3(0.2126, 0.7152, 0.0722));
}

float contrast_ratio(float3 color1, float3 color2)
{
    float l1 = luminance(color1) + 0.05;
    float l2 = luminance(color2) + 0.05;
    return max(l1, l2) / min(l1, l2);
}

float4 contrasted_color(float min_ratio, float4 fg, float4 bg)
{
    float ratio = contrast_ratio(fg.rgb, bg.rgb);
    if (ratio < min_ratio)
    {
        float white_ratio = contrast_ratio(float3(1.0, 1.0, 1.0), bg.rgb);
        float black_ratio = contrast_ratio(float3(0.0, 0.0, 0.0), bg.rgb);
        if (white_ratio > black_ratio)
        {
            return float4(1.0, 1.0, 1.0, 1.0);
        }
        return float4(0.0, 0.0, 0.0, 1.0);
    }

    return fg;
}

float4 load_color(uint4 in_color, bool display_p3, bool use_linear_output)
{
    float4 color = float4(in_color) / 255.0;
    if (display_p3 && !use_linear_output)
    {
        color.rgb *= color.a;
        return color;
    }

    color = linearize_rgba(color);
    if (!display_p3)
    {
        color.rgb = srgb_to_display_p3(color.rgb);
    }

    if (!use_linear_output)
    {
        color = unlinearize_rgba(color);
    }

    color.rgb *= color.a;
    return color;
}

float4 unlinearize_premul(float4 premul_linear)
{
    if (premul_linear.a <= 0.0)
    {
        return float4(0.0, 0.0, 0.0, 0.0);
    }

    float4 color = premul_linear;
    color.rgb /= color.a;
    color = unlinearize_rgba(color);
    color.rgb *= color.a;
    return color;
}

float4 load_color_float(float4 in_color, bool display_p3, bool use_linear_output)
{
    float4 color = in_color;
    if (display_p3 && !use_linear_output)
    {
        color.rgb *= color.a;
        return color;
    }

    color = linearize_rgba(color);
    if (!display_p3)
    {
        color.rgb = srgb_to_display_p3(color.rgb);
    }

    if (!use_linear_output)
    {
        color = unlinearize_rgba(color);
    }

    color.rgb *= color.a;
    return color;
}

struct VSIn
{
    uint2 glyph_pos : GLYPH_POS;
    uint2 glyph_size : GLYPH_SIZE;
    int2 bearings : BEARINGS;
    uint2 grid_pos : GRID_POS;
    float4 color : COLOR;
    uint atlas : ATLAS;
    uint glyph_bools : GLYPH_BOOLS;
};

struct VSOut
{
    float4 position : SV_Position;
    nointerpolation float4 color : COLOR0;
    nointerpolation float4 bg_color : COLOR1;
    nointerpolation uint atlas : ATLAS;
    nointerpolation uint glyph_bools : GLYPH_BOOLS;
    float2 tex_coord : TEXCOORD0;
};

VSOut VSMain(VSIn input, uint vid : SV_VertexID)
{
    float2 corner = float2((vid == 1u || vid == 3u) ? 1.0 : 0.0, (vid >= 2u) ? 1.0 : 0.0);
    float2 cell_pos = cell_size * float2(input.grid_pos);
    float2 size = float2(input.glyph_size);
    float2 offset = float2(input.bearings);
    offset.y = cell_size.y - offset.y;
    float2 pos = cell_pos + size * corner + offset;

    VSOut outv;
    outv.position = mul(projection_matrix, float4(pos, 0.0, 1.0));
    outv.atlas = input.atlas;
    outv.glyph_bools = input.glyph_bools;
    outv.tex_coord = float2(input.glyph_pos) + float2(input.glyph_size) * corner;

    uint2 grid_size = unpack2u16(grid_size_packed_2u16);
    uint2 cursor_pos = unpack2u16(cursor_pos_packed_2u16);
    bool cursor_wide = (bools & CURSOR_WIDE) != 0u;
    bool use_display_p3 = (bools & USE_DISPLAY_P3) != 0u;

    outv.color = load_color_float(input.color, use_display_p3, true);

    const bool has_grid = (grid_size.x > 0u && grid_size.y > 0u);
    uint index = has_grid ? (input.grid_pos.y * grid_size.x + input.grid_pos.x) : 0u;
    float4 cell_color = has_grid ? cell_bg_buf[index] : float4(0.0, 0.0, 0.0, 0.0);
    float4 bg_color = load_color_float(cell_color, use_display_p3, true);

    float4 global_bg = load_color(unpack4u8(bg_color_packed_4u8), use_display_p3, true);
    outv.bg_color = bg_color + global_bg * (1.0 - bg_color.a);

    if (min_contrast > 1.0 && (input.glyph_bools & NO_MIN_CONTRAST) == 0u)
    {
        outv.color = contrasted_color(min_contrast, outv.color, outv.bg_color);
    }

    bool is_cursor_pos = (
        (input.grid_pos.x == cursor_pos.x) ||
        (cursor_wide && input.grid_pos.x == (cursor_pos.x + 1u))
    ) && (input.grid_pos.y == cursor_pos.y);

    if ((input.glyph_bools & IS_CURSOR_GLYPH) == 0u && is_cursor_pos)
    {
        outv.color = load_color(unpack4u8(cursor_color_packed_4u8), use_display_p3, true);
    }

    return outv;
}

float4 PSMain(VSOut input) : SV_Target
{
    bool use_linear_blending = (bools & USE_LINEAR_BLENDING) != 0u;
    bool use_linear_correction = (bools & USE_LINEAR_CORRECTION) != 0u;

    int2 coord = int2(input.tex_coord);
    if (input.atlas == 0u)
    {
        float4 color = input.color;
        if (!use_linear_blending)
        {
            color = unlinearize_premul(color);
        }

        float a = texture_grayscale.Load(int3(coord, 0)).r;
        if (use_linear_correction)
        {
            float4 bg = input.bg_color;
            float fg_l = luminance(color.rgb);
            float bg_l = luminance(bg.rgb);
            if (abs(fg_l - bg_l) > 0.001)
            {
                float blend_l = linearize_channel(
                    unlinearize_channel(fg_l) * a + unlinearize_channel(bg_l) * (1.0 - a)
                );
                a = clamp((blend_l - bg_l) / (fg_l - bg_l), 0.0, 1.0);
            }
        }

        color *= a;
        return color;
    }

    float4 color = texture_color.Load(int3(coord, 0));
    if (use_linear_blending)
    {
        return color;
    }
    return unlinearize_premul(color);
}
