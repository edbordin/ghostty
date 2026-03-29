// For simplicity, common includes are handled manually in zig so we can keep using @embedFile
// #include "frame_constants.hlsi"

static const uint USE_LINEAR_BLENDING = 4u;
static const uint USE_DISPLAY_P3 = 2u;

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

uint4 unpack4u8(uint packed)
{
    return uint4(
        packed & 0xFFu,
        (packed >> 8u) & 0xFFu,
        (packed >> 16u) & 0xFFu,
        (packed >> 24u) & 0xFFu
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

struct VSOut
{
    float4 position : SV_Position;
};

VSOut VSMain(uint vertex_id : SV_VertexID)
{
    VSOut output;
    float2 position = float2(
        (vertex_id == 2u) ? 3.0 : -1.0,
        (vertex_id == 1u) ? 3.0 : -1.0
    );
    output.position = float4(position, 0.0, 1.0);
    return output;
}

float4 PSMain() : SV_Target
{
    bool use_linear_blending = (bools & USE_LINEAR_BLENDING) != 0u;
    bool use_display_p3 = (bools & USE_DISPLAY_P3) != 0u;
    return load_color(bg_color_packed_4u8, use_display_p3, use_linear_blending);
}
