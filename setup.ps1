#requires -Version 5.1
<#
.SYNOPSIS
  Matrix Minimal 安装（通常由 install.ps1 调用；Windows PowerShell 5.1 和 PowerShell 7 都能运行）

.DESCRIPTION
  改动之前都会备份成 *.matrix-bak-<时间>，并把原来的值记进 ~\.config\omp\matrix-minimal.state.json，
  uninstall.ps1 据此原样恢复。
    1. 没有 oh-my-posh（或版本太旧）时，下载官方独立版（校验哈希和签名）到
       %LOCALAPPDATA%\Programs\oh-my-posh\bin，并加进用户 PATH
    2. 主题文件复制到 ~\.config\omp，写入你的名字，按你的屏幕生成代码雨背景图
    3. PowerShell 7 和 Windows PowerShell 的 profile 各加两行加载主题；
       执行策略是 Restricted 时改成 RemoteSigned（仅当前用户），否则 profile 根本不会运行
    4. Windows Terminal：加入 Matrix Minimal 配色；只有 PowerShell 的配置换上配色、雨幕背景和磷光效果

.PARAMETER Name
  提示符和开场白（Wake up, <名字>...）里的名字。不给就询问，直接回车用上次安装的名字或 Windows 用户名。

.PARAMETER Root
  测试用：把所有改动写到这个文件夹里（模拟用户目录、文档、LOCALAPPDATA），不碰注册表。
#>
[CmdletBinding()]
param(
    [string]$Name = $env:MATRIX_NAME,
    [string]$Root = $env:MATRIX_ROOT,
    [switch]$SkipOhMyPosh,
    [switch]$SkipTerminal
)

$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSEdition -ne 'Core') {
    # Windows PowerShell started from PowerShell 7 inherits a module path that finds the 7.x
    # modules first and then fails to load them; use its own default path in this process.
    $env:PSModulePath = @((Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'WindowsPowerShell\Modules'),
                          (Join-Path $env:ProgramFiles 'WindowsPowerShell\Modules'), (Join-Path $PSHOME 'Modules')) -join ';'
}
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$source = $PSScriptRoot
$sandbox = [bool]$Root
$utf8 = New-Object Text.UTF8Encoding $false
$ompVersion = '29.0.2'              # the oh-my-posh release this theme is tested with
$ompMinimum = [version]'29.0'

function Write-Ok([string]$Text)   { Write-Host "  [ok] $Text" -ForegroundColor Green }
function Write-Note([string]$Text) { Write-Host "  [!!] $Text" -ForegroundColor Yellow }
function Write-Step([string]$Text) { Write-Host ''; Write-Host "  $Text" -ForegroundColor DarkGreen }

function Backup-File([string]$Path) {
    $dest = "$Path.matrix-bak-$stamp"; $n = 1
    while (Test-Path $dest) { $dest = "$Path.matrix-bak-$stamp-$n"; $n++ }
    Copy-Item $Path $dest
}

# PSCustomObject (from ConvertFrom-Json) -> nested hashtables, so the state is easy to update
function ConvertTo-Hash($Value) {
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        $h = [ordered]@{}
        foreach ($p in $Value.PSObject.Properties) { $h[$p.Name] = ConvertTo-Hash $p.Value }
        return $h
    }
    if ($Value -is [array]) { return , @($Value | ForEach-Object { ConvertTo-Hash $_ }) }   # "," keeps 1-item arrays
    $Value
}

# Text with the encoding it was saved in; legacy code pages come back with Encoding = $null
function Read-TextFile([string]$Path) {
    $b = [IO.File]::ReadAllBytes($Path)
    if ($b.Length -ge 2 -and $b[0] -eq 0xFF -and $b[1] -eq 0xFE) {
        return @{ Text = [Text.Encoding]::Unicode.GetString($b, 2, $b.Length - 2); Encoding = New-Object Text.UnicodeEncoding $false, $true }
    }
    $bom = $b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF
    $start = if ($bom) { 3 } else { 0 }
    try {
        $text = (New-Object Text.UTF8Encoding $false, $true).GetString($b, $start, $b.Length - $start)
        return @{ Text = $text; Encoding = New-Object Text.UTF8Encoding $bom }
    } catch {
        return @{ Text = [Text.Encoding]::Default.GetString($b); Encoding = $null }
    }
}

