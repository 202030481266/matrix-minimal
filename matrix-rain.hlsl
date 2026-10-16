// Matrix Minimal — digital rain pixel shader for Windows Terminal
//
// Draws falling green glyph columns BEHIND your text: only pixels that still
// show the terminal background colour get rain, so prompt and output stay crisp.
//
// Use: in Windows Terminal settings.json (install.ps1 does this for you):
//   "experimental.pixelShaderPath": "%USERPROFILE%\\.config\\omp\\matrix-rain.hlsl"
// Edit the values under "Tweak me" and save: Terminal reloads it by itself.

Texture2D shaderTexture;
SamplerState samplerState;

cbuffer PixelShaderSettings
{
    float  Time;        // seconds since the shader was enabled
    float  Scale;       // UI scale (1.0 = 100 %)
    float2 Resolution;  // size of shaderTexture in pixels
    float4 Background;  // terminal background colour
};

// ---------------------------------------------------------------- Tweak me
#define GLYPH_PX        2.0     // size of one glyph pixel at 100 % scale
#define RAIN_STRENGTH   0.30    // 0 = off, 1 = full brightness behind text
#define HEAD_BOOST      1.9     // how much brighter the leading glyph is
#define TRAIL_CELLS     16.0    // average trail length, in glyph rows
#define SPEED_MIN       3.0     // glyph rows per second
#define SPEED_MAX       9.0
#define DENSITY         0.55    // share of columns that carry a drop (0..1)
#define TEXT_LOW        0.020   // background/text separation (colour distance)
#define TEXT_HIGH       0.080

static const float3 TRAIL_COLOR = float3(0.000, 1.000, 0.255); // #00FF41
static const float3 HEAD_COLOR  = float3(0.780, 1.000, 0.820); // near-white green
// -------------------------------------------------------------------------

// 16 glyphs, 5x7 pixels, one row per entry (bit 4 = leftmost pixel).
// Mirrored half-width katakana and a few digits.
static const uint GLYPHS[112] =
{
    0x1F, 0x01, 0x06, 0x04, 0x04, 0x08, 0x10,
    0x01, 0x02, 0x06, 0x0A, 0x12, 0x02, 0x02,
    0x04, 0x1F, 0x11, 0x01, 0x02, 0x04, 0x08,
    0x00, 0x1F, 0x04, 0x04, 0x04, 0x04, 0x1F,
    0x02, 0x1F, 0x02, 0x06, 0x0A, 0x12, 0x02,
    0x08, 0x1F, 0x09, 0x09, 0x09, 0x11, 0x12,
    0x04, 0x1F, 0x04, 0x1F, 0x04, 0x04, 0x04,
    0x0F, 0x09, 0x11, 0x01, 0x02, 0x04, 0x18,
    0x10, 0x1F, 0x0A, 0x12, 0x02, 0x04, 0x08,
    0x1F, 0x01, 0x01, 0x01, 0x01, 0x01, 0x1F,
    0x0A, 0x1F, 0x0A, 0x0A, 0x02, 0x04, 0x08,
    0x11, 0x09, 0x01, 0x02, 0x04, 0x08, 0x10,
    0x0E, 0x11, 0x13, 0x15, 0x19, 0x11, 0x0E,
    0x04, 0x0C, 0x04, 0x04, 0x04, 0x04, 0x0E,
    0x0E, 0x11, 0x01, 0x06, 0x01, 0x11, 0x0E,
    0x1F, 0x01, 0x02, 0x04, 0x08, 0x08, 0x08
};

uint hashu(uint x)
{
    x ^= x >> 16;
    x *= 0x7feb352du;
    x ^= x >> 15;
    x *= 0x846ca68bu;
    x ^= x >> 16;
    return x;
}

float rnd(uint x)
{
    return (float)(hashu(x) & 0x00ffffffu) / 16777216.0;
}

// Brightness of one rain layer at a cell. head = 1 on the leading glyph.
// Windows Terminal wraps Time back to 0 every 1000 s, so every column falls a
// whole number of times per 1000 s: the wrap is invisible.
float rainLayer(uint col, float row, float rows, uint seed, out float head)
{
    head = 0.0;
    uint c = hashu(col * 2654435761u + seed);
    if (rnd(c) > DENSITY)
        return 0.0;

    float period = rows + TRAIL_CELLS * 2.0 + rnd(c + 2u) * rows;   // rows per fall
    float speed  = lerp(SPEED_MIN, SPEED_MAX, rnd(c + 1u));          // rows per second
    float cycles = max(1.0, round(speed * 1000.0 / period));        // falls per 1000 s
    float u      = Time * cycles / 1000.0 + rnd(c + 3u);
    float drop   = floor(u);
    float pos    = floor(frac(u) * period);                          // head row of this drop

    float trail  = TRAIL_CELLS * lerp(0.55, 1.45, rnd(c + (uint)fmod(drop, cycles) * 7u + 4u));
    float d      = pos - row;                          // rows above the head
    if (d < 0.0 || d > trail)
        return 0.0;

    head = (d < 0.5) ? 1.0 : 0.0;
    float f = 1.0 - d / trail;
    return f * f;
}

float glyphMask(uint2 cell, float2 local, float gp)
{
    float2 g = floor(local / gp) - float2(0.0, 1.0);   // 1 px gap above
    if (g.x < 0.0 || g.x > 4.0 || g.y < 0.0 || g.y > 6.0)
        return 0.0;

    uint id   = hashu(cell.x * 73856093u ^ cell.y * 19349663u);
    float rate = 0.6 + rnd(id) * 4.0;                  // glyph changes per second
    uint tick = (uint)(Time * rate + rnd(id + 9u) * 8.0);
    uint glyph = hashu(id + tick * 83492791u) & 15u;

    uint bits = GLYPHS[glyph * 7u + (uint)g.y];
    return (float)((bits >> (4u - (uint)g.x)) & 1u);
}

float4 main(float4 pos : SV_POSITION, float2 tex : TEXCOORD) : SV_TARGET
{
    float4 color = shaderTexture.Sample(samplerState, tex);

    float  gp   = GLYPH_PX * max(Scale, 1.0);
    float2 cs   = float2(6.0, 9.0) * gp;               // 5x7 glyph + spacing
    float2 px   = tex * Resolution;
    float2 cf   = floor(px / cs);
    uint2  cell = (uint2)cf;
    float  rows = ceil(Resolution.y / cs.y);

    float h1, h2;
    float r1 = rainLayer(cell.x, cf.y, rows, 0x9E37u, h1);
    float r2 = rainLayer(cell.x, cf.y, rows, 0x51EDu, h2) * 0.6;
    float rain = max(r1, r2);
    float head = max(h1, h2 * 0.6);
    if (rain <= 0.0)
        return color;

    float glyph = glyphMask(cell, px - cf * cs, gp);
    float3 rgb  = lerp(TRAIL_COLOR, HEAD_COLOR, head);
    float  k    = rain * glyph * RAIN_STRENGTH * lerp(1.0, HEAD_BOOST, head);

    // Only paint where the pixel still is background (keeps text readable). The texture is
    // premultiplied: with a background image the background is transparent, not Background.
    float3 diff = abs(color.rgb - Background.rgb * color.a);
    float  dist = max(diff.r, max(diff.g, diff.b));
    float  isBg = 1.0 - smoothstep(TEXT_LOW, TEXT_HIGH, dist);

    color.rgb = saturate(color.rgb + rgb * k * isBg);
    return color;
}
