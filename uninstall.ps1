#requires -Version 5.1
<#
.SYNOPSIS
  卸载 Matrix Minimal：按安装时记下的原值恢复；profile 里只删安装时加的那几行。

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File "$HOME\.config\omp\uninstall.ps1"

.PARAMETER KeepOhMyPosh
  保留安装时下载的 oh-my-posh（不加这个参数会询问）。

.PARAMETER Root
  测试用：和 setup.ps1 -Root 配对，只处理这个文件夹里的东西。
#>
[CmdletBinding()]
param(
    [string]$Root = $env:MATRIX_ROOT,
    [switch]$KeepOhMyPosh
)

$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSEdition -ne 'Core') {
    # Windows PowerShell started from PowerShell 7 inherits a module path that finds the 7.x
    # modules first and then fails to load them; use its own default path in this process.
    $env:PSModulePath = @((Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'WindowsPowerShell\Modules'),
                          (Join-Path $env:ProgramFiles 'WindowsPowerShell\Modules'), (Join-Path $PSHOME 'Modules')) -join ';'
}
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$sandbox = [bool]$Root
$utf8 = New-Object Text.UTF8Encoding $false

function Write-Ok([string]$Text)   { Write-Host "  [ok] $Text" -ForegroundColor Green }
function Write-Note([string]$Text) { Write-Host "  [!!] $Text" -ForegroundColor Yellow }

function Backup-File([string]$Path) {
    $dest = "$Path.matrix-bak-$stamp"; $n = 1
    while (Test-Path $dest) { $dest = "$Path.matrix-bak-$stamp-$n"; $n++ }
    Copy-Item $Path $dest
}

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
    $sb.ToString() -replace ',(\s*[}\]])', '$1'
}

# value of a property on a PSCustomObject, $null when it is missing
function Get-Prop($Object, [string]$Name) {
    if ($null -eq $Object) { return $null }
    $p = $Object.PSObject.Properties[$Name]
    if ($p) { $p.Value } else { $null }
}

Write-Host ''
Write-Host '  Matrix Minimal: uninstall' -ForegroundColor Green

if ($sandbox) {
    $Root = [IO.Path]::GetFullPath($Root)
    $userHome = Join-Path $Root 'home'
    $localAppData = Join-Path $Root 'localappdata'
    $documents = Join-Path $Root 'documents'
    Write-Note "测试模式：只处理 $Root"
} else {
    $userHome = $HOME
    $localAppData = $env:LOCALAPPDATA
    $documents = [Environment]::GetFolderPath('MyDocuments')
}
$target = Join-Path $userHome '.config\omp'
$stateFile = Join-Path $target 'matrix-minimal.state.json'
$state = $null
if (Test-Path $stateFile) { $state = [IO.File]::ReadAllText($stateFile) | ConvertFrom-Json }
else { Write-Note '没找到安装记录（matrix-minimal.state.json），按默认位置清理' }

