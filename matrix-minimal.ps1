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
#   Intro  开场 'launch' 每次启动终端（Windows Terminal、VS Code）的第一个标签页（默认）| 'daily' 每天第一次
#          | 'always' 每个新标签页 | 'off'。launch 和 daily 下，没轮到的新标签页只显示结尾的大字。按任意键跳过
#   Decode 单独输入 pwd 时路径从片假名逐字解码
#   Glitch 命令失败后新提示符闪一下
if ($null -eq $global:MatrixFx) { $global:MatrixFx = @{ Intro = 'launch'; Decode = $true; Glitch = $true } }

# 1. Prompt -------------------------------------------------------------------
& {
    # setup.ps1 puts oh-my-posh here. A terminal started before the install (or before the
    # PATH change reached Explorer) still has the old PATH, so add it for this session.
    $ompBin = Join-Path $env:LOCALAPPDATA 'Programs\oh-my-posh\bin'
    if ((Test-Path (Join-Path $ompBin 'oh-my-posh.exe')) -and (($env:Path -split ';') -notcontains $ompBin)) { $env:Path = "$ompBin;$env:Path" }
    # The intro / glitch hooks and the input colours need PSReadLine loaded now, not later.
    if (-not (Get-Module PSReadLine)) { Import-Module PSReadLine -ErrorAction SilentlyContinue }
}

