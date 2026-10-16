# CLAUDE.md：Matrix Minimal 开发交接

黑客帝国风格的 PowerShell + Windows Terminal 主题，基于 Oh My Posh。作者是 shulin，GitHub 账号有两个：202030481266（仓库所有者）和 criscuolosubidu（协作者，也是 `theme`/posh-theme 脚本的作者账号）。和用户交流用中文，README 和面向用户的提示也是中文；代码注释用英文。

## 文件

| 文件 | 作用 |
|---|---|
| `install.ps1` | `irm .../install.ps1 \| iex` 的入口。**必须是纯 ASCII、无 BOM**（`iex` 不认 BOM；没有 BOM 时 PS5 又会把中文按 GBK 读坏）。它会下载仓库 zip，再用当前版本的 PowerShell 运行 `setup.ps1`。变量统一用 `$mm` 前缀，避免污染用户的会话 |
| `setup.ps1` | 真正的安装脚本（带 BOM，兼容 PS5 和 PS7）。参数：`-Name`、`-Root`（沙盒测试）、`-SkipOhMyPosh`、`-SkipTerminal`。分 4 步：oh-my-posh → 主题文件 → profile → Windows Terminal。所有改动先备份（`*.matrix-bak-<时间>`），原值记到 `~\.config\omp\matrix-minimal.state.json` |
| `uninstall.ps1` | 按 state 文件恢复原样 |
| `matrix-minimal.omp.json` | Oh My Posh 配置（schema v4，仓库里 `var.Name` 为空，安装时填入） |
| `matrix-minimal.ps1` | 提示符初始化，以及所有动效：开场、pwd 解码、失败闪烁、`matrix` 彩蛋；还有自检 `Test-MatrixMinimal` |
| `matrix-terminal.ps1` | 只在 Windows Terminal 里生效：PowerShell 自己的输出颜色（PS7 用 `$PSStyle`，PS5 用 `$Host.PrivateData`，只替换默认值）、claude/codex 等程序运行时恢复原生配色（OSC 4/10/11/12，结束后用 104/110/111/112 复位），以及 `rain` 命令（新开一个用 "Matrix Rain" 配置的标签页，见下文） |
| `matrix-phosphor.hlsl` | 默认的像素着色器：文字微光 + 扫描线。**不用 `Time`**，所以只在画面变化时运行 |
| `matrix-rain.hlsl` | 会动的代码雨（用 `Time`，WT 会以 60fps 持续重绘），只用在 "Matrix Rain" 配置上 |
| `matrix-rain-bg.ps1` | 生成静态雨幕背景图 `matrix-rain-bg.png`，按屏幕尺寸生成 |
| `windows-terminal.json` | 配色方案（见下文"输出配色"），以及要写进 PowerShell 配置的外观设置 |

安装位置：`~\.config\omp\`。profile 里加两行：`. (Join-Path $HOME '.config/omp/matrix-minimal.ps1')` 和 `matrix-terminal.ps1`，上面有一行注释头 `# Matrix Minimal (https://...)`。

## 开发流程

改完仓库里的文件后，在仓库目录运行 `powershell -ExecutionPolicy Bypass -File .\install.ps1` 重新安装，新开标签页，再运行 `Test-MatrixMinimal`。
沙盒测试：`setup.ps1 -Root <临时目录>`，加 `uninstall.ps1 -Root` 配对使用，不会碰真实系统。PS5 和 PS7 都要测。

## 踩过的坑（别再踩）

