# ---------------------------------------------------------------------------
#  Matrix Minimal for PowerShell + Oh My Posh
#  $PROFILE loads it with:   . (Join-Path $HOME '.config/omp/matrix-minimal.ps1')
#  Keep it next to matrix-minimal.omp.json and MatrixPath.format.ps1xml.
#  Self-check:  Test-MatrixMinimal
# ---------------------------------------------------------------------------

# Settings ------------------------------------------------------------------
#   提示符里的名字、管理员标记：改 matrix-minimal.omp.json 里的 "var"
$global:MatrixPathStyle   = 'bar'      # pwd 输出样式：'bar' 深绿高亮条 | 'plain' 无底色
$global:MatrixMinimalHome = $PSScriptRoot
# 动效（可以在 $PROFILE 里加载本文件之前先定义 $MatrixFx 覆盖）：
#   Intro  新窗口开场 'daily' 每天第一次 | 'always' 每次 | 'off'，按任意键跳过
#   Decode 单独输入 pwd 时路径从片假名逐字解码
#   Glitch 命令失败后新提示符闪一下
if ($null -eq $global:MatrixFx) { $global:MatrixFx = @{ Intro = 'daily'; Decode = $true; Glitch = $true } }

# 1. Prompt -------------------------------------------------------------------
if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
    oh-my-posh init pwsh --config (Join-Path $PSScriptRoot 'matrix-minimal.omp.json') | Invoke-Expression
} else {
    Write-Warning 'Matrix Minimal: 找不到 oh-my-posh 命令，提示符主题没有加载。'
}

