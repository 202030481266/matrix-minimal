// Matrix Minimal - phosphor screen for Windows Terminal
//
// Text gets a faint phosphor glow and fine scanlines; the rain toward the window
// corners is dimmed a little. The digital rain itself is the background image
// matrix-rain-bg.png (made by matrix-rain-bg.ps1, glow and scanlines baked in).
//
// This shader never reads Time, and that is what keeps it cheap: Windows Terminal
// only runs a shader that ignores Time when the screen content changes, instead
// of redrawing the whole window 60 times a second. Do not add anything that reads
// Time (flicker, breathing, ...): that alone turns the 60 fps redraw back on.
//
// Use (Windows Terminal settings.json, PowerShell profiles):
//   "experimental.pixelShaderPath": "%USERPROFILE%\\.config\\omp\\matrix-phosphor.hlsl"
// Edit the values under "Tweak me" and save: Terminal reloads it by itself.

Texture2D shaderTexture;
SamplerState samplerState;

cbuffer PixelShaderSettings
{
    float  Time;        // part of the layout Windows Terminal expects - never read it (see above)
    float  Scale;       // UI scale (1.0 = 100 %)
    float2 Resolution;  // size of shaderTexture in pixels
    float4 Background;  // terminal background colour
};

// ---------------------------------------------------------------- Tweak me
#define GLOW_STRENGTH   0.45    // phosphor halo around text (0 = off)
#define GLOW_RADIUS     1.5     // halo radius at 100 % scale, in pixels
#define GLOW_ON_TEXT    0.30    // share of the halo that also brightens the text itself
#define SCAN_TEXT       0.08    // how much a scanline darkens text (0 = off)
#define VIGNETTE        0.00    // dims the rain toward the corners; text is never dimmed (0 = off).
                                // Only use it with "padding": "0": the shader does not cover the
                                // padding strip, which would stay bright and show as a seam.
#define TEXT_LOW        0.40    // what counts as text: colour distance from the background
#define TEXT_HIGH       0.60    //   (dim rain glyphs stay below TEXT_LOW)
// -------------------------------------------------------------------------

static const float2 RING1[8] =
{
    float2( 1.000,  0.000), float2( 0.707,  0.707), float2( 0.000,  1.000), float2(-0.707,  0.707),
    float2(-1.000,  0.000), float2(-0.707, -0.707), float2( 0.000, -1.000), float2( 0.707, -0.707)
};
static const float2 RING2[8] =   // RING1 turned by 22.5 degrees
{
    float2( 0.924,  0.383), float2( 0.383,  0.924), float2(-0.383,  0.924), float2(-0.924,  0.383),
    float2(-0.924, -0.383), float2(-0.383, -0.924), float2( 0.383, -0.924), float2( 0.924, -0.383)
};

// 0 for background and rain, 1 for text. Works with an opaque background and with a
// transparent one (background image): the terminal texture is premultiplied.
float Textness(float4 c)
{
    float3 d = abs(c.rgb - Background.rgb * c.a);
    return smoothstep(TEXT_LOW, TEXT_HIGH, max(d.r, max(d.g, d.b)));
}

// Only text emits light.
float3 Light(float4 c)
{
    return max(c.rgb - Background.rgb * c.a, 0.0) * Textness(c);
}

float4 main(float4 pos : SV_POSITION, float2 tex : TEXCOORD) : SV_TARGET
{
    float4 color = shaderTexture.SampleLevel(samplerState, tex, 0);
    float  s     = max(Scale, 1.0);
    float2 texel = 1.0 / Resolution;

    // halo: two rings of 8 bilinear taps (each tap averages 4 pixels)
    float3 halo = 0;
    [unroll] for (int i = 0; i < 8; i++)
    {
        halo += Light(shaderTexture.SampleLevel(samplerState, tex + RING1[i] * (GLOW_RADIUS * s) * texel, 0)) * 0.6;
        halo += Light(shaderTexture.SampleLevel(samplerState, tex + RING2[i] * (GLOW_RADIUS * s * 2.2) * texel, 0)) * 0.4;
    }
    halo /= 8.0;

    float  t    = Textness(color);
    float3 glow = halo * GLOW_STRENGTH * lerp(1.0, GLOW_ON_TEXT, t);

    // one darker pixel row per glyph-pixel pitch of the rain (2 px at 100 %)
    float pitch  = max(2.0, round(2.0 * s));
    float onScan = (fmod(floor(pos.y), pitch) == pitch - 1.0) ? 1.0 : 0.0;

    float2 v   = tex * 2.0 - 1.0;                       // -1 .. 1 across the window
    float  vig = VIGNETTE * smoothstep(0.35, 1.0, dot(v, v) * 0.5);

    // Premultiplied output. Text is darkened by the scanline only; whatever shows
    // through transparent pixels (the rain image) is dimmed by the vignette via alpha.
    float darkText = onScan * SCAN_TEXT;
    float4 o;
    o.rgb = color.rgb * (1.0 - lerp(vig, darkText, t)) + glow;
    o.a   = 1.0 - (1.0 - vig) * (1.0 - color.a);
    return o;
}