- **编码**：含中文的 `.ps1` 必须带 UTF-8 BOM，否则 PS5 按 GBK 读。PS5 的 `Get-Content` 默认按 ANSI 读，改用 `[IO.File]::ReadAllText`。片假名输出要用 `$Host.UI.Write`，`[Console]::Out` 在 GBK 代码页下会变成 `?`。
- PS5 中 `pwd` 是 AllScope 别名，覆盖时要 `Set-Alias -Option AllScope`。
- 函数返回单元素数组会被展开，要写成 `return , @()`。`Add-Member -Force` 会把属性挪到对象末尾，所以 settings.json 要原地改值。PowerShell 变量名不区分大小写（`$name` 会覆盖参数 `$Name`）。
- 从 pwsh 启动 PS5 时会继承 `PSModulePath`，导致模块自动加载失败，setup 里先把它清理干净。
- `Get-Command` 查不存在的命令很慢（会扫描所有模块），判断程序是否已安装改用 PATH + `File.Exists`。
- oh-my-posh：用 `extends` 继承配置时会丢掉 `final_space`；继承的 `POSH_SESSION_ID` 会缓存配置，导致 `--config` 不生效；`transient_prompt` 每次回车多启动一个进程（已删除）。MSIX 版每次启动多约 130ms，所以 setup 下载的是官方独立 exe（v29.0.2，校验 SHA256 和签名），放到 `%LOCALAPPDATA%\Programs\oh-my-posh\bin`。写入用户 PATH 后用 `[Environment]::SetEnvironmentVariable(..., 'User')` 广播 WM_SETTINGCHANGE；`matrix-minimal.ps1` 里还会兜底把这个目录加进 `$env:Path`。
- **posh-theme（用户的 `theme` 工具）**：如果它已加载，主题会注册进它的 `$PoshThemes`，使用存根 `~\.posh-themes\matrix-minimal.omp.json`（`{"extends": ..., "final_space": true}`），并且只在 `~\.posh-theme` 为 `matrix-minimal` 时调用 `Initialize-PoshTheme`，不自己运行 `oh-my-posh init`。posh-theme 会接管 `Set-PoshContext`；有 `$PoshThemeVersion` 时由它设置标签页标题。
- 开场动画由第一次 `prompt` 触发，`PSConsoleHostReadLine` 的包装里有兜底；钩子被别的东西替换时会重新包装，出错信息存进 `$global:MatrixHookError`。`$MatrixFx.Intro` 默认是 `'always'`（**用户明确要求每开一个标签页播放一次**），也可设为 `daily`、`off`。
- **Windows Terminal**：settings.json 会热加载。着色器和背景图按配置（profile）生效，**不能按标签页设置**，也没有 VT 序列能改。设了背景图时，背景本身是透明的，着色器拿到的纹理是预乘 alpha（`matrix-rain.hlsl` 已按这个处理）。着色器不覆盖 padding 区域，所以 phosphor 的 VIGNETTE 默认为 0（否则边缘会出现接缝）。setup 只修改 name/source/commandline 匹配 `PowerShell|pwsh` 的配置，并跳过 Matrix Rain 的 GUID。
- 端到端测试：用 `wt -w mmtest nt -p <guid>` 开一个单独的窗口，别动用户正在用的窗口。标签页里 shell 的父进程是 WindowsTerminal.exe，据此找到 PID，`AttachConsole` + `WriteConsoleInput` 注入按键（`-` 键是 VK 0xBD，不是 0x2D；开场动画会吞掉第一个键，先确认 shell 已经能执行命令），用 `PrintWindow(PW_RENDERFULLCONTENT)` 截图对比。GPU 用 `Get-Counter '\GPU Engine(pid_<WT pid>_*)\Utilization Percentage'`（这台机子的计数器名是英文）。`*>` 重定向在 PS5 写 UTF-16、在 PS7 写 UTF-8，用 `[IO.File]::ReadAllText` 读。**判断颜色要对截图做像素采样**，看缩略图会看走眼（曾经把 `#00FF41` 看成淡色）。预览配色可以在标签页里用 OSC 4/10 临时换调色板（结果是准的），也可以把配色写进 `%LOCALAPPDATA%\Microsoft\Windows Terminal\Fragments\<名字>\*.json`，然后用 `wt nt --colorScheme <名字>` 打开。管道会让 git 关掉颜色，要加 `-c color.ui=always`。`-File` 必须传绝对路径。不要调用 `python3`（Windows 应用商店的占位程序会卡住）。

