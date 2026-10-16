#requires -Version 5.1
<#
.SYNOPSIS
  Matrix Minimal: renders the static digital-rain background for Windows Terminal.

.DESCRIPTION
  One frozen frame of the rain, in the same 5x7 katakana pixel style as matrix-rain.hlsl:
  dense on the right, fading out toward the left and the bottom, where commands, output
  and the prompt live. Phosphor glow and scanlines are baked in, so the terminal does no
  per-frame work for the rain at all.

  Rendered at the screen's work-area size in physical pixels. Windows Terminal draws it
  1:1 (crisp) with "backgroundImageStretchMode": "none" and "backgroundImageAlignment":
  "bottomLeft"; a smaller window or pane just shows the bottom-left part of it, which is
  why "sparse" and "dense" are measured in pixels from the left edge.
  At display scaling other than 100 % Windows Terminal would enlarge such an image, so
  setup.ps1 uses "uniformToFill" there instead: crisp when the window is maximized.
  Run this script again after changing resolution or scaling, or to try another -Seed,
  then open a new tab.

.EXAMPLE
  pwsh -File matrix-rain-bg.ps1                  # writes matrix-rain-bg.png next to this script
  pwsh -File matrix-rain-bg.ps1 -Seed 7 -Preview # another rain pattern, plus a preview image
#>
[CmdletBinding()]
param(
    [string]$OutFile = (Join-Path $PSScriptRoot 'matrix-rain-bg.png'),
    [int]$Seed = 20261016,
    [int]$Width = 0,        # 0 = work area of the primary screen, in physical pixels
    [int]$Height = 0,
    [double]$Scale = 0,     # 0 = the screen's display scaling (one glyph pixel = 2 px at 100 %)
    [switch]$Preview        # also write <name>.preview.png: the image over the theme background
)

