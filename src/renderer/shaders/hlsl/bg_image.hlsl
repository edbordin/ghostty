// For simplicity, common includes are handled manually in zig so we can keep using @embedFile
// #include "frame_constants.hlsi"

Texture2D<float4> image_tex : register(t0);
SamplerState image_sampler : register(s0);

static const uint USE_LINEAR_BLENDING = 4u;
static const uint USE_DISPLAY_P3 = 2u;

static const uint BG_IMAGE_POSITION_MASK = 15u;
static const uint BG_IMAGE_TL = 0u;
static const uint BG_IMAGE_TC = 1u;
static const uint BG_IMAGE_TR = 2u;
static const uint BG_IMAGE_ML = 3u;
static const uint BG_IMAGE_MC = 4u;
static const uint BG_IMAGE_MR = 5u;
static const uint BG_IMAGE_BL = 6u;
static const uint BG_IMAGE_BC = 7u;
static const uint BG_IMAGE_BR = 8u;

static const uint BG_IMAGE_FIT_MASK = (3u << 4u);
static const uint BG_IMAGE_CONTAIN = (0u << 4u);
static const uint BG_IMAGE_COVER = (1u << 4u);
static const uint BG_IMAGE_STRETCH = (2u << 4u);
static const uint BG_IMAGE_NONE = (3u << 4u);

static const uint BG_IMAGE_REPEAT = (1u << 6u);

float3 srgb_to_display_p3(float3 srgb)
{
    const float3x3 srgb_to_dp3 = float3x3(
        0.8224621, 0.1775380, 0.0000000,
        0.0331941, 0.9668050, 0.0000000,
        0.0170827, 0.0723974, 0.9105199
    );
    return mul(srgb_to_dp3, srgb);
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

uint4 unpack4u8(uint packed)
{
    return uint4(
        packed & 0xFFu,
        (packed >> 8u) & 0xFFu,
        (packed >> 16u) & 0xFFu,
        (packed >> 24u) & 0xFFu
    );
}

float4 load_color(uint packed, bool display_p3, bool use_linear_output)
{
    float4 color = float4(unpack4u8(packed)) / 255.0;
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
    float opacity : OPACITY;
    uint info : INFO;
};

struct VSOut
{
    float4 position : SV_Position;
    nointerpolation float4 bg_color : BGCOLOR;
    nointerpolation float2 offset : OFFSET;
    nointerpolation float2 scale : SCALE;
    nointerpolation float opacity : OPACITY;
    nointerpolation uint repeat : REPEAT;
};

VSOut VSMain(VSIn input, uint vertex_id : SV_VertexID)
{
    bool use_linear_blending = (bools & USE_LINEAR_BLENDING) != 0u;
    bool use_display_p3 = (bools & USE_DISPLAY_P3) != 0u;

    float2 position = float2(
        (vertex_id == 2u) ? 3.0 : -1.0,
        (vertex_id == 1u) ? 3.0 : -1.0
    );

    VSOut output;
    output.position = float4(position, 0.0, 1.0);
    output.opacity = input.opacity;
    output.repeat = input.info & BG_IMAGE_REPEAT;

    uint tex_w;
    uint tex_h;
    image_tex.GetDimensions(tex_w, tex_h);
    float2 tex_size = float2(tex_w, tex_h);

    float2 dest_size = tex_size;
    uint fit_mode = input.info & BG_IMAGE_FIT_MASK;
    if (fit_mode == BG_IMAGE_CONTAIN)
    {
        float fit_scale = min(screen_size.x / tex_size.x, screen_size.y / tex_size.y);
        dest_size = tex_size * fit_scale;
    }
    else if (fit_mode == BG_IMAGE_COVER)
    {
        float fit_scale = max(screen_size.x / tex_size.x, screen_size.y / tex_size.y);
        dest_size = tex_size * fit_scale;
    }
    else if (fit_mode == BG_IMAGE_STRETCH)
    {
        dest_size = screen_size;
    }
    else if (fit_mode == BG_IMAGE_NONE)
    {
        dest_size = tex_size;
    }

    float2 start = float2(0.0, 0.0);
    float2 mid = (screen_size - dest_size) / 2.0;
    float2 end = screen_size - dest_size;

    float2 dest_offset = mid;
    uint pos_mode = input.info & BG_IMAGE_POSITION_MASK;
    if (pos_mode == BG_IMAGE_TL)
    {
        dest_offset = float2(start.x, start.y);
    }
    else if (pos_mode == BG_IMAGE_TC)
    {
        dest_offset = float2(mid.x, start.y);
    }
    else if (pos_mode == BG_IMAGE_TR)
    {
        dest_offset = float2(end.x, start.y);
    }
    else if (pos_mode == BG_IMAGE_ML)
    {
        dest_offset = float2(start.x, mid.y);
    }
    else if (pos_mode == BG_IMAGE_MC)
    {
        dest_offset = float2(mid.x, mid.y);
    }
    else if (pos_mode == BG_IMAGE_MR)
    {
        dest_offset = float2(end.x, mid.y);
    }
    else if (pos_mode == BG_IMAGE_BL)
    {
        dest_offset = float2(start.x, end.y);
    }
    else if (pos_mode == BG_IMAGE_BC)
    {
        dest_offset = float2(mid.x, end.y);
    }
    else if (pos_mode == BG_IMAGE_BR)
    {
        dest_offset = float2(end.x, end.y);
    }

    output.offset = dest_offset;
    output.scale = tex_size / dest_size;

    uint4 bg_u8 = unpack4u8(bg_color_packed_4u8);
    float3 bg_rgb = load_color(
        (bg_u8.x) | (bg_u8.y << 8u) | (bg_u8.z << 16u) | (255u << 24u),
        use_display_p3,
        use_linear_blending
    ).rgb;
    output.bg_color = float4(bg_rgb, float(bg_u8.w) / 255.0);

    return output;
}

float4 PSMain(VSOut input, float4 position : SV_Position) : SV_Target
{
    bool use_linear_blending = (bools & USE_LINEAR_BLENDING) != 0u;

    uint tex_w;
    uint tex_h;
    image_tex.GetDimensions(tex_w, tex_h);
    float2 tex_size = float2(tex_w, tex_h);

    float2 tex_coord = (position.xy - input.offset) * input.scale;

    if (input.repeat != 0u)
    {
        tex_coord = fmod(fmod(tex_coord, tex_size) + tex_size, tex_size);
    }

    float4 rgba;
    if (any(tex_coord < 0.0) || any(tex_coord > tex_size))
    {
        rgba = float4(0.0, 0.0, 0.0, 0.0);
    }
    else
    {
        rgba = image_tex.Sample(image_sampler, tex_coord / tex_size);
        if (!use_linear_blending)
        {
            rgba = unlinearize_rgba(rgba);
        }
        rgba.rgb *= rgba.a;
    }

    rgba *= min(input.opacity, 1.0 / input.bg_color.a);
    rgba += max(float4(0.0, 0.0, 0.0, 0.0), float4(input.bg_color.rgb, 1.0) * (1.0 - rgba.a));
    rgba *= input.bg_color.a;

    return rgba;
}
