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

# 3. Moving rain on demand -------------------------------------------------------
#    rain on    the moving digital rain (matrix-rain.hlsl) in place of the still one;
#               Windows Terminal then redraws all the time, which keeps the GPU busy
#    rain off   back to the still rain image and the phosphor screen
#    rain       switch between the two
#    Only the theme's own file names are swapped inside settings.json, so comments and your
#    other settings stay exactly as they are; the terminal picks the change up by itself.
function global:rain {
    param([string]$State)
    if ($State -and $State -notin 'on', 'off') { Write-Host '用法：rain on | rain off | rain（切换）'; return }
    $settings = @(
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'),
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\settings.json')
    ) | Where-Object { Test-Path $_ }
    $found = @(foreach ($path in $settings) {
        $text = [IO.File]::ReadAllText($path)
        if ($text -match 'matrix-(phosphor|rain)\.hlsl') { @{ Path = $path; Text = $text } }
    })
    if (-not $found) { Write-Warning 'Windows Terminal 里没有使用 Matrix Minimal 的配置（先运行安装）'; return }
    if (-not $State) { $State = if ($found | Where-Object { $_.Text -match 'matrix-rain\.hlsl' }) { 'off' } else { 'on' } }

    $omp = Join-Path $HOME '.config\omp'
    if ($State -eq 'on') {
        if (-not (Test-Path (Join-Path $omp 'matrix-rain.hlsl'))) { Write-Warning "找不到 $omp\matrix-rain.hlsl（重新运行一次安装）"; return }
        $clear = Join-Path $omp 'matrix-rain-clear.png'      # stands in for the still rain image
        if (-not (Test-Path $clear)) {
            Add-Type -AssemblyName System.Drawing
            $bmp = New-Object System.Drawing.Bitmap 1, 1, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
            $bmp.SetPixel(0, 0, [System.Drawing.Color]::Transparent)
            $bmp.Save($clear, [System.Drawing.Imaging.ImageFormat]::Png)
            $bmp.Dispose()
        }
    }
    foreach ($f in $found) {
        $text = if ($State -eq 'on') { $f.Text.Replace('matrix-phosphor.hlsl', 'matrix-rain.hlsl').Replace('matrix-rain-bg.png', 'matrix-rain-clear.png') }
                else { $f.Text.Replace('matrix-rain.hlsl', 'matrix-phosphor.hlsl').Replace('matrix-rain-clear.png', 'matrix-rain-bg.png') }
        if ($text -eq $f.Text) { continue }
        $b = [IO.File]::ReadAllBytes($f.Path)
        $bom = $b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF
        [IO.File]::WriteAllText($f.Path, $text, (New-Object Text.UTF8Encoding $bom))
    }
    if ($State -eq 'on') {
        Write-Host '代码雨：开。所有 PowerShell 标签页的背景都在下雨了；它会一直占用显卡，看够了运行 rain off' -ForegroundColor Green
    } else {
        Write-Host '代码雨：关。换回静态雨幕和磷光效果' -ForegroundColor DarkGreen
    }
}
