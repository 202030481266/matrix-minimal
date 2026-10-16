# ---------------------------------------------------------------------------
#  Matrix Minimal: companions for the "Matrix Minimal" Windows Terminal scheme
#  The prompt, the input and the rain use their own RGB greens. Command output gets
#  the scheme: pale phosphor text, and ANSI colours that keep their meaning (red
#  removed / error, green added / success, amber warning, cyan detail, blue, purple).
#  The scheme applies whatever prompt theme is active, so $PROFILE loads this
#  file for every theme:   . (Join-Path $HOME '.config/omp/matrix-terminal.ps1')
# ---------------------------------------------------------------------------

if (-not $env:WT_SESSION) { return }   # the scheme only exists in Windows Terminal

# 1. PowerShell's own colours ------------------------------------------------
#    Verbose and debug messages are amber like warnings by default: give them colours of
#    their own. Get-ChildItem paints directory names on a blue *background*; use a text
#    colour, and colour media files too. Only PowerShell's defaults are replaced, so
#    settings made in $PROFILE before this file is loaded stay.
if ($PSStyle) {
    & {
        $e = [char]27
        $f = $PSStyle.Formatting
        if ($f.Verbose -eq "$e[33;1m") { $f.Verbose = "$e[36m" }    # cyan
        if ($f.Debug -eq "$e[33;1m") { $f.Debug = "$e[35m" }        # purple
        $fi = $PSStyle.FileInfo
        if ($fi.Directory -eq "$e[44;1m") { $fi.Directory = "$e[1;38;2;125;255;184m" }   # bold #7DFFB8
        $add = @{
            "$e[35m"   = '.png', '.jpg', '.jpeg', '.gif', '.bmp', '.webp', '.svg', '.ico',
                         '.mp3', '.wav', '.flac', '.mp4', '.mkv', '.mov', '.avi'
            "$e[31;1m" = '.rar', '.xz', '.bz2', '.zst'                # with the built-in archives
        }
        foreach ($style in $add.Keys) {
            foreach ($x in $add[$style]) { if (-not $fi.Extension.ContainsKey($x)) { $fi.Extension.Add($x, $style) } }
        }
    }
} elseif ($Host.PrivateData -and $Host.PrivateData.PSObject.Properties['VerboseForegroundColor']) {
    # Windows PowerShell: console colours (DarkCyan / DarkMagenta are the scheme's cyan / purple)
    if ($Host.PrivateData.VerboseForegroundColor -eq 'Yellow') { $Host.PrivateData.VerboseForegroundColor = 'DarkCyan' }
    if ($Host.PrivateData.DebugForegroundColor -eq 'Yellow') { $Host.PrivateData.DebugForegroundColor = 'DarkMagenta' }
    # The progress bar is yellow on dark cyan: amber on cyan in this scheme, hard to read
    if ($Host.PrivateData.ProgressForegroundColor -eq 'Yellow' -and $Host.PrivateData.ProgressBackgroundColor -eq 'DarkCyan') {
        $Host.PrivateData.ProgressForegroundColor = 'Black'
    }
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
#    rain       opens a new tab with the moving digital rain (matrix-rain.hlsl). Windows Terminal
#               sets shaders per profile, never per tab, so the rain has a profile of its own,
#               "Matrix Rain", added to settings.json the first time; other tabs keep the still
#               rain. That tab redraws all the time, which keeps the GPU busy even while another
#               tab is in front or the window is minimised (measured): close it when done.
#    rain off   tells you to close that tab; it also undoes "rain on" of earlier versions, which
#               made every PowerShell profile rain
#    settings.json is edited as text, so comments and formatting stay as they are; the terminal
#    picks the change up by itself.
function global:rain {
    param([string]$State)
    if ($State -and $State -notin 'on', 'off') { Write-Host '用法：rain（新开一个下雨的标签页）| rain off'; return }
    $guid = '{4d415452-4958-5241-494e-6d696e696d61}'   # "MATRIXRAINminima"
    $here = $env:WT_PROFILE_ID -eq $guid
    if ($State -ne 'off' -and $here) { Write-Host '这个标签页就在下雨；关掉它，雨就停了' -ForegroundColor Green; return }

    # The entries of profiles.list, found on the text: settings.json may hold comments, which
    # Windows PowerShell's ConvertFrom-Json rejects. Returns the index of the list's "[" and "]"
    # and, for each entry, where it starts and ends (after its "}") and its guid.
    function Get-ProfileList([string]$Text) {
        $keys = New-Object Collections.Generic.List[string]   # the key of every open bracket
        $prev = $null; $depth = 0; $list = $null
        foreach ($m in [regex]::Matches($Text, '"(?:[^"\\]|\\.)*"|//[^\n]*|/\*[\s\S]*?\*/|[{}\[\]]')) {
            $t = $m.Value
            if ($t[0] -eq [char]'/') { continue }
            $key = ''                                         # this token is the value of $key
            if ($prev -and $prev.Value[0] -eq [char]'"' -and
                $Text.Substring($prev.Index + $prev.Length, $m.Index - $prev.Index - $prev.Length) -match '^\s*:\s*$') { $key = $prev.Value }
            $prev = $m
            if ($t[0] -eq [char]'"') {
                if ($list -and $keys.Count -eq $depth + 1 -and $key -eq '"guid"') { $list.Items[$list.Items.Count - 1].Guid = $t.Trim('"') }
            } elseif ($t -eq '{' -or $t -eq '[') {
                $keys.Add($key)
                if ($list) {
                    if ($keys.Count -eq $depth + 1 -and $t -eq '{') { $list.Items.Add(@{ Start = $m.Index; End = -1; Guid = $null }) }
                } elseif ($t -eq '[' -and (($keys.Count -eq 3 -and $keys[1] -eq '"profiles"' -and $key -eq '"list"') -or
                                           ($keys.Count -eq 2 -and $key -eq '"profiles"'))) {   # very old files: "profiles": [ ... ]
                    $list = @{ Open = $m.Index; Close = -1; Items = New-Object Collections.Generic.List[object] }
                    $depth = $keys.Count
                }
            } else {
                if ($list -and $keys.Count -eq $depth + 1 -and $t -eq '}') { $list.Items[$list.Items.Count - 1].End = $m.Index + 1 }
                if ($list -and $keys.Count -eq $depth) { $list.Close = $m.Index; return $list }
                if ($keys.Count) { $keys.RemoveAt($keys.Count - 1) }
            }
        }
    }
    function Save-Settings($File, [string]$Text) {
        $b = [IO.File]::ReadAllBytes($File.Path)
        $bom = $b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF
        [IO.File]::WriteAllText($File.Path, $Text, (New-Object Text.UTF8Encoding $bom))
    }

    $settings = @(
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'),
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\settings.json')
    ) | Where-Object { Test-Path $_ }
    $found = @(foreach ($path in $settings) {
        $text = [IO.File]::ReadAllText($path)
        if ($text -match 'matrix-(phosphor|rain)\.hlsl') { @{ Path = $path; Text = $text; List = Get-ProfileList $text } }
    })
    if (-not $found) { Write-Warning 'Windows Terminal 里没有使用 Matrix Minimal 的配置（先运行安装）'; return }

    if ($State -eq 'off') {
        # Earlier versions swapped the moving rain into every PowerShell profile. Swap it back in
        # those entries only, last one first so the positions found before stay right.
        $undone = $false
        foreach ($f in $found) {
            if (-not $f.List) { continue }
            $text = $f.Text
            for ($i = $f.List.Items.Count - 1; $i -ge 0; $i--) {
                $it = $f.List.Items[$i]
                $entry = $text.Substring($it.Start, $it.End - $it.Start)
                if ($it.Guid -eq $guid -or -not $entry.Contains('matrix-rain-clear.png')) { continue }
                $entry = $entry.Replace('matrix-rain.hlsl', 'matrix-phosphor.hlsl').Replace('matrix-rain-clear.png', 'matrix-rain-bg.png')
                $text = $text.Substring(0, $it.Start) + $entry + $text.Substring($it.End)
            }
            if ($text -ne $f.Text) { Save-Settings $f $text; $undone = $true }
        }
        if ($undone) { Write-Host '代码雨：关。PowerShell 标签页换回静态雨幕和磷光效果' -ForegroundColor DarkGreen }
        if ($here) { Write-Host '这个标签页就是下雨的那个，关掉它，雨就停了' -ForegroundColor DarkGreen }
        elseif (-not $undone) { Write-Host '代码雨只在 "Matrix Rain" 标签页里下，关掉那个标签页就停了' -ForegroundColor DarkGreen }
        return
    }

    $omp = Join-Path $HOME '.config\omp'
    if (-not (Test-Path (Join-Path $omp 'matrix-rain.hlsl'))) { Write-Warning "找不到 $omp\matrix-rain.hlsl（重新运行一次安装）"; return }
    $added = $false
    foreach ($f in $found) {
        $list = $f.List
        if (-not $list) { Write-Warning "$($f.Path) 里找不到 profiles.list，没有修改"; continue }
        if ($list.Items | Where-Object { $_.Guid -eq $guid }) { continue }
        # Indent like the first entry: the line of its "{", then the line of its first key
        $text = $f.Text
        $nl = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
        $first = if ($list.Items.Count) { $list.Items[0].Start } else { $list.Open }
        $lineStart = $text.LastIndexOf("`n", $first) + 1
        $indent = [regex]::Match($text.Substring($lineStart), '^[ \t]*').Value
        if (-not $list.Items.Count) { $indent += '    ' }      # an empty list: one level below its "["
        $inner = [regex]::Match($text.Substring($first + 1), '^[ \t]*\r?\n([ \t]*)"')
        $inner = if ($list.Items.Count -and $inner.Success) { $inner.Groups[1].Value } else { $indent + '    ' }
        $shell = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh.exe -NoLogo' } else { '%SystemRoot%\\System32\\WindowsPowerShell\\v1.0\\powershell.exe -NoLogo' }
        $props = @(
            "`"guid`": `"$guid`""
            '"name": "Matrix Rain"'
            "`"commandline`": `"$shell`""
            '"colorScheme": "Matrix Minimal"'
            '"cursorShape": "filledBox"'
            '"opacity": 100'
            '"useAcrylic": false'
            '"experimental.pixelShaderPath": "%USERPROFILE%\\.config\\omp\\matrix-rain.hlsl"'
        )
        $entry = '{' + $nl + (($props | ForEach-Object { $inner + $_ }) -join (',' + $nl)) + $nl + $indent + '}'
        if ($list.Items.Count) { $at = $list.Items[$list.Items.Count - 1].End; $entry = ',' + $nl + $indent + $entry }
        else { $at = $list.Open + 1; $entry = $nl + $indent + $entry }
        Save-Settings $f ($text.Insert($at, $entry))
        $added = $true
    }

    $wt = $null
    foreach ($d in $env:Path.Split(';')) {
        $d = $d.Trim().Trim('"')
        if ($d -and [IO.File]::Exists($d + '\wt.exe')) { $wt = $d + '\wt.exe'; break }
    }
    if (-not $wt) {
        Write-Host '找不到 wt.exe（Windows Terminal 的应用执行别名可能被关了）：从标签栏的 + 菜单里打开 "Matrix Rain"' -ForegroundColor Yellow
        return
    }
    # Windows Terminal reloads settings.json by itself. Asked for the profile too early, it silently
    # opens another one: 0 ms was too early in testing, 100 ms enough; 1 s leaves room for slow machines.
    if ($added) { Start-Sleep -Milliseconds 1000 }
    # The new tab runs this same PowerShell, in this folder. wt.exe splits its arguments at ";".
    $exe = if ($PSVersionTable.PSEdition -ne 'Core') { Join-Path $PSHOME 'powershell.exe' }
           elseif ($PSHOME -like '*\WindowsApps\*') { 'pwsh.exe' }   # Microsoft Store: start it through its alias
           else { Join-Path $PSHOME 'pwsh.exe' }
    $dir = (Get-Location -PSProvider FileSystem).ProviderPath.Replace(';', '\;')
    & $wt -w 0 nt -p $guid -d $dir $exe -NoLogo
    Write-Host '代码雨在新标签页 "Matrix Rain" 里下，别的标签页不受影响。它会一直占用显卡（切到别的标签页也不会停），看够了关掉那个标签页就行' -ForegroundColor Green
}
