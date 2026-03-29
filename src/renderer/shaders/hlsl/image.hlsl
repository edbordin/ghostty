// For simplicity, common includes are handled manually in zig so we can keep using @embedFile
// #include "frame_constants.hlsi"

Texture2D<float4> image_tex : register(t0);
SamplerState image_sampler : register(s0);
static const uint USE_LINEAR_BLENDING = 4u;

struct VSIn
{
    float2 grid_pos : GRID_POS;
    float2 cell_offset : CELL_OFFSET;
    float4 source_rect : SOURCE_RECT;
    float2 dest_size : DEST_SIZE;
};

struct VSOut
{
    float4 position : SV_Position;
    float2 tex_coord : TEXCOORD0;
};

float unlinearize_channel(float v)
{
    return (v <= 0.0031308) ? (v * 12.92) : (pow(v, 1.0 / 2.4) * 1.055 - 0.055);
}

float3 unlinearize_rgb(float3 rgb)
{
    return float3(
        unlinearize_channel(rgb.r),
        unlinearize_channel(rgb.g),
        unlinearize_channel(rgb.b)
    );
}

VSOut VSMain(VSIn input, uint vid : SV_VertexID)
{
    float2 corner = float2((vid == 1u || vid == 3u) ? 1.0 : 0.0, (vid >= 2u) ? 1.0 : 0.0);

    uint tex_w;
    uint tex_h;
    image_tex.GetDimensions(tex_w, tex_h);
    float2 tex_size = float2(tex_w, tex_h);

    VSOut output;
    output.tex_coord = input.source_rect.xy + input.source_rect.zw * corner;
    output.tex_coord /= tex_size;

    float2 image_pos = cell_size * input.grid_pos;
    image_pos += input.cell_offset;
    image_pos += input.dest_size * corner;
    output.position = mul(projection_matrix, float4(image_pos, 1.0, 1.0));
    return output;
}

float4 PSMain(VSOut input) : SV_Target
{
    float4 rgba = image_tex.Sample(image_sampler, input.tex_coord);

    if ((bools & USE_LINEAR_BLENDING) == 0u)
    {
        rgba.rgb = unlinearize_rgb(rgba.rgb);
    }

    rgba.rgb *= rgba.a;
    return rgba;
}
