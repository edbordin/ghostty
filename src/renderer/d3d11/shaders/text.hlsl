cbuffer TextConstants : register(b0)
{
    float4x4 projection;
    float2 cell_size;
    float2 _pad0;
};

Texture2D<float> texture_grayscale : register(t0);
Texture2D<float4> texture_color : register(t1);

struct VSIn
{
    uint2 glyph_pos : GLYPH_POS;
    uint2 glyph_size : GLYPH_SIZE;
    int2 bearings : BEARINGS;
    uint2 grid_pos : GRID_POS;
    float4 color : COLOR;
    uint atlas : ATLAS;
};

struct VSOut
{
    float4 position : SV_Position;
    nointerpolation float4 color : COLOR0;
    nointerpolation uint atlas : ATLAS;
    float2 tex_coord : TEXCOORD0;
};

VSOut VSMain(VSIn input, uint vid : SV_VertexID)
{
    float2 corner = float2((vid == 1 || vid == 3) ? 1.0 : 0.0, (vid >= 2) ? 1.0 : 0.0);
    float2 cell_pos = cell_size * float2(input.grid_pos);
    float2 size = float2(input.glyph_size);
    float2 offset = float2(input.bearings);
    offset.y = cell_size.y - offset.y;
    float2 pos = cell_pos + size * corner + offset;

    VSOut outv;
    outv.position = mul(projection, float4(pos, 0.0, 1.0));
    outv.color = input.color;
    outv.atlas = input.atlas;
    outv.tex_coord = float2(input.glyph_pos) + float2(input.glyph_size) * corner;
    return outv;
}

float4 PSMain(VSOut input) : SV_Target
{
    int2 coord = int2(input.tex_coord);
    if (input.atlas == 0)
    {
        float a = texture_grayscale.Load(int3(coord, 0)).r;
        float4 color = input.color;
        color.rgb *= color.a;
        return color * a;
    }
    return texture_color.Load(int3(coord, 0));
}