# Windows Terminal allows // and /* */ comments; Windows PowerShell's ConvertFrom-Json does not
function Remove-JsonComments([string]$Text) {
    $sb = New-Object Text.StringBuilder
    $i = 0; $n = $Text.Length; $inString = $false
    while ($i -lt $n) {
        $c = $Text[$i]
        if ($inString) {
            [void]$sb.Append($c)
            if ($c -eq [char]'\' -and $i + 1 -lt $n) { [void]$sb.Append($Text[$i + 1]); $i += 2; continue }
            if ($c -eq [char]'"') { $inString = $false }
            $i++; continue
        }
        if ($c -eq [char]'"') { $inString = $true; [void]$sb.Append($c); $i++; continue }
        if ($c -eq [char]'/' -and $i + 1 -lt $n -and $Text[$i + 1] -eq [char]'/') {
            while ($i -lt $n -and $Text[$i] -ne [char]"`n") { $i++ }
            continue
        }
        if ($c -eq [char]'/' -and $i + 1 -lt $n -and $Text[$i + 1] -eq [char]'*') {
            $i += 2
            while ($i + 1 -lt $n -and -not ($Text[$i] -eq [char]'*' -and $Text[$i + 1] -eq [char]'/')) { $i++ }
            $i += 2; continue
        }
        [void]$sb.Append($c); $i++
    }
    $sb.ToString() -replace ',(\s*[}\]])', '$1'      # trailing commas
}

function Get-UserPath {
    [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment').GetValue('Path', '', 'DoNotExpandEnvironmentNames')
}
function Set-UserPath([string]$Value) {
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
    $key.SetValue('Path', $Value, [Microsoft.Win32.RegistryValueKind]::ExpandString)
    $key.Close()
}

Write-Host ''
Write-Host '  Matrix Minimal' -ForegroundColor Green
Write-Host '  Wake up...' -ForegroundColor DarkGreen

# --- where things go ---------------------------------------------------------
if ($sandbox) {
    $Root = [IO.Path]::GetFullPath($Root)
    $userHome = Join-Path $Root 'home'
    $localAppData = Join-Path $Root 'localappdata'
    $documents = Join-Path $Root 'documents'
    Write-Note "测试模式：所有改动都写到 $Root，不碰注册表"
} else {
    $userHome = $HOME
    $localAppData = $env:LOCALAPPDATA
    $documents = [Environment]::GetFolderPath('MyDocuments')
}
$target = Join-Path $userHome '.config\omp'
$stateFile = Join-Path $target 'matrix-minimal.state.json'
$state = [ordered]@{}
if (Test-Path $stateFile) { $state = ConvertTo-Hash ([IO.File]::ReadAllText($stateFile) | ConvertFrom-Json) }
foreach ($k in 'profiles', 'disabledLines', 'executionPolicy', 'terminal') { if ($null -eq $state[$k]) { $state[$k] = [ordered]@{} } }
$state['version'] = 1

$themeFiles = 'matrix-minimal.omp.json', 'matrix-minimal.ps1', 'MatrixPath.format.ps1xml', 'matrix-terminal.ps1',
              'matrix-phosphor.hlsl', 'matrix-rain-bg.ps1', 'matrix-rain.hlsl', 'uninstall.ps1'
$missing = @($themeFiles + 'windows-terminal.json') | Where-Object { -not (Test-Path (Join-Path $source $_)) }
if ($missing) { throw "缺少文件：$($missing -join ', ')。请把整个文件夹一起下载。" }

# --- 1. oh-my-posh -------------------------------------------------------------
Write-Step '1/4  oh-my-posh'
$omp = Get-Command oh-my-posh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
$ompHave = $null
if ($omp) { try { $ompHave = [version](((& $omp.Source version) | Out-String).Trim()) } catch { } }
if ($SkipOhMyPosh) {
    Write-Note '按要求跳过'
} elseif ($ompHave -and $ompHave -ge $ompMinimum) {
    Write-Ok "已有 oh-my-posh $ompHave（$($omp.Source)）"
} else {
    if ($ompHave) { Write-Note "现有 oh-my-posh $ompHave 太旧，另外安装 $ompVersion" }
    $arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64' -or $env:PROCESSOR_ARCHITEW6432 -eq 'ARM64') { 'arm64' } else { 'amd64' }
    $base = "https://github.com/JanDeDobbeleer/oh-my-posh/releases/download/v$ompVersion"
    $bin = Join-Path $localAppData 'Programs\oh-my-posh\bin'
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('matrix-omp-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $tmp | Out-Null
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $exe = Join-Path $tmp "posh-windows-$arch.exe"
        $sums = Join-Path $tmp 'checksums.txt'
        Write-Host "  下载 oh-my-posh $ompVersion（$arch，约 20 MB）..."
        Invoke-WebRequest "$base/posh-windows-$arch.exe" -OutFile $exe -UseBasicParsing
        Invoke-WebRequest "$base/checksums.txt" -OutFile $sums -UseBasicParsing
        $expected = (Get-Content $sums | Where-Object { $_ -match "posh-windows-$arch\.exe\s*$" } | Select-Object -First 1) -replace '\s.*$', ''
        $sha = [Security.Cryptography.SHA256]::Create()
        $stream = [IO.File]::OpenRead($exe)
        try { $actual = -join ($sha.ComputeHash($stream) | ForEach-Object { $_.ToString('x2') }) } finally { $stream.Dispose() }
        if (-not $expected -or $actual -ne $expected.ToLower()) { throw "oh-my-posh 下载校验失败（SHA256 对不上），已停止安装" }
        $sig = Get-AuthenticodeSignature $exe
        if ($sig.Status -ne 'Valid') { throw "oh-my-posh 的数字签名无效（$($sig.Status)），已停止安装" }
        New-Item -ItemType Directory -Force -Path $bin | Out-Null
        Copy-Item $exe (Join-Path $bin 'oh-my-posh.exe') -Force
    } finally {
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
    $state['ohMyPosh'] = [ordered]@{ dir = $bin }
    Write-Ok "oh-my-posh $ompVersion -> $bin（SHA256 和签名已校验）"
    if ($sandbox) {
        Write-Note "测试模式：没有改 PATH（实际安装会把 $bin 加到用户 PATH 最前面）"
    } else {
        $path = Get-UserPath
        $parts = @($path -split ';' | Where-Object { $_ })
        if ($parts -notcontains $bin) {
            Set-UserPath ((@($bin) + $parts) -join ';')
            $state['ohMyPosh']['pathAdded'] = $true
            Write-Ok '已加进用户 PATH'
        }
    }
    $env:Path = "$bin;$env:Path"
}

# --- 2. theme files --------------------------------------------------------------
Write-Step '2/4  主题文件'
New-Item -ItemType Directory -Force -Path $target | Out-Null
$configPath = Join-Path $target 'matrix-minimal.omp.json'
$previousName = $null
if (Test-Path $configPath) { try { $previousName = ([IO.File]::ReadAllText($configPath) | ConvertFrom-Json).var.Name } catch { } }
foreach ($f in $themeFiles) {
    $from = Join-Path $source $f
    $to = Join-Path $target $f
    if ([IO.Path]::GetFullPath($from) -eq [IO.Path]::GetFullPath($to)) { continue }
    if ((Test-Path $to) -and ([IO.File]::ReadAllText($to) -ne [IO.File]::ReadAllText($from)) -and $f -ne 'matrix-minimal.omp.json') { Backup-File $to }
    Copy-Item $from $to -Force
    Unblock-File $to -ErrorAction SilentlyContinue
}
$state['files'] = @($themeFiles + 'matrix-rain-bg.png')
Write-Ok "复制到 $target"

if (-not $Name) {
    $default = if ($previousName) { $previousName } else { $env:USERNAME }
    $interactive = [Environment]::UserInteractive -and -not [Console]::IsInputRedirected
    if ($interactive) {
        $answer = Read-Host "  你的名字（显示在提示符和开场白 Wake up, ... 里；直接回车用 $default）"
        $Name = if ($answer -and $answer.Trim()) { $answer.Trim() } else { $default }
    } else {
        $Name = $default
    }
}
$json = [IO.File]::ReadAllText($configPath)
$literal = (ConvertTo-Json $Name).Replace('$', '$$')
$json = ([regex]'"Name"\s*:\s*"(?:[^"\\]|\\.)*"').Replace($json, '"Name": ' + $literal, 1)
[IO.File]::WriteAllText($configPath, $json, $utf8)
Write-Ok "名字：$Name（以后可以改 $configPath 里的 var.Name）"

& (Join-Path $target 'matrix-rain-bg.ps1') -OutFile (Join-Path $target 'matrix-rain-bg.png') | ForEach-Object { Write-Ok $_ }
$screen = [MatrixRain]::PrimaryWorkArea()
$stretch = if ($screen[2] -eq 96) { 'none' } else { 'uniformToFill' }   # see matrix-rain-bg.ps1

# --- 3. PowerShell profiles ----------------------------------------------------
Write-Step '3/4  PowerShell profile'
$loaders = [ordered]@{
    'matrix-minimal.ps1'  = ". (Join-Path `$HOME '.config/omp/matrix-minimal.ps1')"
    'matrix-terminal.ps1' = ". (Join-Path `$HOME '.config/omp/matrix-terminal.ps1')"
}
$header = '# Matrix Minimal (https://github.com/202030481266/matrix-minimal)'
$hasPwsh = [bool](Get-Command pwsh -CommandType Application -ErrorAction SilentlyContinue)
$shells = @(
    [ordered]@{ Shell = 'Windows PowerShell'; Path = Join-Path $documents 'WindowsPowerShell\Microsoft.PowerShell_profile.ps1' }
)
if ($hasPwsh -or $PSVersionTable.PSEdition -eq 'Core') {
    $shells += [ordered]@{ Shell = 'PowerShell 7'; Path = Join-Path $documents 'PowerShell\Microsoft.PowerShell_profile.ps1' }
}
$oldInit = '^(?!\s*#).*(oh-my-posh(\.exe)?\s+init|MatrixPath\.format\.ps1xml)'

foreach ($s in $shells) {
    $p = $s.Path
    if (Test-Path $p) {
        $file = Read-TextFile $p
    } else {
        $file = @{ Text = ''; Encoding = New-Object Text.UTF8Encoding $true }
        New-Item -ItemType Directory -Force -Path (Split-Path $p) | Out-Null
        $state['profiles'][$p] = 'created'
    }
    $nl = if ($file.Text.Contains("`r`n") -or -not $file.Text) { "`r`n" } else { "`n" }
    $lines = New-Object Collections.Generic.List[string]
    if ($file.Text) { foreach ($l in ($file.Text -split "\r?\n")) { $lines.Add($l) } }

    $add = @($loaders.Keys | Where-Object { $loaderFile = $_; -not ($lines | Where-Object { $_ -notmatch '^\s*#' -and $_.Contains($loaderFile) }) })
    $disabled = @()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match $oldInit -and $lines[$i] -notmatch 'matrix-minimal|matrix-terminal') {
            $disabled += $lines[$i].Trim()
            $lines[$i] = "# [matrix-minimal] $($lines[$i])"
        }
    }
    if (-not $add -and -not $disabled) { Write-Ok "$($s.Shell)：已经在加载主题"; continue }
    if ($null -eq $file.Encoding) {
        Write-Note "$p 的编码不是 UTF-8，没有修改。请手动在末尾加上："
        foreach ($k in $loaders.Keys) { Write-Host "      $($loaders[$k])" }
        continue
    }
    if (Test-Path $p) { Backup-File $p }
    if (-not $state['profiles'][$p]) { $state['profiles'][$p] = 'modified' }
    if ($disabled) { $state['disabledLines'][$p] = @(@($state['disabledLines'][$p]) + $disabled | Where-Object { $_ } | Select-Object -Unique) }
    if ($add) {
        while ($lines.Count -gt 0 -and $lines[$lines.Count - 1].Trim() -eq '') { $lines.RemoveAt($lines.Count - 1) }
        if ($lines.Count -gt 0) { $lines.Add('') }
        $lines.Add($header)
        foreach ($k in $add) { $lines.Add($loaders[$k]) }
        $lines.Add('')
    }
    [IO.File]::WriteAllText($p, ($lines -join $nl), $file.Encoding)
    foreach ($d in $disabled) { Write-Note "$($s.Shell)：停用了原来的一行：$d" }
    Write-Ok "$($s.Shell)：$p"
}

# The profile is a script: with the "Restricted" policy it would never run.
function Get-PolicyFromRegistry([string]$Path) {
    $v = (Get-ItemProperty -Path $Path -Name ExecutionPolicy -ErrorAction SilentlyContinue).ExecutionPolicy
    if ($v) { $v } else { $null }
}
$ps5Key = 'HKCU:\Software\Microsoft\PowerShell\1\ShellIds\Microsoft.PowerShell'
$ps5Effective = @(
    (Get-PolicyFromRegistry 'HKLM:\Software\Policies\Microsoft\Windows\PowerShell'),
    (Get-PolicyFromRegistry 'HKCU:\Software\Policies\Microsoft\Windows\PowerShell'),
    (Get-PolicyFromRegistry $ps5Key),
    (Get-PolicyFromRegistry 'HKLM:\Software\Microsoft\PowerShell\1\ShellIds\Microsoft.PowerShell')
) | Where-Object { $_ } | Select-Object -First 1
if (-not $ps5Effective) { $ps5Effective = 'Restricted' }
if ($ps5Effective -in 'Restricted', 'AllSigned') {
    $gpo = (Get-PolicyFromRegistry 'HKLM:\Software\Policies\Microsoft\Windows\PowerShell') -or (Get-PolicyFromRegistry 'HKCU:\Software\Policies\Microsoft\Windows\PowerShell')
    if ($gpo) {
        Write-Note "Windows PowerShell 的执行策略是 $ps5Effective（组策略设定，改不了），profile 不会运行"
    } elseif ($sandbox) {
        Write-Note "测试模式：Windows PowerShell 执行策略是 $ps5Effective，实际安装会改成 RemoteSigned（仅当前用户）"
    } else {
        if (-not $state['executionPolicy'].Contains('Windows PowerShell')) {
            $previous = Get-PolicyFromRegistry $ps5Key
            $state['executionPolicy']['Windows PowerShell'] = if ($previous) { $previous } else { '' }
        }
        if (-not (Test-Path $ps5Key)) { New-Item -Path $ps5Key -Force | Out-Null }
        Set-ItemProperty -Path $ps5Key -Name ExecutionPolicy -Value 'RemoteSigned'
        Write-Ok "Windows PowerShell 执行策略：$ps5Effective -> RemoteSigned（仅当前用户，否则 profile 不会运行）"
    }
}
if ($hasPwsh -and -not $sandbox) {
    $pwshPolicy = (& pwsh -NoProfile -NonInteractive -Command 'Get-ExecutionPolicy' | Out-String).Trim()
    if ($pwshPolicy -in 'Restricted', 'AllSigned') {
        & pwsh -NoProfile -NonInteractive -Command 'Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force' 2>$null
        if (-not $state['executionPolicy'].Contains('PowerShell 7')) { $state['executionPolicy']['PowerShell 7'] = $pwshPolicy }
        Write-Ok "PowerShell 7 执行策略：$pwshPolicy -> RemoteSigned（仅当前用户）"
    }
}

# --- 4. Windows Terminal -------------------------------------------------------
Write-Step '4/4  Windows Terminal'
if ($SkipTerminal) {
    Write-Note '按要求跳过'
} else {
    $wt = [IO.File]::ReadAllText((Join-Path $source 'windows-terminal.json')) | ConvertFrom-Json
    $scheme = $wt.schemes[0]
    $look = [ordered]@{}
    foreach ($p in $wt.powershellProfiles.PSObject.Properties) { $look[$p.Name] = $p.Value }
    $look['backgroundImageStretchMode'] = $stretch
    if ($sandbox) {
        $look['backgroundImage'] = Join-Path $target 'matrix-rain-bg.png'
        $look['experimental.pixelShaderPath'] = Join-Path $target 'matrix-phosphor.hlsl'
    }
    $settingsFiles = @(
        (Join-Path $localAppData 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'),
        (Join-Path $localAppData 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json'),
        (Join-Path $localAppData 'Microsoft\Windows Terminal\settings.json')
    ) | Where-Object { Test-Path $_ }
    if (-not $settingsFiles) {
        Write-Note '没找到 Windows Terminal 的设置文件。没装 Windows Terminal 的话提示符照样能用，只是没有配色和雨幕；'
        Write-Note '装好之后（Microsoft Store 搜 Windows Terminal）打开一次，再运行一遍安装'
    }
    foreach ($path in $settingsFiles) {
        $raw = [IO.File]::ReadAllText($path)
        try { $s = $raw | ConvertFrom-Json } catch {
            try { $s = (Remove-JsonComments $raw) | ConvertFrom-Json } catch {
                Write-Note "读不了 $path（$($_.Exception.Message)），这个文件没改"
                continue
            }
        }
        $list = if ($s.profiles -is [array]) { @($s.profiles) } else { @($s.profiles.list) }
        $record = $state['terminal'][$path]
        if ($null -eq $record) { $record = [ordered]@{}; $state['terminal'][$path] = $record }
        if (-not $record.Contains('schemeExisted')) { $record['schemeExisted'] = [bool](@($s.schemes) | Where-Object { $_ -and $_.name -eq $scheme.name }) }
        if (-not $record.Contains('profiles')) { $record['profiles'] = [ordered]@{} }

        $schemes = @(@($s.schemes) | Where-Object { $_ -and $_.name -ne $scheme.name }) + $scheme
        if ($s.PSObject.Properties['schemes']) { $s.PSObject.Properties['schemes'].Value = $schemes }
        else { $s | Add-Member -NotePropertyName schemes -NotePropertyValue $schemes }
        $names = @()
        foreach ($pr in $list) {
            if ("$($pr.name) $($pr.source) $($pr.commandline)" -notmatch 'PowerShell|pwsh') { continue }
            $id = if ($pr.guid) { $pr.guid } else { $pr.name }
            if (-not $record['profiles'].Contains($id)) {
                $before = [ordered]@{}
                foreach ($k in $look.Keys) { $before[$k] = if ($pr.PSObject.Properties[$k]) { $pr.$k } else { '<absent>' } }
                $record['profiles'][$id] = $before
            }
            foreach ($k in $look.Keys) {      # change existing keys in place, so the file keeps its order
                if ($pr.PSObject.Properties[$k]) { $pr.PSObject.Properties[$k].Value = $look[$k] }
                else { $pr | Add-Member -NotePropertyName $k -NotePropertyValue $look[$k] }
            }
            $names += "$($pr.name)"
        }
        if (-not $names) { Write-Note "$path 里没有 PowerShell 配置，只加入了配色"; }
        Backup-File $path
        [IO.File]::WriteAllText($path, ($s | ConvertTo-Json -Depth 64), $utf8)
        Write-Ok "配色、雨幕和磷光效果 -> $(($names | Select-Object -Unique) -join '、')"
        Write-Ok "背景图拉伸方式：$stretch（显示缩放 $([math]::Round($screen[2] / 96 * 100))%）"
    }
}

[IO.File]::WriteAllText($stateFile, (ConvertTo-Json $state -Depth 10), $utf8)

Write-Host ''
Write-Host '  完成。Welcome to the desert of the real.' -ForegroundColor Green
Write-Host '  - 关掉所有 PowerShell 窗口，重新打开（新 PATH 和 profile 才会生效）'
Write-Host '  - 每天第一个窗口会播开场；随时运行 Show-MatrixIntro 重播'
Write-Host "  - 卸载：powershell -ExecutionPolicy Bypass -File `"$(Join-Path $target 'uninstall.ps1')`""
Write-Host ''
