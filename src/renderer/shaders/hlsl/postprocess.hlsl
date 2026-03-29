Texture2D<float4> source_texture : register(t0);
SamplerState source_sampler : register(s0);

struct VSOut
{
    float4 position : SV_Position;
    float2 uv : TEXCOORD0;
};

VSOut VSMain(uint vid : SV_VertexID)
{
    VSOut outv;
    float2 pos = float2((vid == 2) ? 3.0 : -1.0, (vid == 1) ? -3.0 : 1.0);
    outv.position = float4(pos, 0.0, 1.0);
    outv.uv = float2((pos.x + 1.0) * 0.5, (1.0 - pos.y) * 0.5);
    return outv;
}

float4 PSMain(VSOut input) : SV_Target
{
    return source_texture.Sample(source_sampler, input.uv);
}