# ---------------------------------------------------------------- Tweak me
$Look = @{
    SparseUntil     = 450    # px from the left edge: almost no rain before this
    DenseFrom       = 1300   # px from the left edge: full rain from here on
    DensityLeft     = 0.06   # share of columns carrying a drop, left / right
    DensityRight    = 0.90
    BrightLeft      = 0.30   # brightness on the left, relative to the right
    TrailAlpha      = 0.38   # opacity of the brightest trail glyph (text stays far brighter)
    HeadAlpha       = 0.52   # opacity of the leading glyph of a drop
    TrailCells      = 22     # average trail length, in glyph rows
    GlowStrength    = 0.90   # phosphor halo around the rain glyphs (0 = off)
    GlowRadius      = 1.5    # halo radius, in glyph pixels
    BottomFadePx    = 220    # the rain fades out over this many px above the bottom edge
    BottomFadeLeft  = 0.85   # how much of it is gone at the very bottom, left / right
    BottomFadeRight = 0.40
    ScanlineDark    = 0.28   # one darker pixel row per glyph-pixel row (CRT scanlines)
}
$Background = 0x0D, 0x02, 0x08   # theme background #0D0208, only used for -Preview
# -------------------------------------------------------------------------

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
if (-not ('MatrixRain' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public class MatrixRainLook
{
    public int Width, Height, GlyphPx;
    public uint Seed;
    public double SparseUntil, DenseFrom, DensityLeft, DensityRight, BrightLeft;
    public double TrailAlpha, HeadAlpha, TrailCells, GlowStrength, GlowRadius;
    public double BottomFadePx, BottomFadeLeft, BottomFadeRight, ScanlineDark;
}

public static class MatrixRain
{
    // 5x7 glyphs, '#' = lit pixel. The first 16 are exactly the glyphs of matrix-rain.hlsl.
    static readonly string[] Glyphs =
    {
        "#####|....#|..##.|..#..|..#..|.#...|#....", // a
        "....#|...#.|..##.|.#.#.|#..#.|...#.|...#.", // i
        "..#..|#####|#...#|....#|...#.|..#..|.#...", // u
        ".....|#####|..#..|..#..|..#..|..#..|#####", // e
        "...#.|#####|...#.|..##.|.#.#.|#..#.|...#.", // o
        ".#...|#####|.#..#|.#..#|.#..#|#...#|#..#.", // ka
        "..#..|#####|..#..|#####|..#..|..#..|..#..", // ki
        ".####|.#..#|#...#|....#|...#.|..#..|##...", // ku
        "#....|#####|.#.#.|#..#.|...#.|..#..|.#...", // ke
        "#####|....#|....#|....#|....#|....#|#####", // ko
        ".#.#.|#####|.#.#.|.#.#.|...#.|..#..|.#...", // sa
        "#...#|.#..#|....#|...#.|..#..|.#...|#....", // so
        ".###.|#...#|#..##|#.#.#|##..#|#...#|.###.", // 0
        "..#..|.##..|..#..|..#..|..#..|..#..|.###.", // 1
        ".###.|#...#|....#|..##.|....#|#...#|.###.", // 3
        "#####|....#|...#.|..#..|.#...|.#...|.#...", // 7
        "##...|....#|##..#|....#|...#.|..#..|##...", // shi
        ".....|#####|....#|...#.|..#..|.#.#.|#...#", // su
        ".#...|#####|.#..#|.#.#.|.#...|.#...|..###", // se
        ".####|.#..#|#.#.#|...##|...#.|..#..|##...", // ta
        "...#.|###..|..#..|#####|..#..|..#..|.#...", // chi
        "#.#.#|#.#.#|....#|....#|...#.|..#..|##...", // tsu
        ".###.|.....|#####|..#..|..#..|..#..|.#...", // te
        ".#...|.#...|.##..|.#.#.|.#...|.#...|.#...", // to
        "..#..|..#..|#####|..#..|..#..|.#...|#....", // na
        ".....|.###.|.....|.....|.....|#####|.....", // ni
        ".....|#####|....#|.#.#.|..#..|.#.#.|#....", // nu
        "..#..|#####|...#.|..#..|.###.|#.#.#|..#..", // ne
        "....#|....#|...#.|...#.|..#..|.#...|#....", // no
        ".....|.#.#.|.#.#.|#...#|#...#|#...#|.....", // ha
        "#....|#....|#####|#....|#....|#....|.####", // hi
        "#####|....#|....#|....#|...#.|..#..|##...", // fu
        ".....|.#...|#.#..|...#.|....#|.....|.....", // he
        "..#..|#####|..#..|..#..|#.#.#|#.#.#|..#..", // ho
        "#####|....#|....#|.#.#.|..#..|...#.|.....", // ma
        ".###.|.....|.###.|.....|.###.|....#|.....", // mi
        ".....|..#..|.#...|#....|#...#|#####|....#", // mu
        "....#|....#|.#.#.|..#..|.#.#.|#....|.....", // me
        "#####|..#..|#####|..#..|..#..|..#..|...##", // mo
        ".#...|.#...|#####|.#..#|.#.#.|.#...|.#...", // ya
        ".....|.###.|...#.|...#.|...#.|#####|.....", // yu
        "#####|....#|#####|....#|....#|#####|.....", // yo
        ".###.|.....|#####|....#|....#|...#.|..#..", // ra
        "#..#.|#..#.|#..#.|#..#.|...#.|..#..|.#...", // ri
        "..#..|#.#..|#.#..|#.#..|#.#.#|#.##.|.....", // ru
        "#....|#....|#....|#...#|#..#.|#.#..|##...", // re
        "#####|#...#|#...#|#...#|#...#|#####|.....", // ro
        "#####|#...#|#...#|....#|...#.|..#..|##...", // wa
        "##...|.....|....#|....#|...#.|..#..|###..", // n
        ".###.|#...#|....#|...#.|..#..|.#...|#####", // 2
        "...#.|..##.|.#.#.|#..#.|#####|...#.|...#.", // 4
        "#####|#....|####.|....#|....#|#...#|.###.", // 5
        "..##.|.#...|#....|####.|#...#|#...#|.###.", // 6
        ".###.|#...#|#...#|.###.|#...#|#...#|.###.", // 8
        ".###.|#...#|#...#|.####|....#|...#.|.##..", // 9
    };

    static uint Hash(uint x)
    {
        unchecked
        {
            x ^= x >> 16; x *= 0x7feb352dU;
            x ^= x >> 15; x *= 0x846ca68bU;
            x ^= x >> 16;
            return x;
        }
    }

    static double Rnd(uint x) { return (Hash(x) & 0x00ffffffU) / 16777216.0; }

    static double Smooth(double a, double b, double x)
    {
        double t = (x - a) / (b - a);
        t = t < 0 ? 0 : (t > 1 ? 1 : t);
        return t * t * (3 - 2 * t);
    }

    static double Lerp(double a, double b, double t) { return a + (b - a) * t; }

    static bool[][] Masks()
    {
        var masks = new bool[Glyphs.Length][];
        for (int g = 0; g < Glyphs.Length; g++)
        {
            string[] rows = Glyphs[g].Split('|');
            if (rows.Length != 7) throw new ArgumentException("glyph " + g + ": needs 7 rows");
            masks[g] = new bool[35];
            for (int y = 0; y < 7; y++)
            {
                if (rows[y].Length != 5) throw new ArgumentException("glyph " + g + " row " + y + ": needs 5 columns");
                for (int x = 0; x < 5; x++) masks[g][y * 5 + x] = rows[y][x] == '#';
            }
        }
        return masks;
    }

    static void Stamp(float[] alpha, float[] head, int W, int H, bool[] mask, int x0, int y0, int gp, float a, bool isHead)
    {
        for (int gy = 0; gy < 7; gy++)
            for (int gx = 0; gx < 5; gx++)
            {
                if (!mask[gy * 5 + gx]) continue;
                for (int py = y0 + gy * gp; py < y0 + (gy + 1) * gp; py++)
                {
                    if (py < 0 || py >= H) continue;
                    for (int px = x0 + gx * gp; px < x0 + (gx + 1) * gp; px++)
                    {
                        if (px < 0 || px >= W) continue;
                        int i = py * W + px;
                        if (a >= alpha[i]) { alpha[i] = a; head[i] = isHead ? 1f : 0f; }
                    }
                }
            }
    }

    static float[] Blur(float[] src, int W, int H, double sigma)
    {
        int r = (int)Math.Ceiling(sigma * 3);
        var k = new float[2 * r + 1];
        double sum = 0;
        for (int i = -r; i <= r; i++) { k[i + r] = (float)Math.Exp(-(i * i) / (2 * sigma * sigma)); sum += k[i + r]; }
        for (int i = 0; i < k.Length; i++) k[i] = (float)(k[i] / sum);
        var tmp = new float[W * H];
        var dst = new float[W * H];
        for (int y = 0; y < H; y++)
            for (int x = 0; x < W; x++)
            {
                float acc = 0;
                for (int j = -r; j <= r; j++) { int xx = x + j; if (xx >= 0 && xx < W) acc += src[y * W + xx] * k[j + r]; }
                tmp[y * W + x] = acc;
            }
        for (int y = 0; y < H; y++)
            for (int x = 0; x < W; x++)
            {
                float acc = 0;
                for (int j = -r; j <= r; j++) { int yy = y + j; if (yy >= 0 && yy < H) acc += tmp[yy * W + x] * k[j + r]; }
                dst[y * W + x] = acc;
            }
        return dst;
    }

    // BGRA bytes with straight (non-premultiplied) alpha, ready for a 32bppArgb bitmap.
    public static byte[] Render(MatrixRainLook o)
    {
        int W = o.Width, H = o.Height, gp = o.GlyphPx;
        int cw = 6 * gp, ch = 9 * gp;                 // cell: 5x7 glyph plus spacing, as in the shader
        int cols = (W + cw - 1) / cw, rows = (H + ch - 1) / ch;
        bool[][] masks = Masks();
        var alpha = new float[W * H];
        var head = new float[W * H];

        unchecked
        {
            for (int c = 0; c < cols; c++)
            {
                double x = c * cw + cw * 0.5;
                double t = Smooth(o.SparseUntil, o.DenseFrom, x);
                double density = Lerp(o.DensityLeft, o.DensityRight, t);
                double bright = Lerp(o.BrightLeft, 1.0, t);
                double fadeDepth = Lerp(o.BottomFadeLeft, o.BottomFadeRight, t);
                for (int layer = 0; layer < 3; layer++)       // up to three drops per column
                {
                    uint h = Hash(o.Seed + Hash((uint)c * 2654435761U + (uint)layer * 0x9E3779B9U));
                    double chance = density * (layer == 0 ? 1.0 : (layer == 1 ? 0.5 : 0.25));
                    if (Rnd(h) >= chance) continue;
                    double gain = layer == 0 ? 1.0 : (layer == 1 ? 0.65 : 0.45);
                    double trail = o.TrailCells * Lerp(0.55, 1.45, Rnd(h + 1));
                    int headRow = (int)Math.Floor(Rnd(h + 2) * (rows + trail * 0.5));
                    for (int d = 0; d <= (int)trail; d++)
                    {
                        int r = headRow - d;
                        if (r < 0) break;
                        if (r >= rows) continue;
                        double f = 1.0 - d / trail;
                        f *= f;
                        bool isHead = d == 0;
                        double a = (isHead ? o.HeadAlpha : o.TrailAlpha * f) * bright * gain;
                        a *= 1.0 - fadeDepth * Smooth(H - o.BottomFadePx, H, r * ch + ch * 0.5);
                        if (a < 0.006) continue;
                        int g = (int)(Hash(o.Seed ^ ((uint)c * 73856093U) ^ ((uint)r * 19349663U)) % (uint)masks.Length);
                        Stamp(alpha, head, W, H, masks[g], c * cw, r * ch + gp, gp, (float)a, isHead);
                    }
                }
            }
        }

        float[] glow = Blur(alpha, W, H, o.GlowRadius * gp);
        var px = new byte[W * H * 4];
        for (int y = 0; y < H; y++)
        {
            bool scan = (y % gp) == gp - 1;
            for (int x = 0; x < W; x++)
            {
                int i = y * W + x;
                double A = alpha[i];
                double G = Math.Min(1.0, glow[i] * o.GlowStrength) * (1 - A);
                double outA = A + G;
                if (outA < 0.5 / 255) continue;
                double hd = head[i];
                // glyphs: trail #00FF41 .. head #C7FFD1; halo: #00FF41
                double r = (A * Lerp(0x00, 0xC7, hd)) / outA;
                double gr = (A * 0xFF + G * 0xFF) / outA;
                double b = (A * Lerp(0x41, 0xD1, hd) + G * 0x41) / outA;
                if (scan) outA *= 1 - o.ScanlineDark;
                int j = i * 4;
                px[j] = (byte)Math.Round(b);
                px[j + 1] = (byte)Math.Round(gr);
                px[j + 2] = (byte)Math.Round(r);
                px[j + 3] = (byte)Math.Round(outA * 255);
            }
        }
        return px;
    }

    // The image composited over a solid background, for previews.
    public static byte[] Flatten(byte[] bgra, int r, int g, int b)
    {
        var o = new byte[bgra.Length];
        for (int j = 0; j < bgra.Length; j += 4)
        {
            double a = bgra[j + 3] / 255.0;
            o[j] = (byte)Math.Round(bgra[j] * a + b * (1 - a));
            o[j + 1] = (byte)Math.Round(bgra[j + 1] * a + g * (1 - a));
            o[j + 2] = (byte)Math.Round(bgra[j + 2] * a + r * (1 - a));
            o[j + 3] = 255;
        }
        return o;
    }

    [StructLayout(LayoutKind.Sequential)] struct RECT { public int L, T, R, B; }
    [StructLayout(LayoutKind.Sequential)] struct POINT { public int X, Y; }
    [StructLayout(LayoutKind.Sequential)] struct MONITORINFO { public int cbSize; public RECT rcMonitor, rcWork; public uint dwFlags; }
    [DllImport("user32.dll")] static extern bool SetProcessDpiAwarenessContext(IntPtr value);
    [DllImport("user32.dll")] static extern IntPtr MonitorFromPoint(POINT pt, uint flags);
    [DllImport("user32.dll")] static extern bool GetMonitorInfo(IntPtr monitor, ref MONITORINFO info);
    [DllImport("shcore.dll")] static extern int GetDpiForMonitor(IntPtr monitor, int type, out uint dpiX, out uint dpiY);

    // { width, height, dpi } of the primary screen's work area, in physical pixels
    public static int[] PrimaryWorkArea()
    {
        try { SetProcessDpiAwarenessContext(new IntPtr(-4)); } catch (Exception) { }
        IntPtr mon = MonitorFromPoint(new POINT(), 1);
        var mi = new MONITORINFO();
        mi.cbSize = Marshal.SizeOf(typeof(MONITORINFO));
        GetMonitorInfo(mon, ref mi);
        uint dx = 96, dy = 96;
        try { if (GetDpiForMonitor(mon, 0, out dx, out dy) != 0) dx = 96; } catch (Exception) { dx = 96; }
        return new int[] { mi.rcWork.R - mi.rcWork.L, mi.rcWork.B - mi.rcWork.T, (int)dx };
    }
}
'@
}

function Save-Bgra([byte[]]$Pixels, [int]$W, [int]$H, [string]$Path) {
    $bmp = New-Object System.Drawing.Bitmap $W, $H, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $data = $bmp.LockBits((New-Object System.Drawing.Rectangle 0, 0, $W, $H),
        [System.Drawing.Imaging.ImageLockMode]::WriteOnly, $bmp.PixelFormat)
    try { [Runtime.InteropServices.Marshal]::Copy($Pixels, 0, $data.Scan0, $Pixels.Length) }
    finally { $bmp.UnlockBits($data) }
    $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
}

$screen = [MatrixRain]::PrimaryWorkArea()
if ($Width -le 0) { $Width = $screen[0] }
if ($Height -le 0) { $Height = $screen[1] }
if ($Scale -le 0) { $Scale = $screen[2] / 96.0 }

$o = New-Object MatrixRainLook
$o.Width = $Width; $o.Height = $Height; $o.Seed = [uint32]$Seed
$o.GlyphPx = [math]::Max(2, [int][math]::Round(2 * $Scale))
foreach ($k in $Look.Keys) { $o.$k = $Look[$k] }

$sw = [Diagnostics.Stopwatch]::StartNew()
$pixels = [MatrixRain]::Render($o)
$OutFile = [IO.Path]::GetFullPath($OutFile)
Save-Bgra $pixels $Width $Height $OutFile
"matrix-rain-bg: {0}x{1}, glyph pixel {2} px, seed {3} -> {4} ({5:N0} KB, {6} ms)" -f $Width, $Height, $o.GlyphPx, $Seed, $OutFile, ((Get-Item $OutFile).Length / 1KB), $sw.ElapsedMilliseconds
if ($Preview) {
    $previewFile = [IO.Path]::ChangeExtension($OutFile, '.preview.png')
    Save-Bgra ([MatrixRain]::Flatten($pixels, $Background[0], $Background[1], $Background[2])) $Width $Height $previewFile
    "preview -> $previewFile"
}