# --- profiles ----------------------------------------------------------------------
$header = '# Matrix Minimal (https://github.com/202030481266/matrix-minimal)'
$loaderLines = ". (Join-Path `$HOME '.config/omp/matrix-minimal.ps1')", ". (Join-Path `$HOME '.config/omp/matrix-terminal.ps1')"
$profilePaths = if ($state -and $state.profiles) { @($state.profiles.PSObject.Properties.Name) } else {
    @((Join-Path $documents 'WindowsPowerShell\Microsoft.PowerShell_profile.ps1'),
      (Join-Path $documents 'PowerShell\Microsoft.PowerShell_profile.ps1'))
}
foreach ($p in $profilePaths) {
    if (-not (Test-Path $p)) { continue }
    $file = Read-TextFile $p
    if ($null -eq $file.Encoding) { Write-Note "$p 的编码不是 UTF-8，没有修改，请手动删掉加载 matrix-minimal 的几行"; continue }
    $nl = if ($file.Text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $kept = New-Object Collections.Generic.List[string]
    $changed = $false
    foreach ($l in ($file.Text -split "\r?\n")) {
        $t = $l.Trim()
        if ($t -eq $header -or $loaderLines -contains $t) { $changed = $true; continue }
        if ($l.StartsWith('# [matrix-minimal] ')) { $kept.Add($l.Substring(19)); $changed = $true; continue }
        $kept.Add($l)
    }
    $leftovers = @($kept | Where-Object { $_ -notmatch '^\s*#' -and $_ -match 'matrix-minimal\.ps1|matrix-terminal\.ps1' })
    if ($changed) {
        while ($kept.Count -gt 0 -and $kept[$kept.Count - 1].Trim() -eq '') { $kept.RemoveAt($kept.Count - 1) }
        $created = $state -and (Get-Prop $state.profiles $p) -eq 'created'
        if ($created -and -not ($kept | Where-Object { $_.Trim() })) {
            Remove-Item $p
            Write-Ok "删除了安装时新建的 $p"
        } else {
            Backup-File $p
            [IO.File]::WriteAllText($p, (($kept -join $nl) + $nl), $file.Encoding)
            Write-Ok "profile 已还原：$p"
        }
    }
    foreach ($l in $leftovers) { Write-Note "$p 里还有一行自己写的引用，请手动删掉：$($l.Trim())" }
}

# --- Windows Terminal ------------------------------------------------------------
$terminal = if ($state) { $state.terminal } else { $null }
if ($terminal) {
    foreach ($path in @($terminal.PSObject.Properties.Name)) {
        if (-not (Test-Path $path)) { continue }
        $record = Get-Prop $terminal $path
        $raw = [IO.File]::ReadAllText($path)
        try { $s = $raw | ConvertFrom-Json } catch {
            try { $s = (Remove-JsonComments $raw) | ConvertFrom-Json } catch { Write-Note "读不了 $path，没有修改"; continue }
        }
        $list = if ($s.profiles -is [array]) { @($s.profiles) } else { @($s.profiles.list) }
        $restored = @()
        foreach ($pr in $list) {
            $id = if ($pr.guid) { $pr.guid } else { $pr.name }
            $before = Get-Prop $record.profiles $id
            if (-not $before) { continue }
            foreach ($kv in $before.PSObject.Properties) {
                if ($kv.Value -eq '<absent>') { $pr.PSObject.Properties.Remove($kv.Name) }
                elseif ($pr.PSObject.Properties[$kv.Name]) { $pr.PSObject.Properties[$kv.Name].Value = $kv.Value }
                else { $pr | Add-Member -NotePropertyName $kv.Name -NotePropertyValue $kv.Value }
            }
            $restored += "$($pr.name)"
        }
        $inUse = @($list) + @(Get-Prop $s.profiles 'defaults') | Where-Object { $_ -and (Get-Prop $_ 'colorScheme') -eq 'Matrix Minimal' }
        if (-not $record.schemeExisted -and -not $inUse) {
            if ($s.PSObject.Properties['schemes']) {
                $s.PSObject.Properties['schemes'].Value = @(@($s.schemes) | Where-Object { $_ -and $_.name -ne 'Matrix Minimal' })
            }
        }
        Backup-File $path
        [IO.File]::WriteAllText($path, ($s | ConvertTo-Json -Depth 64), $utf8)
        Write-Ok "Windows Terminal 已还原：$(($restored | Select-Object -Unique) -join '、')"
    }
} else {
    Write-Note 'Windows Terminal：没有安装记录，没有修改。需要的话在设置里把 PowerShell 的配色、背景图、像素着色器改回去'
}

# --- execution policy ------------------------------------------------------------
$policies = if ($state) { $state.executionPolicy } else { $null }
if ($policies -and -not $sandbox) {
    $ps5Previous = Get-Prop $policies 'Windows PowerShell'
    if ($null -ne $ps5Previous) {
        $key = 'HKCU:\Software\Microsoft\PowerShell\1\ShellIds\Microsoft.PowerShell'
        if ((Get-ItemProperty -Path $key -Name ExecutionPolicy -ErrorAction SilentlyContinue).ExecutionPolicy -eq 'RemoteSigned') {
            if ($ps5Previous) { Set-ItemProperty -Path $key -Name ExecutionPolicy -Value $ps5Previous }
            else { Remove-ItemProperty -Path $key -Name ExecutionPolicy -ErrorAction SilentlyContinue }
            Write-Ok "Windows PowerShell 执行策略已还原$(if ($ps5Previous) { "为 $ps5Previous" })"
        }
    }
    if ($null -ne (Get-Prop $policies 'PowerShell 7') -and (Get-Command pwsh -ErrorAction SilentlyContinue)) {
        & pwsh -NoProfile -NonInteractive -Command 'Set-ExecutionPolicy Undefined -Scope CurrentUser -Force' 2>$null
        Write-Ok 'PowerShell 7 执行策略已还原'
    }
}

# --- oh-my-posh (only if the installer downloaded it) -------------------------------
$omp = if ($state) { $state.ohMyPosh } else { $null }
if ($omp -and $omp.dir -and (Test-Path $omp.dir)) {
    $remove = -not $KeepOhMyPosh
    if ($remove -and [Environment]::UserInteractive -and -not [Console]::IsInputRedirected) {
        $answer = Read-Host "  也删掉安装时下载的 oh-my-posh（$($omp.dir)）吗？别的主题还要用就输入 n [Y/n]"
        $remove = $answer -notmatch '^\s*n'
    }
    if ($remove) {
        Remove-Item (Split-Path $omp.dir) -Recurse -Force -ErrorAction SilentlyContinue
        if ($omp.pathAdded -and -not $sandbox) {
            $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
            $path = $key.GetValue('Path', '', 'DoNotExpandEnvironmentNames')
            $key.SetValue('Path', (@($path -split ';' | Where-Object { $_ -and $_ -ne $omp.dir }) -join ';'), [Microsoft.Win32.RegistryValueKind]::ExpandString)
            $key.Close()
        }
        Write-Ok 'oh-my-posh 已删除'
    }
}

# --- files -----------------------------------------------------------------------
$files = if ($state -and $state.files) { @($state.files) } else {
    'matrix-minimal.omp.json', 'matrix-minimal.ps1', 'MatrixPath.format.ps1xml', 'matrix-terminal.ps1',
    'matrix-phosphor.hlsl', 'matrix-rain-bg.ps1', 'matrix-rain.hlsl', 'uninstall.ps1', 'matrix-rain-bg.png'
}
foreach ($f in @($files) + 'matrix-rain-bg.preview.png' + 'matrix-minimal.state.json') {
    Remove-Item (Join-Path $target $f) -Force -ErrorAction SilentlyContinue
}
if ((Test-Path $target) -and -not (Get-ChildItem $target -Force)) { Remove-Item $target }
Remove-Item (Join-Path $localAppData 'matrix-minimal') -Recurse -Force -ErrorAction SilentlyContinue
Write-Ok "主题文件已删除（$target 里的 *.matrix-bak-* 备份保留）"

Write-Host ''
Write-Host '  卸载完成。关掉所有 PowerShell 窗口重新打开即可。' -ForegroundColor Green
Write-Host ''
