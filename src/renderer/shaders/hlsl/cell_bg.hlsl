// For simplicity, common includes are handled manually in zig so we can keep using @embedFile
// #include "frame_constants.hlsi"

Buffer<float4> cell_bg_buf : register(t2);

static const uint EXTEND_LEFT = 1u;
static const uint EXTEND_RIGHT = 2u;
static const uint EXTEND_UP = 4u;
static const uint EXTEND_DOWN = 8u;
static const uint USE_DISPLAY_P3 = 2u;
static const uint USE_LINEAR_BLENDING = 4u;

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

float linearize_channel(float v)
{
    return (v <= 0.04045) ? (v / 12.92) : pow((v + 0.055) / 1.055, 2.4);
}

float unlinearize_channel(float v)
{
    return (v <= 0.0031308) ? (v * 12.92) : (pow(v, 1.0 / 2.4) * 1.055 - 0.055);
}

float4 linearize_color(float4 color)
{
    return float4(
        linearize_channel(color.r),
        linearize_channel(color.g),
        linearize_channel(color.b),
        color.a
    );
}

float4 unlinearize_color(float4 color)
{
    return float4(
        unlinearize_channel(color.r),
        unlinearize_channel(color.g),
        unlinearize_channel(color.b),
        color.a
    );
}

float4 load_color(float4 in_color, bool display_p3, bool use_linear_output)
{
    float4 color = in_color;
    if (display_p3 && !use_linear_output)
    {
        color.rgb *= color.a;
        return color;
    }

    color = linearize_color(color);
    if (!display_p3)
    {
        color.rgb = srgb_to_display_p3(color.rgb);
    }

    if (!use_linear_output)
    {
        color = unlinearize_color(color);
    }

    color.rgb *= color.a;
    return color;
}

float4 PSMain(float4 position : SV_Position) : SV_Target
{
    uint2 grid_size = unpack2u16(grid_size_packed_2u16);
    if (grid_size.x == 0u || grid_size.y == 0u || cell_size.x <= 0.0 || cell_size.y <= 0.0)
    {
        return float4(0.0, 0.0, 0.0, 0.0);
    }

    float2 frag = position.xy;
    float2 origin = float2(grid_padding.w, grid_padding.x);
    int2 grid_pos = int2(floor((frag - origin) / cell_size));

    int max_x = int(grid_size.x) - 1;
    int max_y = int(grid_size.y) - 1;

    if (grid_pos.x < 0)
    {
        if ((padding_extend & EXTEND_LEFT) != 0u)
            grid_pos.x = 0;
        else
            return float4(0.0, 0.0, 0.0, 0.0);
    }
    else if (grid_pos.x > max_x)
    {
        if ((padding_extend & EXTEND_RIGHT) != 0u)
            grid_pos.x = max_x;
        else
            return float4(0.0, 0.0, 0.0, 0.0);
    }

    if (grid_pos.y < 0)
    {
        if ((padding_extend & EXTEND_UP) != 0u)
            grid_pos.y = 0;
        else
            return float4(0.0, 0.0, 0.0, 0.0);
    }
    else if (grid_pos.y > max_y)
    {
        if ((padding_extend & EXTEND_DOWN) != 0u)
            grid_pos.y = max_y;
        else
            return float4(0.0, 0.0, 0.0, 0.0);
    }

    uint index = uint(grid_pos.y) * grid_size.x + uint(grid_pos.x);
    float4 color = cell_bg_buf[index];
    bool use_display_p3 = (bools & USE_DISPLAY_P3) != 0u;
    bool use_linear_blending = (bools & USE_LINEAR_BLENDING) != 0u;
    return load_color(color, use_display_p3, use_linear_blending);
}