## README 的演示图

`docs/demo.gif` 是 2026-10-16 重录的（38 秒，2.3 MB；名字 shulin，在临时仓库 `D:\项目\zion` 里录）：开场 → `pwd` → `git status -s` → `git diff` → 敲错 `matirx` 触发闪烁 → `matrix`（菜单、按 `r`、全屏代码雨、按空格醒来、台词）→ `rain`（切到 Matrix Rain 标签页，录约 2.5 秒动态雨后结束，接着循环）。`docs/screenshot.png` 是敲错命令后闪烁结束的那一帧（能看到 git 的配色）。两段整屏的雨占了 GIF 的大部分体积；改用 128 色只小 8%，所以保留 256 色。录制方法：
- 打开一个单独的 WT 窗口：`wt -w mmrec --size 100,29 nt -p <pwsh guid> -d <仓库> pwsh.exe -NoLogo`（加 `-NoLogo` 去掉版本横幅）。用一个后台线程每 50 ms 调一次 `PrintWindow` 存 PNG，用 `WriteConsoleInput` 逐字"打字"。名字是临时改 `var.Name` 实现的，录完要按原字节写回去。
- 这台机子开标签页后约 4 秒才开始放开场。**开场里按任何键都会跳过开场，而且这个键会被吞掉**，所以要等开场完全结束再输入。
- 剪辑：裁掉标签栏和边框（终端区域从 x=8、y=41 开始，宽 1116）；从第一行开场文字出现前几帧开始；相同的帧合并；光标闪烁（A、B、A 这种只差光标的循环）合并成一帧；每次停顿最长 2.2 秒。结尾是动态雨，所以裁掉最后 1.2 秒，最后一帧只停 80 ms，接着从头循环。然后用 ffmpeg 的 concat 列表带上每帧时长，`palettegen` / `paletteuse=dither=none:diff_mode=rectangle` 生成 GIF（约 500 KB）。
- PS7.4 以后，敲错命令会出现 `[General Feedback]` 提示（"最相似的命令是 matrix"），这是 PowerShell 自带的，录进去了。

## 用户的偏好

- **不要处理 profile 加载慢的问题**：用户说那台机子本来就慢，不是这个主题造成的，他自己解决。
- 动效要克制，不能影响性能（因此放弃了常驻的动态雨，改成静态雨幕 + 磷光）。
- 不能污染别的程序的配色（claude、codex 保留原生主题）。
- 动手大改之前先说方案。**提交和推送不用再问**（2026-10-17 用户明确授权，限本项目）。

## 输出配色（2026-10-16，用户在 A/B/C/D 四个候选里选了 A）

以前 16 色几乎全是绿的，前景色 `#00FF41` 和 green `#00C832` 也几乎一样，git diff 的新增行和没改的行分不清。现在的分工是：提示符、输入高亮、雨幕和开场用自己的 RGB 矩阵绿（不受配色影响）；命令输出的正文用淡磷光色 `#B4F1C4`，16 色各有含义：red `#FF3E5B` 红药丸（删除、错误），green `#00E03C` / 亮 `#00FF41`（新增、成功、表头），yellow `#FFB000` 琥珀磷光（警告、commit 号），blue `#508CFF` 蓝药丸，purple `#C38BFF`，cyan `#2EE6D6`（`@@`、HEAD、详细信息）。所有颜色和背景的对比度至少 4.1（brightBlack `#4F7A5A`），正文 15.9。

