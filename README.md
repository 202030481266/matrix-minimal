# Matrix Minimal

> Wake up, Neo... The Matrix has you.

给 PowerShell + Windows Terminal 做的黑客帝国主题，基于 [Oh My Posh](https://ohmyposh.dev)。

![演示：开场、pwd 解码、命令失败时的故障闪烁](docs/demo.gif)

## 有什么

- **极简提示符**：名字、git 分支（`*` 有未提交的改动，`+N` / `-N` 领先 / 落后远端）、失败时的退出码、`>`（管理员窗口是 `#`）。命令运行超过 2 秒时，右边才显示耗时。
- **雨幕背景**：一帧静态的片假名代码雨，右边密、越往左越淡，底部也会变淡，不挡你的命令。安装时按你的屏幕生成，不占 GPU。
- **磷光屏**：文字带一点荧光微光，外加细扫描线。像素着色器只在画面变化时运行，平时不耗资源。
- **开场**：每天第一个窗口会先打出 "Wake up, 你的名字..."，接着下一阵代码雨，最后停在 "Welcome to the desert of the real."。按任意键跳过，随时运行 `Show-MatrixIntro` 重播。
- **pwd 解码**：单独输入 `pwd` 时，路径先是一串乱跳的片假名，再逐字解码成真实路径，以高亮条显示。
- **故障闪烁**：命令失败后，提示符会红绿错位地抖一下。
- **彩蛋**：输入 `matrix`，墨菲斯会让你选药丸。红色药丸带你进入全屏代码雨，按任意键醒来，并留下一句电影台词；蓝色药丸则让故事到此结束。
- **不污染别的程序**：`ls` 的目录名不再变成绿色色块；运行 `claude`、`codex` 时自动换回它们自己的配色。

![截图](docs/screenshot.png)

## 安装

在 PowerShell 里运行（Windows PowerShell 5.1 和 PowerShell 7 都可以）：

```powershell
irm https://raw.githubusercontent.com/202030481266/matrix-minimal/main/install.ps1 | iex
```

安装时会询问你的名字（显示在提示符和开场白里）。装完后，**关掉所有 PowerShell 窗口重新打开**。

安装脚本会做下面这些事。改动之前都会备份，卸载时按原来的值恢复：

1. 没有 oh-my-posh 时，下载官方独立版到 `%LOCALAPPDATA%\Programs\oh-my-posh\bin`（校验 SHA256 和数字签名），并加进用户 PATH。
2. 把主题文件放到 `~\.config\omp`，按你的屏幕生成背景图。
3. 在 Windows PowerShell 和 PowerShell 7 的 profile 里各加两行加载主题。如果执行策略是 Restricted，会改成 RemoteSigned（仅当前用户），否则 profile 根本不会运行。
4. Windows Terminal：加入 "Matrix Minimal" 配色，只给 PowerShell 的配置换上配色、雨幕背景和磷光效果；cmd、WSL 保持原样。

也可以下载 zip，解压后在文件夹里运行 `powershell -ExecutionPolicy Bypass -File .\install.ps1`。

### 要求

- Windows 10 / 11
- [Windows Terminal](https://aka.ms/terminal)：配色、雨幕和磷光效果都依赖它。没有的话，提示符和动效照样能用。
- 显示缩放为 100% 时背景最清晰；其他缩放比例下，窗口最大化时最清晰。

## 自定义

| 想改什么 | 怎么做 |
|---|---|
| 名字 | 改 `~\.config\omp\matrix-minimal.omp.json` 里的 `var.Name` |
| 关掉某个动效 | 在 `$PROFILE` 里、加载主题的那两行**之前**加上 `$MatrixFx = @{ Intro = 'off'; Decode = $true; Glitch = $true }`。Intro 可选 `daily`（每天一次）、`always`、`off` |
| 雨的疏密、亮度，或者换一种排布 | 改 `~\.config\omp\matrix-rain-bg.ps1` 顶部的 "Tweak me"，运行 `pwsh -File ~\.config\omp\matrix-rain-bg.ps1 -Seed 7`，然后重开标签页 |
| 磷光的强弱 | 改 `~\.config\omp\matrix-phosphor.hlsl` 顶部的参数，保存后立即生效 |
| 想要会动的代码雨 | 在 Windows Terminal 设置里把像素着色器换成 `matrix-rain.hlsl`（会一直占用 GPU） |
| 哪些程序使用自己的配色 | `$MatrixNativeApps = 'claude', 'codex', 'nvim'`（同样放在加载主题之前） |

运行 `Test-MatrixMinimal` 可以自检。

## 卸载

```powershell
powershell -ExecutionPolicy Bypass -File "$HOME\.config\omp\uninstall.ps1"
```

profile 里只会删除安装时加的那几行；Windows Terminal 的设置会恢复成安装前的值；如果 oh-my-posh 是安装时下载的，卸载时会询问是否一并删除。

## 致谢

- [Oh My Posh](https://ohmyposh.dev)
- *The Matrix* (1999)
