// Lightweight CRT-like postprocess fallback for D3D11 raw HLSL loading.
Texture2D iChannel0 : register(t0);
SamplerState iSampler0 : register(s0);

float4 main(float4 fragPos : SV_Position) : SV_Target
{
    uint w = 1;
    uint h = 1;
    iChannel0.GetDimensions(w, h);

    float2 res = float2((float)w, (float)h);
    float2 uv = fragPos.xy / res;

    // Mild screen curvature.
    float2 centered = uv * 2.0 - 1.0;
    centered *= 1.08;
    centered.x *= 1.0 + 0.08 * centered.y * centered.y;
    centered.y *= 1.0 + 0.08 * centered.x * centered.x;
    uv = centered * 0.5 + 0.5;

    float3 col = iChannel0.Sample(iSampler0, uv).rgb;

    // RGB channel offset for chromatic aberration.
    float2 aberr = float2(1.2 / res.x, 0.0);
    col.r = iChannel0.Sample(iSampler0, uv + aberr).r;
    col.b = iChannel0.Sample(iSampler0, uv - aberr).b;

    // Horizontal scanlines and subtle grille.
    float scan = 0.9 + 0.1 * sin(uv.y * res.y * 1.4);
    float grille = 0.94 + 0.06 * sin(uv.x * res.x * 3.14159);
    col *= scan * grille;

    // Vignette and slight gamma shaping.
    float2 v = uv * (1.0 - uv);
    float vignette = saturate(pow(16.0 * v.x * v.y, 0.22));
    col *= vignette;
    col = pow(saturate(col), 0.92);

    // Black out outside curved area.
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
        col = float3(0.0, 0.0, 0.0);
    }

    return float4(col, 1.0);
}