- 不改用户的 `.gitconfig`：调色板对了，git 的默认颜色就都对了。
- PS7：Verbose 用青色、Debug 用紫色（默认和警告一样是黄色），图片和音视频用紫色，再补几种压缩包用红色；只在值还是 PowerShell 默认值时才改，所以用户在 `$PROFILE` 里先设的值会保留。PS5：`$Host.PrivateData` 里 Verbose 设成 DarkCyan、Debug 设成 DarkMagenta（对应配色里的 cyan 和 purple）；进度条默认是黄字配 DarkCyan 底，在这套配色下变成琥珀字配青色底，对比度只有 1.04，所以字改成 Black（截图确认过能看清）。PS7 的进度条是黑字配琥珀底，本来就清楚。
- **目录颜色保持薄荷绿 `#7DFFB8` 加粗**：用户说先看看效果，暂时不改成蓝色。

## `rain`：单独一个标签页下雨

着色器只能按配置设置，所以 `rain` 用一个专门的 WT 配置 "Matrix Rain"（固定 GUID `{4d415452-4958-5241-494e-6d696e696d61}`，即 "MATRIXRAINminima"）：commandline 是 `pwsh.exe -NoLogo` 或 PS5 的完整路径，Matrix Minimal 配色，`matrix-rain.hlsl`，**不设背景图**，字体从 `profiles.defaults` 继承。

- 第一次运行 `rain` 时，把这个配置**以文本方式**插到 `profiles.list` 末尾，用正则分词器数括号（`Get-ProfileList`，兼容注释、尾逗号、旧版 `"profiles": [...]`），缩进照抄第一个配置，保留 BOM 和换行符。然后运行 `wt -w 0 nt -p <guid> -d <当前目录，; 转义成 \;> <当前 shell> -NoLogo`。
- 在雨的标签页里（`$env:WT_PROFILE_ID` 等于这个 GUID）运行 `rain` 只给提示。`rain off` 也只给提示，另外兼容旧版（ddfb813）：只把含有 `matrix-rain-clear.png` 且不是 Matrix Rain 的配置换回来。
- setup 跳过这个 GUID；uninstall 删除这个配置，而且在 `$inUse` 判断**之前**删（它也用 Matrix Minimal 配色）。
- 实测（2026-10-16，这台机子）：
  - 插入配置后立即 `wt -p <guid>`，WT 会**静默**换成别的配置打开（按 commandline 匹配到了 Windows PowerShell）；等 100 ms 就够了，代码里等 1 秒。
  - 在标签页里运行时，`-w 0` 指向这个标签页所在的窗口。WT 重建命令行时会给带空格的参数加引号（Program Files 下的 pwsh 7.6.0 正常）。`-d` 里用 `\;` 可以。
  - Store 版 pwsh 的 `$PSHOME` 在 WindowsApps 下，所以新标签页改用 `pwsh.exe`（走应用执行别名）启动。
  - 负载（RTX 4090，窗口 2560×1392；WT 进程，CPU 按一个核算）：只有静态标签页时 GPU 0.2%、CPU 0.3%；雨的标签页在前台时 GPU 0.7%、CPU 2.2%；**切到别的标签页**时 GPU 0.4%、CPU 2.5%；**最小化**时 GPU 0.6%、CPU 3.4%；关掉标签页后回落。所以切走或最小化都不会停，只能关掉标签页。提示语和 README 里已经这么写了。

## 其他未完成的事

- 朋友的机子当初"没有开场动画"的确切原因没有复现出来，修复针对的是可能的原因。如果还有问题，让他重新运行安装并发 `Test-MatrixMinimal` 的输出。
- 朋友在运行 `irm | iex` 的同一个窗口里输入 `rain`，报"找不到命令"：那个窗口加载的还是旧版 profile，新开标签页就好。提议过在 `install.ps1` 结尾（仅 iex 安装时）当场重新加载 `matrix-terminal.ps1`，并把结尾提示改成"新命令要在新标签页里用"，用户还没决定。
- PS5 下的失败闪烁效果还没有目测确认过。
- 仓库没有 LICENSE（提过，用户还没要求）。