# If the "theme" switcher (posh-theme) is already loaded, matrix-minimal becomes one of its
# themes and lets it run oh-my-posh: a second "oh-my-posh init" here would drop posh-theme's
# tab hooks (the busy spinner would never stop) and leave "theme" reporting another theme.
function global:Register-MatrixWithPoshTheme {
    if (-not $global:PoshThemes -or -not (Get-Command Initialize-PoshTheme -CommandType Function -ErrorAction SilentlyContinue)) { return $false }
    $stub = Join-Path $HOME '.posh-themes\matrix-minimal.omp.json'         # where posh-theme looks for extra themes
    if (-not (Test-Path $stub)) {
        New-Item -ItemType Directory -Force -Path (Split-Path $stub) | Out-Null
        $config = (Join-Path $global:MatrixMinimalHome 'matrix-minimal.omp.json') | ConvertTo-Json
        [IO.File]::WriteAllText($stub, "{`n  `"extends`": $config,`n  `"final_space`": true`n}`n")
    }
    if ($global:PoshThemes -notcontains 'matrix-minimal') { $global:PoshThemes += 'matrix-minimal' }
    $true
}
# The prompt shows the active Python environment itself (the "python" segment). oh-my-posh
# already silences venv's own "(name) "; CONDA_CHANGEPS1 silences conda's, which is written
# ahead of the prompt when conda's hook runs after this file (the "Anaconda PowerShell Prompt"
# shortcut does). Only while this prompt is the one in use: other themes may not show it.
if (Register-MatrixWithPoshTheme) {
    $saved = "$(Get-Content $global:PoshThemeFile -ErrorAction SilentlyContinue)".Trim()
    if ($saved -eq 'matrix-minimal') {
        if ($global:PoshThemeCurrent -ne 'matrix-minimal') {
            Initialize-PoshTheme 'matrix-minimal'
            $global:PoshThemeCurrent = 'matrix-minimal'
        }
        $env:CONDA_CHANGEPS1 = 'false'
    }
} elseif (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
    oh-my-posh init pwsh --config (Join-Path $PSScriptRoot 'matrix-minimal.omp.json') | Invoke-Expression
    $env:CONDA_CHANGEPS1 = 'false'
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
            Command   = "$e[38;2;0;255;65m"         # matrix green
            Parameter = "$e[38;2;46;230;214m"       # cyan
            Operator  = "$e[38;2;111;162;124m"
            String    = "$e[38;2;255;200;97m"       # amber
            Number    = "$e[38;2;221;182;255m"      # light purple
            Variable  = "$e[38;2;132;174;255m"      # blue pill
            Keyword   = "$e[38;2;195;139;255m"      # purple
            Type      = "$e[38;2;46;230;214m"       # cyan
            Comment   = "$e[38;2;61;138;80m"
            Error     = "$e[38;2;255;62;91m"        # red pill
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
    if ($env:TERM_PROGRAM -eq 'vscode') {
        & $add info 'terminal' 'VS Code 终端：配色和代码雨只在 Windows Terminal 中生效'
    } elseif (-not $env:WT_SESSION) {
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
            # the still rain is the background image; "Matrix Rain" tabs have the moving one, a shader
            $raining = $picked.Profile -and $picked.Profile.guid -eq '{4d415452-4958-5241-494e-6d696e696d61}'
            $what = if ($raining) { '代码雨 shader' } else { '雨幕背景图' }
            $file = if ($raining) { & $get 'experimental.pixelShaderPath' } else { & $get 'backgroundImage' }
            if (-not $file) {
                & $add bad 'rain' "$who 没有设置$what"
            } else {
                $real = [Environment]::ExpandEnvironmentVariables($file)
                if (Test-Path $real) { & $add ok 'rain' "$what $real" }
                else { & $add bad 'rain' "$what 不存在：$real" }
            }
        }
    }

    # intro / glitch hooks (another wrapper may sit in front of ours, e.g. VS Code's: then ours
    # ran when this command was read)
    $readLine = Get-Command PSConsoleHostReadLine -CommandType Function -ErrorAction SilentlyContinue
    if (-not ($global:MatrixReadLineSeen -or ($readLine -and $readLine.ScriptBlock.ToString().Contains('Invoke-MatrixReadLine')))) {
        & $add bad 'intro' '开场 / 故障闪烁的钩子没有装上（PSReadLine 没有加载？）'
    } elseif ($global:PoshThemeCurrent -and $global:PoshThemeCurrent -ne 'matrix-minimal') {
        & $add info 'intro' "theme 当前是 $global:PoshThemeCurrent：开场和故障闪烁只在 matrix-minimal 下出现"
    } else {
        $mode = "$($global:MatrixFx.Intro)"
        $todayMark = Join-Path $global:MatrixIntroMarks ('intro-' + (Get-Date -Format 'yyyyMMdd'))
        $detail = switch ($mode) {
            'launch' { '每次启动终端播一次，之后新开的标签页只显示结尾的大字' }
            'always' { '每个新标签页都播' }
            'daily'  { if (Test-Path $todayMark) { '每天一次，今天已经播过（新标签页只显示结尾的大字）' } else { '每天一次，今天还没播' } }
            default  { "已关闭（`$MatrixFx.Intro = '$mode'）" }
        }
        & $add ok 'intro' "$detail；随时运行 Show-MatrixIntro 重播"
    }
    if ($global:MatrixHookError) {
        $where = ($global:MatrixHookError.InvocationInfo.PositionMessage -split "`n")[0]
        & $add bad 'intro' "上次出错：$($global:MatrixHookError.Exception.Message) $where"
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
# Two hooks, each wrapping the function that was there before:
#   prompt                 remembers the text of every prompt (the glitch redraws it); the first
#                          prompt of a session plays the intro (every host calls the prompt)
#   PSConsoleHostReadLine  PSReadLine calls it whenever it waits for a command, with the new
#                          prompt already on screen: the glitch, and the intro when the first
#                          prompt was not ours yet
# Others replace them later (oh-my-posh makes a new prompt on every init, i.e. theme switch;
# importing PSReadLine again brings back its own function) or wrap them in turn (VS Code's
# shell integration, after the profile). So each hook checks that the other one still ran in
# the last round and wraps whatever is there now if not; a wrapper around ours still runs ours.
# Each wrapper keeps the function it wraps for itself (GetNewClosure): wrappers around
# wrappers never call each other in a loop.
function global:Register-MatrixPrompt {
    $current = Get-Command prompt -CommandType Function -ErrorAction SilentlyContinue
    if (-not $current -or $current.ScriptBlock.ToString().Contains('Invoke-MatrixPrompt')) { return }
    $inner = $current.ScriptBlock
    # $? (the last command's success) has to be taken before anything else runs
    Set-Item function:global:prompt -Value { Invoke-MatrixPrompt $inner $? }.GetNewClosure()
}

function global:Invoke-MatrixPrompt([scriptblock]$Inner, [bool]$LastStatus) {
    # oh-my-posh reads the last command's success from this variable when it is set
    $global:NVS_ORIGINAL_LASTEXECUTIONSTATUS = $LastStatus
    if (-not $global:MatrixInReadLine) {        # not a prompt redrawn while waiting for input
        $global:MatrixPromptSeen = $true
        if (-not $global:MatrixIntroChecked) { try { Start-MatrixSession } catch { $global:MatrixHookError = $_ } }
        # put the input hook back if the last round went without it ($null: no round yet)
        if ($global:MatrixReadLineSeen -eq $false) { try { Register-MatrixReadLine } catch { } }
        $global:MatrixReadLineSeen = $false
    }
    try {
        # $? again for the wrapped prompt: when it is a wrapper itself (VS Code's), it reads it
        if (-not $LastStatus) { Write-Error 'last command failed' -ErrorAction Ignore }
        $text = & $Inner
    } finally { Remove-Variable NVS_ORIGINAL_LASTEXECUTIONSTATUS -Scope Global -ErrorAction SilentlyContinue }
    $global:MatrixLastPrompt = -join $text
    # tab title = current path, unless a theme switcher (posh-theme) already manages titles
    if (-not $global:PoshThemeVersion) { try { $Host.UI.RawUI.WindowTitle = Get-MatrixTabPath } catch { } }
    $text
}

# Once per session, from the first prompt (or, when that prompt was not ours yet, the first
# wait for input): tell the theme switcher about the easter egg and play the intro.
function global:Start-MatrixSession([switch]$Redraw) {
    if ($global:MatrixIntroChecked) { return }
    $global:MatrixIntroChecked = $true
    $global:MatrixGlitchHistoryId = (Get-History -Count 1).Id
    # the "matrix" easter egg is interactive: no busy spinner from the theme switcher (posh-theme)
    if ($global:PoshThemeInteractiveApps -and $global:PoshThemeInteractiveApps -notcontains 'matrix') {
        $global:PoshThemeInteractiveApps += 'matrix'
    }
    if ([Console]::IsOutputRedirected -or -not $Host.UI.SupportsVirtualTerminal) { return }
    $kind = Get-MatrixIntroKind
    if ($kind) {
        try { Show-MatrixIntro -Redraw:$Redraw -TitleOnly:($kind -eq 'title') }
        catch {
            # 'launch' / 'daily': give the turn back, so the next tab tries again
            if ($global:MatrixIntroMark) { Remove-Item $global:MatrixIntroMark -ErrorAction SilentlyContinue }
            throw
        }
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

function global:Register-MatrixReadLine {
    $current = Get-Command PSConsoleHostReadLine -CommandType Function -ErrorAction SilentlyContinue
    if (-not $current -or $current.ScriptBlock.ToString().Contains('Invoke-MatrixReadLine')) { return }
    $inner = $current.ScriptBlock
    Set-Item function:global:PSConsoleHostReadLine -Value { Invoke-MatrixReadLine $inner }.GetNewClosure()
}

function global:Invoke-MatrixReadLine([scriptblock]$Inner) {
    $global:MatrixReadLineSeen = $true
    $global:MatrixInReadLine = $true            # prompts from here on are redraws (intro, Ctrl+L)
    try {
        try { Invoke-MatrixBeforeInput } catch { $global:MatrixHookError = $_ }   # shown by Test-MatrixMinimal
        & $Inner
    } finally { $global:MatrixInReadLine = $false }
}

function global:Invoke-MatrixBeforeInput {
    if ([Console]::IsOutputRedirected -or -not $Host.UI.SupportsVirtualTerminal) { return }
    if (-not $global:MatrixPromptSeen) { Register-MatrixPrompt }   # the last prompt was not ours
    $global:MatrixPromptSeen = $false
    # "theme -Update" reloads posh-theme, which resets its theme list
    if ($global:PoshThemes -and $global:PoshThemes -notcontains 'matrix-minimal') { $global:PoshThemes += 'matrix-minimal' }
    if (-not $global:MatrixIntroChecked) { Start-MatrixSession -Redraw; return }   # the first prompt was not ours yet
    if ($global:MatrixFx.Glitch) { Show-MatrixGlitch }
}
Register-MatrixReadLine
Register-MatrixPrompt

# --- wake-up intro ---
# Who has had the intro: an empty file per day ('daily') or per terminal ('launch')
$global:MatrixIntroMarks = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'matrix-minimal'

# What a new tab shows: 'full' (the whole intro), 'title' (only its last words) or '' (nothing).
function global:Get-MatrixIntroKind {
    $global:MatrixIntroMark = $null
    if ($global:PoshThemeCurrent -and $global:PoshThemeCurrent -ne 'matrix-minimal') { return '' }
    $mode = "$($global:MatrixFx.Intro)"
    if ($mode -eq 'always') { return 'full' }
    if ($mode -notin 'launch', 'daily') { return '' }
    $name = if ($mode -eq 'daily') { 'intro-' + (Get-Date -Format 'yyyyMMdd') } else { try { Get-MatrixTerminalMark } catch { $null } }
    if (-not $name) { return 'full' }                               # a console window of its own (or no way to tell)
    # several tabs opened at once (restored by the terminal): only the one that creates the mark plays
    $dir = $global:MatrixIntroMarks
    $mark = Join-Path $dir $name
    try {
        [void][IO.Directory]::CreateDirectory($dir)
        [IO.File]::Open($mark, [IO.FileMode]::CreateNew).Dispose()
    } catch { return 'title' }
    # drop the marks of other days, and of terminals no longer running
    foreach ($f in Get-ChildItem $dir -Filter ($name.Split('-')[0] + '-*')) {
        if ($f.Name -eq $name) { continue }
        if ($f.Name -match '^launch-(\d+)-(\d+)$') {
            $p = try { [Diagnostics.Process]::GetProcessById([int]$Matches[1]) } catch { $null }
            if ($p -and $(try { "$($p.StartTime.Ticks)" -eq $Matches[2] } catch { $true })) { continue }
        }
        Remove-Item $f.FullName -ErrorAction SilentlyContinue
    }
    $global:MatrixIntroMark = $mark
    'full'
}

# "launch-<id>-<start time>" of the process this tab runs in: Windows Terminal, VS Code, ... (past
# any PowerShell started inside the tab). Nothing for a console window started from Explorer or
# the Start menu: that window is a terminal of its own.
function global:Get-MatrixTerminalMark {
    $p = [Diagnostics.Process]::GetCurrentProcess()
    $ntdll = $null
    for ($i = 0; $p -and $i -lt 8 -and $p.ProcessName -in 'pwsh', 'powershell'; $i++) {
        if ($PSVersionTable.PSEdition -eq 'Core') { $p = $p.Parent; continue }
        # Windows PowerShell has no .Parent: ask ntdll, through a P/Invoke made at run time
        # (Add-Type would start the C# compiler, WMI takes ~0.3 s)
        if (-not $ntdll) {
            $asm = [Reflection.Emit.AssemblyBuilder]::DefineDynamicAssembly((New-Object Reflection.AssemblyName 'MatrixNtdll'), 'Run')
            $type = $asm.DefineDynamicModule('MatrixNtdll').DefineType('MatrixNtdll', 'Public, Class')
            [void]$type.DefinePInvokeMethod('NtQueryInformationProcess', 'ntdll.dll', 'Public, Static, PinvokeImpl', 'Standard',
                [int], [Type[]]@([IntPtr], [int], [IntPtr[]], [int], [IntPtr]), 'Winapi', 'Auto')
            $ntdll = $type.CreateType()
        }
        $info = New-Object IntPtr[] 6                               # PROCESS_BASIC_INFORMATION; [5] is the parent's id
        $p = if ($ntdll::NtQueryInformationProcess($p.Handle, 0, $info, 6 * [IntPtr]::Size, [IntPtr]::Zero) -eq 0) {
            try { [Diagnostics.Process]::GetProcessById([int]$info[5]) } catch { $null }
        }
    }
    if (-not $p -or $p.ProcessName -in 'pwsh', 'powershell', 'explorer') { return $null }
    "launch-$($p.Id)-$(try { $p.StartTime.Ticks } catch { 0 })"
}

# The name in the intro is the one in the prompt: "var.Name" in matrix-minimal.omp.json.
function global:Get-MatrixName {
    try {
        $cfg = [IO.File]::ReadAllText((Join-Path $global:MatrixMinimalHome 'matrix-minimal.omp.json')) | ConvertFrom-Json
        if ($cfg.var.Name) { return $cfg.var.Name }
    } catch { }
    $env:USERNAME
}

# Falling katakana over the whole window, then it drains away.
#   -Ms n      rain for n ms; returns $true if a key cut it short (the intro)
#   -UntilKey  rain until a key is pressed, which it swallows (the red pill)
function global:Show-MatrixRain([int]$Ms = 1000, [switch]$UntilKey) {
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
    $drainedAt = 0
    while ($true) {
        if (-not $draining) {
            $stop = if ($UntilKey) { [Console]::KeyAvailable } else { $sw.ElapsedMilliseconds -ge $Ms }
            if ($stop) {
                if ($UntilKey) { [void][Console]::ReadKey($true) }
                $draining = $true
                $drainedAt = $sw.ElapsedMilliseconds
                foreach ($d in $drops) { $d.Speed += 2 }  # the rain drains off quickly
            }
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
        if ($alive -eq 0 -or ($draining -and $sw.ElapsedMilliseconds - $drainedAt -gt 700)) { return $false }
        if ($UntilKey) { [Threading.Thread]::Sleep(33) }
        elseif (Wait-MatrixKey 33) { return $true }
    }
}

# The intro's last words, "Welcome to the desert of the real": DESERT in big letters (figlet's
# "ANSI Shadow": blocks for the face, box lines for the shadow), the rest small around it.
$global:MatrixDesert = @(
    '██████╗ ███████╗███████╗███████╗██████╗ ████████╗'
    '██╔══██╗██╔════╝██╔════╝██╔════╝██╔══██╗╚══██╔══╝'
    '██║  ██║█████╗  ███████╗█████╗  ██████╔╝   ██║   '
    '██║  ██║██╔══╝  ╚════██║██╔══╝  ██╔══██╗   ██║   '
    '██████╔╝███████╗███████║███████╗██║  ██║   ██║   '
    '╚═════╝ ╚══════╝╚══════╝╚══════╝╚═╝  ╚═╝   ╚═╝   '
)

# Draws them at the top of the (cleared) screen, decoding from katakana left to right like
# pwd (~0.3 s; a key shows them at once, and is swallowed unless -KeepKey), or at once with
# -Instant. One plain line when the window is too small for the big letters.
function global:Show-MatrixWelcome([switch]$Instant, [switch]$KeepKey) {
    $e = [char]27
    $out = $Host.UI                 # Unicode-safe (Console.Out would turn katakana into ? on some code pages)
    $big = $global:MatrixDesert
    $w = $big[0].Length
    if ([Console]::WindowWidth -lt $w + 3 -or [Console]::WindowHeight -lt 12) {
        $out.Write("$e[38;2;61;138;80mWelcome to the desert of the real.$e[0m`r`n`r`n")
        return
    }
    $lines = @('W E L C O M E   T O   T H E') + $big + @('O F   T H E   R E A L'.PadLeft($w))
    $small = "$e[38;2;61;138;80m"
    $face = "$e[38;2;0;255;65m"
    $shadow = "$e[38;2;0;143;17m"
    $head = "$e[38;2;199;255;209m"                  # the decoding edge, like the head of a raindrop
    $kana = $global:MatrixKanaNarrow                # every cell here is one column wide
    $rng = $global:MatrixRng
    $f = if ($Instant) { 14 } else { 0 }
    while ($true) {
        $edge = [int][math]::Floor(($w + 1) * $f / 14)     # columns left of it are decoded
        $sb = New-Object Text.StringBuilder
        [void]$sb.Append("$e[H")
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]
            $last = ''
            [void]$sb.Append('  ')
            for ($k = 0; $k -lt $line.Length; $k++) {
                $c = $line[$k]
                if ($c -eq ' ') { [void]$sb.Append(' '); continue }
                $color = if ($i -eq 0 -or $i -eq $lines.Count - 1) { $small } elseif ($c -eq [char]0x2588) { $face } else { $shadow }
                if ($k -ge $edge) {
                    if ($k -lt $edge + 2) { $color = $head }
                    $c = $kana[$rng.Next($kana.Length)]
                }
                if ($color -ne $last) { [void]$sb.Append($color); $last = $color }
                [void]$sb.Append($c)
            }
            [void]$sb.Append("$e[0m`r`n")
        }
        $out.Write($sb.ToString())
        if ($f -ge 14) { break }
        if (Wait-MatrixKey 20) { if (-not $KeepKey) { [void][Console]::ReadKey($true) }; $f = 14 } else { $f++ }
    }
    $out.Write("`r`n")
}

# Run it by hand to show it off; -Redraw (used at startup) also draws the prompt again,
# because the intro clears the prompt that was already on screen. -TitleOnly: only the last
# words (new tabs that do not get the whole intro); a key typed meanwhile is input, not "skip".
function global:Show-MatrixIntro {
    param([switch]$Redraw, [switch]$TitleOnly)
    $e = [char]27
    $out = $Host.UI                 # Unicode-safe (Console.Out would turn katakana into ? on some code pages)
    $green = "$e[38;2;0;255;65m"
    $block = [char]0x2588
    $lines = if ($TitleOnly) { @() } else { "Wake up, $(Get-MatrixName)...", 'The Matrix has you...', 'Follow the white rabbit.' }
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
        if (-not ($skipped -or $TitleOnly)) { $skipped = Show-MatrixRain 800 }
    } finally {
        if ($skipped -and [Console]::KeyAvailable) { [void][Console]::ReadKey($true) }   # the key only meant "skip"
        $out.Write("$e[0m$e[2J$e[H")
        try { Show-MatrixWelcome -Instant:$skipped -KeepKey:$TitleOnly } catch { $global:MatrixHookError = $_ }   # skipped: at once
        [Console]::TreatControlCAsInput = $ctrlC
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

# --- easter egg: type "matrix" ---
# Morpheus offers the pills. Red: rain until a key is pressed, then a line from the film,
# which stays in the terminal. Blue: the story ends. Esc or Ctrl+C leaves at any time.
# It runs on the alternate screen, so the terminal comes back as it was.
$global:MatrixQuotes = @(
    'There is no spoon.', 'Free your mind.', 'I know kung fu.', 'Welcome to the real world.',
    "What is real? How do you define 'real'?", 'Welcome to the desert of the real.',
    'There is a difference between knowing the path and walking the path.',
    'Ignorance is bliss.', 'Dodge this.', 'Follow the white rabbit.'
)

function global:Test-MatrixLeaveKey($Key) {
    $Key.Key -eq 'Escape' -or ($Key.Key -eq 'C' -and ($Key.Modifiers -band [ConsoleModifiers]::Control))
}

# Types $Text at the cursor. Any key finishes the line at once; $false for Esc / Ctrl+C.
function global:Write-MatrixTyped([string]$Text, [string]$Color, [int]$MsPerChar = 28) {
    $clock = [Diagnostics.Stopwatch]::StartNew()
    for ($k = 0; $k -lt $Text.Length; $k++) {
        $Host.UI.Write("$Color$($Text[$k])")
        $wait = ($k + 1) * $MsPerChar - $clock.ElapsedMilliseconds
        if ($wait -gt 0 -and (Wait-MatrixKey $wait)) {
            if (Test-MatrixLeaveKey ([Console]::ReadKey($true))) { return $false }
            $Host.UI.Write("$Color$($Text.Substring($k + 1))")
            return $true
        }
    }
    $true
}

# Waits up to $Ms; any key ends the wait early. $false for Esc / Ctrl+C.
function global:Wait-MatrixBeat([int]$Ms) {
    if (Wait-MatrixKey $Ms) { return -not (Test-MatrixLeaveKey ([Console]::ReadKey($true))) }
    $true
}

function global:matrix {
    if ([Console]::IsOutputRedirected -or -not $Host.UI.SupportsVirtualTerminal) { 'Wake up...'; return }
    $e = [char]27
    $ui = $Host.UI
    $green = "$e[38;2;0;255;65m"
    $white = "$e[38;2;232;255;238m"
    $dim = "$e[38;2;61;138;80m"
    $quote = $null
    $ctrlC = [Console]::TreatControlCAsInput
    try {
        [Console]::TreatControlCAsInput = $true
        while ([Console]::KeyAvailable) { [void][Console]::ReadKey($true) }
        $ui.Write("$e[?1049h$e[?25l$e[0m$e[2J$e[3;5H")                # alternate screen
        if (-not (Write-MatrixTyped 'This is your last chance. After this, there is no turning back.' $green)) { return }
        $ui.Write("$e[5;5H$e[1;38;2;255;62;91m[R] red pill$e[0m        $e[1;38;2;80;140;255m[B] blue pill$e[0m")
        $choice = $null
        while (-not $choice) {
            $k = [Console]::ReadKey($true)
            if (Test-MatrixLeaveKey $k) { return }
            if ($k.Key -eq 'R') { $choice = 'red' } elseif ($k.Key -eq 'B') { $choice = 'blue' }
        }
        if ($choice -eq 'blue') {
            $ui.Write("$e[7;5H")
            if (Write-MatrixTyped 'The story ends, you wake up in your bed and believe whatever you want to believe.' "$e[38;2;80;140;255m") {
                [void](Wait-MatrixBeat 1600)
            }
            return
        }
        $ui.Write("$e[7;5H")
        if (-not (Write-MatrixTyped "Remember: all I'm offering is the truth. Nothing more." $white)) { return }
        if (-not (Wait-MatrixBeat 900)) { return }
        $ui.Write("$e[0m$e[2J$e[$([Console]::WindowHeight);3H${dim}press any key to wake up$e[0m")
        [void](Show-MatrixRain -UntilKey)
        $quote = $global:MatrixQuotes[$global:MatrixRng.Next($global:MatrixQuotes.Count)]
        $row = [math]::Max(1, [int]([Console]::WindowHeight / 2))
        $col = [math]::Max(1, [int](([Console]::WindowWidth - $quote.Length) / 2))
        $ui.Write("$e[0m$e[2J$e[$row;${col}H")
        if (Write-MatrixTyped $quote $green 45) { [void](Wait-MatrixBeat 1500) }
    } finally {
        while ([Console]::KeyAvailable) { [void][Console]::ReadKey($true) }
        [Console]::TreatControlCAsInput = $ctrlC
        $ui.Write("$e[0m$e[2J$e[?1049l$e[?25h")                           # back to the normal screen
        if ($quote) { $ui.WriteLine("$dim$quote$e[0m") }
    }
}
