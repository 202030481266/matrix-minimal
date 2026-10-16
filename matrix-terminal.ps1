# ---------------------------------------------------------------------------
#  Matrix Minimal: companions for the "Matrix Minimal" Windows Terminal scheme
#  The scheme turns every ANSI colour green. That suits the prompt (which uses its
#  own RGB colours anyway) but smears programs that pick ANSI colours themselves.
#  The scheme applies whatever prompt theme is active, so $PROFILE loads this
#  file for every theme:   . (Join-Path $HOME '.config/omp/matrix-terminal.ps1')
# ---------------------------------------------------------------------------

if (-not $env:WT_SESSION) { return }   # the scheme only exists in Windows Terminal

# 1. PowerShell's own colours ------------------------------------------------
#    Get-ChildItem paints directory names on a blue *background* by default, which the
#    scheme turns into bright green blocks. Use a themed text colour instead.
if ($PSStyle) {
    $PSStyle.FileInfo.Directory = "$([char]27)[1;38;2;125;255;184m"   # bold #7DFFB8
}

# 2. Native colours inside AI command-line apps ------------------------------
#    While one of these runs, the tab switches to Windows Terminal's default palette
#    (Campbell) so the app shows its own theme. When it exits, the tab goes back to
#    the profile's scheme. Add more names in $PROFILE before this file is loaded, e.g.
#      $MatrixNativeApps = 'claude', 'codex', 'nvim'
if ($null -eq $global:MatrixNativeApps) {
    $global:MatrixNativeApps = @('claude', 'codex', 'gemini', 'opencode', 'aider', 'copilot')
}
if ($null -eq $global:MatrixNativePalette) {
    # 16 ANSI colours (black red green yellow blue purple cyan white, then the bright ones),
    # then foreground, background, cursor. Values of Windows Terminal's "Campbell".
    $global:MatrixNativePalette = @(
        '#0C0C0C', '#C50F1F', '#13A10E', '#C19C00', '#0037DA', '#881798', '#3A96DD', '#CCCCCC',
        '#767676', '#E74856', '#16C60C', '#F9F1A5', '#3B78FF', '#B4009E', '#61D6D6', '#F2F2F2',
        '#CCCCCC', '#0C0C0C', '#FFFFFF')
}

function global:Set-MatrixNativeColors([bool]$On) {
    $e = [char]27
    $st = "$e\"
    if ($On) {
        $p = $global:MatrixNativePalette
        $rgb = { param($hex) 'rgb:{0}/{1}/{2}' -f $hex.Substring(1, 2), $hex.Substring(3, 2), $hex.Substring(5, 2) }
        $seq = -join (0..15 | ForEach-Object { "$e]4;$_;$(& $rgb $p[$_])$st" })
        $seq += "$e]10;$(& $rgb $p[16])$st$e]11;$(& $rgb $p[17])$st$e]12;$(& $rgb $p[18])$st"
    } else {
        $seq = "$e]104$st$e]110$st$e]111$st$e]112$st"   # reset palette, foreground, background, cursor
    }
    [Console]::Out.Write($seq)
    [Console]::Out.Flush()
}

# One wrapper function per installed app; the real program is looked up on every call.
# Installed = found on PATH. (Get-Command would also search every module for missing names: slow.)
& {
    $dirs = foreach ($d in $env:Path.Split(';')) { $d = $d.Trim().Trim('"'); if ($d) { $d } }
    foreach ($app in $global:MatrixNativeApps) {
        $installed = $false
        foreach ($dir in $dirs) {
            foreach ($ext in '.exe', '.cmd', '.bat', '.ps1') {
                if ([IO.File]::Exists($dir + '\' + $app + $ext)) { $installed = $true; break }
            }
            if ($installed) { break }
        }
        if (-not $installed) { continue }
        . ([scriptblock]::Create(@"
function global:$app {
    `$target = Get-Command '$app' -CommandType Application, ExternalScript -ErrorAction Stop | Select-Object -First 1
    Set-MatrixNativeColors `$true
    try { & `$target @args } finally { Set-MatrixNativeColors `$false }
}
"@))
    }
}