# 2. Highlighted pwd / Get-Location / Resolve-Path output --------------------
#    Only the on-screen view changes; piped PathInfo objects stay untouched.
function global:Format-MatrixPath {
    param([string]$Path, [double]$Reveal = 1)              # -Reveal 0..1: share already decoded (pwd animation)
    $e = [char]27
    $t = $Path.TrimEnd('\', '/')
    if ($t.Length -eq 0 -or $t.EndsWith(':')) {
        $parent = ''; $leaf = $Path                         # "C:\", "/", "HKLM:\"
    } else {
        $i = $t.LastIndexOfAny([char[]]@('\', '/'))
        if ($i -lt 0) { $parent = ''; $leaf = $t }
        else { $parent = $t.Substring(0, $i + 1); $leaf = $t.Substring($i + 1) }
    }
    if ($Reveal -lt 1) {
        $chars = ($parent + $leaf).ToCharArray()
        for ($k = [int][math]::Floor($chars.Length * [math]::Max(0, $Reveal)); $k -lt $chars.Length; $k++) {
            $chars[$k] = Get-MatrixGlyph $chars[$k]
        }
        $text = -join $chars
        $parent = $text.Substring(0, $parent.Length); $leaf = $text.Substring($parent.Length)
    }
    $dim = "$e[22;38;2;0;143;17m"                           # #008F11
    $hot = "$e[1;38;2;0;255;65m"                            # #00FF41 bold
    $off = "$e[0m"
    if ($global:MatrixPathStyle -eq 'plain') { return "$dim$parent$hot$leaf$off" }
    return "$e[48;2;0;59;0m$dim $parent$hot$leaf $off"      # bar: #003B00
}

if (-not $global:MatrixMinimalFormatLoaded) {
    try {
        Update-FormatData -PrependPath (Join-Path $PSScriptRoot 'MatrixPath.format.ps1xml') -ErrorAction Stop
        $global:MatrixMinimalFormatLoaded = $true
    } catch {
        Write-Warning "Matrix Minimal: pwd 高亮没有加载（$($_.Exception.Message)）。运行 Test-MatrixMinimal 查看原因。"
    }
}

# 3. Input colors (PSReadLine) ------------------------------------------------
if (Get-Module PSReadLine) {
    & {
        $e = [char]27
        $colors = @{
            Command   = "$e[38;2;0;255;65m"
            Parameter = "$e[38;2;0;143;17m"
            Operator  = "$e[38;2;0;143;17m"
            String    = "$e[38;2;197;228;120m"
            Number    = "$e[38;2;197;228;120m"
            Variable  = "$e[38;2;125;255;184m"
            Comment   = "$e[38;2;61;138;80m"
            Error     = "$e[38;2;255;62;91m"
        }
        if ((Get-Module PSReadLine).Version -ge [version]'2.1.0') {
            $colors.InlinePrediction = "$e[38;2;61;138;80m"
        }
        Set-PSReadLineOption -Colors $colors
    }
}

# 4. Self-check -----------------------------------------------------------------
function global:Test-MatrixMinimal {
    $e = [char]27
    $onWindows = ($PSVersionTable.PSEdition -eq 'Desktop') -or $IsWindows
    $report = [System.Collections.Generic.List[string]]::new()
    $add = {
        param($state, $part, $detail)
        $mark = switch ($state) {
            'ok'    { "$e[38;2;0;255;65m[ok]$e[0m" }
            'bad'   { "$e[38;2;255;62;91m[!!]$e[0m" }
            default { "$e[38;2;61;138;80m[--]$e[0m" }
        }
        $report.Add(('{0} {1} {2}' -f $mark, $part.PadRight(10), $detail))
    }
    $themeHome = $global:MatrixMinimalHome

    # prompt
    if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
        & $add ok 'prompt' "oh-my-posh $(oh-my-posh version)，主题 $(Join-Path $themeHome 'matrix-minimal.omp.json')"
    } else {
        & $add bad 'prompt' '找不到 oh-my-posh 命令'
    }
    $profileFiles = @($PROFILE.AllUsersAllHosts, $PROFILE.AllUsersCurrentHost,
                      $PROFILE.CurrentUserAllHosts, $PROFILE.CurrentUserCurrentHost) |
        Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique
    foreach ($p in $profileFiles) {
        Select-String -Path $p -Pattern '^(?!\s*#).*oh-my-posh(\.exe)?\s+init' | ForEach-Object {
            if ($_.Line -match 'matrix-minimal') {
                & $add info 'prompt' "$($_.Path):$($_.LineNumber) 重复加载了一次主题，可以删掉这一行"
            } else {
                & $add bad 'prompt' "$($_.Path):$($_.LineNumber) 还有一行 oh-my-posh init，可能会换成别的主题"
            }
        }
    }

    # pwd
    $fmt = Join-Path $themeHome 'MatrixPath.format.ps1xml'
    $out = (Get-Location | Out-String -Width 200) -replace "$e\[[0-9;]*m", ''
    if ($out -notmatch '(?m)^\s*-{4,}\s*$') {
        & $add ok 'pwd' '高亮视图已生效'
    } elseif (-not (Test-Path $fmt)) {
        & $add bad 'pwd' "找不到 $fmt"
    } elseif ($onWindows -and (Get-Item $fmt -Stream Zone.Identifier -ErrorAction SilentlyContinue)) {
        & $add bad 'pwd' "文件带有「来自网络」标记，被执行策略拦下了。运行 Unblock-File '$fmt' 后重开终端"
    } else {
        & $add bad 'pwd' '格式视图没有加载，重开终端看看启动时的报错'
    }

    # psreadline
    if (-not (Get-Module PSReadLine)) {
        & $add info 'psreadline' '当前会话没有加载 PSReadLine'
    } elseif ((Get-PSReadLineOption).CommandColor -eq "$e[38;2;0;255;65m") {
        & $add ok 'psreadline' '输入配色已生效'
    } else {
        & $add bad 'psreadline' '输入配色没生效（profile 里后面可能有别的 Set-PSReadLineOption 覆盖了它）'
    }

    # Windows Terminal
    if (-not $env:WT_SESSION) {
        & $add bad 'terminal' '不在 Windows Terminal 里：配色和代码雨只在 Windows Terminal 中生效'
    } else {
        $candidates = @()
        if ($env:LOCALAPPDATA) {
            $candidates = @(
                (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'),
                (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json'),
                (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\settings.json')
            ) | Where-Object { Test-Path $_ }
        }
        $picked = $null
        foreach ($f in $candidates) {
            try { $s = [IO.File]::ReadAllText($f) | ConvertFrom-Json } catch { continue }
            if ($s.profiles -is [array]) { $list = @($s.profiles); $defaults = $null }
            else { $list = @($s.profiles.list); $defaults = $s.profiles.defaults }
            $cur = $list | Where-Object { $_.guid -eq $env:WT_PROFILE_ID } | Select-Object -First 1
            $entry = [pscustomobject]@{ Path = $f; Settings = $s; Profile = $cur; Defaults = $defaults }
            if ($cur) { $picked = $entry; break }
            if (-not $picked) { $picked = $entry }
        }
        if (-not $picked) {
            & $add bad 'terminal' '找不到或读不了 Windows Terminal 的 settings.json'
        } else {
            $get = {
                param($key)
                foreach ($o in @($picked.Profile, $picked.Defaults)) {
                    if ($o -and $o.PSObject.Properties[$key]) { return $o.$key }
                }
            }
            $who = if ($picked.Profile) { "当前标签的配置「$($picked.Profile.name)」" } else { '当前标签用的默认设置' }
            $scheme = & $get 'colorScheme'
            if ($scheme -and $scheme -isnot [string] -and $scheme.dark) { $scheme = $scheme.dark }
            $hasScheme = [bool](@($picked.Settings.schemes) | Where-Object { $_.name -eq 'Matrix Minimal' })
            if (-not $hasScheme) {
                & $add bad 'terminal' 'settings.json 里还没有 Matrix Minimal 配色（运行 install.ps1）'
            } elseif ($scheme -eq 'Matrix Minimal') {
                & $add ok 'terminal' "$who 使用 Matrix Minimal 配色"
            } else {
                & $add bad 'terminal' "$who 的配色是「$scheme」，不是 Matrix Minimal"
            }
            $shader = & $get 'experimental.pixelShaderPath'
            if (-not $shader) {
                & $add bad 'rain' "$who 没有设置代码雨 shader"
            } else {
                $real = [Environment]::ExpandEnvironmentVariables($shader)
                if (Test-Path $real) { & $add ok 'rain' "shader $real" }
                else { & $add bad 'rain' "shader 文件不存在：$real" }
            }
        }
    }

    # admin
    if ($onWindows) {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        if (([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            & $add info 'admin' '管理员会话：提示符以 # 结尾（主题里 var.RootMark 可以改）'
        }
    }

    $report
}

# 5. Effects: wake-up intro, pwd decode, failure glitch ----------------------
#    Switched in $MatrixFx (Settings). Only in an interactive console that understands VT.

$global:MatrixRng        = New-Object Random
$global:MatrixKanaNarrow = [char[]](0xFF66..0xFF9D)      # half-width katakana: one column each
$global:MatrixKanaWide   = [char[]](0x30A2..0x30F3)      # full-width katakana: two columns each

# Columns a character takes on screen: 2 for CJK and full-width forms, else 1.
function global:Get-MatrixCharWidth([char]$c) {
    $n = [int]$c
    if (($n -ge 0x1100 -and $n -le 0x115F) -or ($n -ge 0x2E80 -and $n -le 0xA4CF) -or
        ($n -ge 0xAC00 -and $n -le 0xD7A3) -or ($n -ge 0xF900 -and $n -le 0xFAFF) -or
        ($n -ge 0xFE30 -and $n -le 0xFE4F) -or ($n -ge 0xFF00 -and $n -le 0xFF60) -or
        ($n -ge 0xFFE0 -and $n -le 0xFFE6)) { return 2 }
    1
}

# A random katakana exactly as wide as $c, so scrambled text keeps its length on screen.
function global:Get-MatrixGlyph([char]$c) {
    if ($c -eq ' ') { return $c }
    if ((Get-MatrixCharWidth $c) -eq 2) { return $global:MatrixKanaWide[$global:MatrixRng.Next($global:MatrixKanaWide.Length)] }
    $global:MatrixKanaNarrow[$global:MatrixRng.Next($global:MatrixKanaNarrow.Length)]
}

# Sleep up to $Ms milliseconds; $true as soon as a key is waiting.
function global:Wait-MatrixKey([int]$Ms) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.ElapsedMilliseconds -lt $Ms) {
        if ([Console]::KeyAvailable) { return $true }
        [Threading.Thread]::Sleep(5)
    }
    $false
}

# --- pwd decode ---
# Typed on its own at the prompt, pwd decodes the path from katakana, left to right (~0.3 s).
# Everything else (pwd | clip, $p = pwd, pwd -Stack, scripts) gets Get-Location's normal objects.
function global:Show-MatrixLocation {
    if ($global:MatrixFx.Decode -and $args.Count -eq 0 -and $MyInvocation.CommandOrigin -eq 'Runspace' -and
        $MyInvocation.Line.Trim() -eq $MyInvocation.InvocationName -and
        -not [Console]::IsOutputRedirected -and $Host.UI.SupportsVirtualTerminal) {
        $path = (Get-Location).Path
        $e = [char]27
        $out = $Host.UI                 # Unicode-safe (Console.Out would turn katakana into ? on some code pages)
        try {
            $out.Write("`n$e[?25l")
            for ($f = 0; $f -lt 14; $f++) {
                $out.Write("`r" + (Format-MatrixPath $path -Reveal ($f / 14)) + "$e[K")
                [Threading.Thread]::Sleep(20)
            }
            $out.Write("`r" + (Format-MatrixPath $path) + "$e[K`n`n")   # same layout as the normal view
        } finally { $out.Write("$e[?25h") }
        return
    }
    Get-Location @args
}
Set-Alias -Name pwd -Value Show-MatrixLocation -Scope Global -Option AllScope -Force   # AllScope: Windows PowerShell's pwd has it

# --- hooks ---
# Remember the text of every prompt (the glitch redraws it). oh-my-posh makes a new prompt
# function on every init (theme switch), so this is re-checked before each input.
function global:Register-MatrixPrompt {
    $current = Get-Command prompt -CommandType Function -ErrorAction SilentlyContinue
    if (-not $current -or $current.ScriptBlock.ToString().Contains('MatrixPromptInner')) { return }
    $global:MatrixPromptInner = $current.ScriptBlock
    Set-Item function:global:prompt -Value {
        # oh-my-posh reads the last command's success from this variable when it is set;
        # it must be taken before anything here changes $?
        $global:NVS_ORIGINAL_LASTEXECUTIONSTATUS = $?
        try { $text = & $global:MatrixPromptInner }
        finally { Remove-Variable NVS_ORIGINAL_LASTEXECUTIONSTATUS -Scope Global -ErrorAction SilentlyContinue }
        $global:MatrixLastPrompt = -join $text
        # tab title = current path, unless a theme switcher (posh-theme) already manages titles
        if (-not $global:PoshThemeVersion) { try { $Host.UI.RawUI.WindowTitle = Get-MatrixTabPath } catch { } }
        $text
    }
}

# "~\work\demo", or "…\parent\leaf" when deeper than three levels
function global:Get-MatrixTabPath {
    $loc = Get-Location
    $p = if ($loc.Provider.Name -eq 'FileSystem') { $loc.ProviderPath } else { $loc.Path }
    if ($p -eq $HOME -or $p.StartsWith("$HOME\", [StringComparison]::OrdinalIgnoreCase)) { $p = '~' + $p.Substring($HOME.Length) }
    $parts = $p.TrimEnd('\') -split '\\'
    if ($parts.Count -gt 3) { $p = [string][char]0x2026 + '\' + ($parts[-2..-1] -join '\') }
    $p
}

# PSReadLine calls PSConsoleHostReadLine whenever it waits for a command, with the new prompt
# already on screen. Neither oh-my-posh nor theme switching replaces it.
function global:Invoke-MatrixBeforeInput {
    if ([Console]::IsOutputRedirected -or -not $Host.UI.SupportsVirtualTerminal) { return }
    Register-MatrixPrompt
    if (-not $global:MatrixIntroChecked) {
        $global:MatrixIntroChecked = $true
        $global:MatrixGlitchHistoryId = (Get-History -Count 1).Id
        if (Test-MatrixIntroDue) { Show-MatrixIntro -Redraw }
        return
    }
    if ($global:MatrixFx.Glitch) { Show-MatrixGlitch }
}

if (-not $global:MatrixReadLineInner -and (Get-Command PSConsoleHostReadLine -CommandType Function -ErrorAction SilentlyContinue)) {
    $global:MatrixReadLineInner = (Get-Command PSConsoleHostReadLine -CommandType Function).ScriptBlock
    function global:PSConsoleHostReadLine {
        try { Invoke-MatrixBeforeInput } catch { }
        & $global:MatrixReadLineInner
    }
}
Register-MatrixPrompt

# --- wake-up intro ---
function global:Test-MatrixIntroDue {
    if ($global:PoshThemeCurrent -and $global:PoshThemeCurrent -ne 'matrix-minimal') { return $false }
    switch ("$($global:MatrixFx.Intro)") {
        'always' { return $true }
        'daily' {
            # several tabs restored at once: only the one that creates today's mark plays
            $dir = Join-Path $env:LOCALAPPDATA 'matrix-minimal'
            $mark = Join-Path $dir ('intro-' + (Get-Date -Format 'yyyyMMdd'))
            try {
                [void][IO.Directory]::CreateDirectory($dir)
                [IO.File]::Open($mark, [IO.FileMode]::CreateNew).Dispose()
            } catch { return $false }
            Get-ChildItem $dir -Filter 'intro-*' | Where-Object { $_.FullName -ne $mark } | Remove-Item -ErrorAction SilentlyContinue
            return $true
        }
    }
    $false
}

# The name in the intro is the one in the prompt: "var.Name" in matrix-minimal.omp.json.
function global:Get-MatrixName {
    try {
        $cfg = [IO.File]::ReadAllText((Join-Path $global:MatrixMinimalHome 'matrix-minimal.omp.json')) | ConvertFrom-Json
        if ($cfg.var.Name) { return $cfg.var.Name }
    } catch { }
    $env:USERNAME
}

# ~$Ms of falling katakana over the whole window, then it drains away. $true if a key cut it short.
function global:Show-MatrixRain([int]$Ms = 1000) {
    $e = [char]27
    $out = $Host.UI                 # Unicode-safe (Console.Out would turn katakana into ? on some code pages)
    $W = [Console]::WindowWidth - 1                     # never write the last column: no wrap, no scroll
    $H = [Console]::WindowHeight
    $rng = $global:MatrixRng
    $kana = $global:MatrixKanaNarrow
    $headColor = "$e[38;2;199;255;209m"
    $trailColor = "$e[38;2;0;255;65m"
    $drops = @(for ($x = 1; $x -le $W; $x += 2) {
        if ($rng.NextDouble() -lt 0.7) { [pscustomobject]@{ X = $x; Y = - $rng.Next(0, $H); Speed = 1 + $rng.Next(0, 2); Len = 6 + $rng.Next(0, 14) } }
    })
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $draining = $false
    while ($true) {
        if (-not $draining -and $sw.ElapsedMilliseconds -ge $Ms) {
            $draining = $true
            foreach ($d in $drops) { $d.Speed += 2 }      # the rain drains off quickly
        }
        $sb = New-Object Text.StringBuilder
        $alive = 0
        foreach ($d in $drops) {
            $old = $d.Y
            $d.Y += $d.Speed
            for ($y = [math]::Max(1, $old); $y -lt $d.Y -and $y -le $H; $y++) {
                [void]$sb.Append("$e[$y;$($d.X)H$trailColor").Append($kana[$rng.Next($kana.Length)])
            }
            if ($d.Y -ge 1 -and $d.Y -le $H) {
                [void]$sb.Append("$e[$($d.Y);$($d.X)H$headColor").Append($kana[$rng.Next($kana.Length)])
            }
            for ($y = [math]::Max(1, $old - $d.Len); $y -lt $d.Y - $d.Len -and $y -le $H; $y++) {
                [void]$sb.Append("$e[$y;$($d.X)H ")
            }
            if ($d.Y - $d.Len -le $H) { $alive++ }
            elseif (-not $draining) { $d.Y = - $rng.Next(0, 8); $d.Len = 6 + $rng.Next(0, 14) }
        }
        $out.Write($sb.ToString())
        if ($alive -eq 0 -or $sw.ElapsedMilliseconds -gt $Ms + 700) { return $false }
        if (Wait-MatrixKey 33) { return $true }
    }
}

# Run it by hand to show it off; -Redraw (used at startup) also draws the prompt again,
# because the intro clears the prompt that was already on screen.
function global:Show-MatrixIntro {
    param([switch]$Redraw)
    $e = [char]27
    $out = $Host.UI                 # Unicode-safe (Console.Out would turn katakana into ? on some code pages)
    $green = "$e[38;2;0;255;65m"
    $block = [char]0x2588
    $lines = "Wake up, $(Get-MatrixName)...", 'The Matrix has you...', 'Follow the white rabbit.'
    $ctrlC = [Console]::TreatControlCAsInput
    $skipped = $false
    try {
        [Console]::TreatControlCAsInput = $true        # Ctrl+C skips the intro instead of breaking the shell
        $out.Write("$e[?25l$e[0m$e[2J$e[H")
        foreach ($line in $lines) {
            $out.Write("$e[2;4H$e[2K$green")
            $clock = [Diagnostics.Stopwatch]::StartNew()
            for ($k = 0; $k -lt $line.Length; $k++) {
                $out.Write("$($line[$k])$block$e[D")
                $wait = ($k + 1) * 22 - $clock.ElapsedMilliseconds   # one character per 22 ms on average,
                if ($wait -gt 0 -and (Wait-MatrixKey $wait)) {          # whatever the timer resolution
                    $skipped = $true; break
                }
                if ([Console]::KeyAvailable) { $skipped = $true; break }
            }
            if ($skipped) { break }
            for ($b = 0; $b -lt 3 -and -not $skipped; $b++) {   # hold the line, cursor blinking
                $out.Write($(if ($b % 2) { "$block$e[D" } else { " $e[D" }))
                $skipped = Wait-MatrixKey 90
            }
            if ($skipped) { break }
        }
        if (-not $skipped) { $skipped = Show-MatrixRain 800 }
    } finally {
        if ($skipped -and [Console]::KeyAvailable) { [void][Console]::ReadKey($true) }   # the key only meant "skip"
        [Console]::TreatControlCAsInput = $ctrlC
        $out.Write("$e[0m$e[2J$e[H$e[38;2;61;138;80mWelcome to the desert of the real.$e[0m`r`n`r`n")
        if ($Redraw) { $out.Write(-join (prompt)) }  # the prompt again, on the cleared screen
        $out.Write("$e[?25h")
    }
}

# --- failure glitch ---
# After a failed command the new prompt jitters with red / green fringes (~0.12 s).
# Skipped: empty lines, Ctrl+C, and interactive apps (Claude Code, vim, ...) whose exit codes mean little.
function global:Show-MatrixGlitch {
    $h = Get-History -Count 1
    if (-not $h -or $h.Id -eq $global:MatrixGlitchHistoryId) { return }
    $global:MatrixGlitchHistoryId = $h.Id
    if ($global:PoshThemeCurrent -and $global:PoshThemeCurrent -ne 'matrix-minimal') { return }
    $core = Get-Module oh-my-posh-core
    if (-not $core) { return }
    $code = & $core { $script:ErrorCode }
    if (-not $code -or $code -eq -1073741510) { return }            # success, or stopped with Ctrl+C
    $cmd = (($h.CommandLine.Trim() -split '\s+')[0] -replace '^.*[\\/]', '') -replace '\.(exe|cmd|bat|ps1)$', ''
    $apps = if ($global:PoshThemeInteractiveApps) { $global:PoshThemeInteractiveApps }
            else { @($global:MatrixNativeApps) + @('vim', 'nvim', 'vi', 'hx', 'nano', 'less', 'htop', 'btop', 'lazygit') }
    if ($cmd -in $apps) { return }

    $p = $global:MatrixLastPrompt
    if (-not $p) { return }
    $e = [char]27
    $left = $p.Split([string[]]@("${e}7"), 2, [StringSplitOptions]::None)[0]     # without the right prompt
    $plain = ($left -replace "$e\[[0-9;?]*[A-Za-z]", '') -replace "$e\][^$([char]7)]*$([char]7)", ''
    if ($plain.Contains("`n")) { return }
    $width = 0
    foreach ($c in $plain.ToCharArray()) { $width += Get-MatrixCharWidth $c }
    if ([Console]::CursorLeft -ne $width) { return }                 # the prompt is not where we think
    $ghost = $plain.TrimEnd()
    $chars = $ghost.ToCharArray()
    for ($k = 0; $k -lt 2; $k++) {                                  # two characters glitch to katakana
        $i = $global:MatrixRng.Next($chars.Length)
        if ($chars[$i] -ne ' ') { $chars[$i] = Get-MatrixGlyph $chars[$i] }
    }
    $broken = -join $chars
    $red = "$e[38;2;255;62;91m"
    $green = "$e[38;2;0;255;65m"
    $out = $Host.UI                 # Unicode-safe (Console.Out would turn katakana into ? on some code pages)
    try {
        $out.Write("$e[?25l")
        $out.Write("`r$e[2K $red$ghost`r$green$broken$e[0m"); [Threading.Thread]::Sleep(40)
        $out.Write("`r$e[2K $green$ghost`r$red$broken$e[0m"); [Threading.Thread]::Sleep(40)
        $out.Write("`r$e[2K  $left$e[0m");                    [Threading.Thread]::Sleep(40)
    } finally {
        $out.Write("`r$e[2K$p$e[?25h")                              # the real prompt, cursor where it was
    }
}
