struct GhosttyPostVSOut
{
    float4 position : SV_Position;
};

GhosttyPostVSOut GhosttyPostVS(uint vid : SV_VertexID)
{
    GhosttyPostVSOut outv;
    float2 pos = float2(
        (vid == 2u) ? 3.0 : -1.0,
        (vid == 1u) ? 3.0 : -1.0
    );
    outv.position = float4(pos, 0.0, 1.0);
    return outv;
}
