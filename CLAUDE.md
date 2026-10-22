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
- 开场动画由第一次 `prompt` 触发，`PSConsoleHostReadLine` 的包装里有兜底；出错信息存进 `$global:MatrixHookError`。`$MatrixFx.Intro` 默认是 `'launch'`（2026-10-18 用户改的：每开一个标签页都播太频繁，**每次启动 Windows Terminal 播一次**，其余新标签页只解码结尾的 DESERT 大字），也可设为 `always`、`daily`（没轮到的标签页同样只显示大字）、`off`。`launch` 的判断：从当前进程往上跳过 pwsh/powershell，找到所在终端的进程（WT、VS Code 的 ptyHost），在 `%LOCALAPPDATA%\matrix-minimal\` 用 `CreateNew` 建 `launch-<pid>-<启动时间 ticks>`，建成功的标签页播完整开场（几个标签页同时恢复时只有一个播）；新终端启动时顺手删掉已退出终端的标记。上面是 explorer（开始菜单打开的独立控制台窗口）或者查不到时，每次都播完整开场。只显示大字时按键**不吞**（用户可能已经开始打字）。PS7 用 `Process.Parent`（约 5 ms）；PS5 没有，用 Reflection.Emit 现做一个 `NtQueryInformationProcess` 的 P/Invoke（约 30 ms），WMI/CIM 要约 0.3 秒，`Add-Type` 会启动 C# 编译器，都不用。
- **钩子会被别人包在外面（VS Code）**：VS Code 的 shell integration（`resources\app\out\vs\workbench\contrib\terminal\common\scripts\shellIntegration.ps1`）在 profile **之后**运行，把当时的 `prompt` 和 `PSConsoleHostReadLine` 存起来再包一层，里面用 `.Invoke()` 调原来的。旧版钩子发现"外面不是我"就重新包装，而且被包的函数存在同一个全局变量里，结果形成 我→VS Code→我（旧）→VS Code… 的死循环：动画播完后终端吃满一个核，打不了字（2026-10-18 修好）。现在：每个包装用 `GetNewClosure()` 各自保存自己包着的函数，不会成环；只有上一轮另一个钩子**没有被调用到**时才重新包装（`$MatrixPromptSeen` / `$MatrixReadLineSeen`；在 read-line 钩子里面画的提示符，比如开场重画、Ctrl+L，不算一轮，用 `$MatrixInReadLine` 区分）；`prompt` 包装调里层之前用 `Write-Error -ErrorAction Ignore` 把 `$?` 还原，VS Code 的成功/失败标记才对。用户的 profile 里 posh-theme 会在本主题之后重新 init oh-my-posh，所以 VS Code 里实际是 `prompt` = 我→VS Code→omp，`PSConsoleHostReadLine` = VS Code→我→PSReadLine。测法：写一个只 dot-source 上面那个 shellIntegration.ps1 的脚本，`wt -w mmtest nt pwsh.exe -NoLogo -NoExit -File <绝对路径>`（PS5 同理），注入按键执行命令；也可以用一个替身 `PSConsoleHostReadLine` 在后台控制台里循环跑 `prompt` + `PSConsoleHostReadLine`（不能重定向输出，否则钩子直接 return）。VS Code 终端里 `TERM_PROGRAM=vscode`，从 WT 启动的 VS Code 会继承 `WT_SESSION`，所以 `matrix-terminal.ps1` 两个都判断。
- 用户的终端尺寸（2026-10-18 实测）：VS Code 80×30，WT 126×36。开场结尾的大字要放得下 80 列、不能太高。
- **Windows Terminal**：settings.json 会热加载。着色器和背景图按配置（profile）生效，**不能按标签页设置**，也没有 VT 序列能改。设了背景图时，背景本身是透明的，着色器拿到的纹理是预乘 alpha（`matrix-rain.hlsl` 已按这个处理）。着色器不覆盖 padding 区域，所以 phosphor 的 VIGNETTE 默认为 0（否则边缘会出现接缝）。setup 只修改 name/source/commandline 匹配 `PowerShell|pwsh` 的配置，并跳过 Matrix Rain 的 GUID。
- 端到端测试：用 `wt -w mmtest nt -p <guid>` 开一个单独的窗口，别动用户正在用的窗口。标签页里 shell 的父进程是 WindowsTerminal.exe，据此找到 PID，`AttachConsole` + `WriteConsoleInput` 注入按键（`-` 键是 VK 0xBD，不是 0x2D；开场动画会吞掉第一个键，先确认 shell 已经能执行命令），用 `PrintWindow(PW_RENDERFULLCONTENT)` 截图对比。GPU 用 `Get-Counter '\GPU Engine(pid_<WT pid>_*)\Utilization Percentage'`（这台机子的计数器名是英文）。`*>` 重定向在 PS5 写 UTF-16、在 PS7 写 UTF-8，用 `[IO.File]::ReadAllText` 读。**判断颜色要对截图做像素采样**，看缩略图会看走眼（曾经把 `#00FF41` 看成淡色）。预览配色可以在标签页里用 OSC 4/10 临时换调色板（结果是准的），也可以把配色写进 `%LOCALAPPDATA%\Microsoft\Windows Terminal\Fragments\<名字>\*.json`，然后用 `wt nt --colorScheme <名字>` 打开。管道会让 git 关掉颜色，要加 `-c color.ui=always`。`-File` 必须传绝对路径。不要调用 `python3`（Windows 应用商店的占位程序会卡住）。

## README 的演示图

`docs/demo.gif` 是 2026-10-18 重录的（为了开场结尾的 DESERT 大字；37.7 秒，3.3 MB，1116×920，346 帧；名字 shulin，在临时仓库 `D:\项目\zion` 里录，录完删掉了）：开场 → `pwd` → `git status -s` → `git diff` → 敲错 `matirx` 触发闪烁 → `matrix`（菜单、按 `r`、全屏代码雨、按空格醒来、台词）→ `rain`（切到 Matrix Rain 标签页，约 1.7 秒动态雨后结束，接着循环）。`docs/screenshot.png` 是敲错命令后闪烁结束的那一帧（能看到大字和 git 的配色）。两段整屏的雨占了 GIF 的大部分体积；改用 128 色只小 8%，所以保留 256 色。录制方法：
- zion 仓库：`neo.ps1` 提交过的内容是 `$choice = 'red pill'` / `$spoon = $true` / `Follow-WhiteRabbit`，工作区把第二行改成 `$spoon = $null   # there is no spoon`（blob 正好是 `1202f88..bf5c812`）；`oracle.md` 已暂存，`morpheus.txt` 未跟踪。文件要写成 CRLF，否则 autocrlf 会在 `git diff` 里打出换行警告。
- 打开一个单独的 WT 窗口：`wt -w mmrec --size 100,36 nt -p <默认的 PowerShell 配置 guid> -d <仓库> pwsh.exe -NoLogo`。大字比原来的一行多占 7 行，36 行正好让敲错命令后的整屏（大字 + pwd + status + diff + 报错）不滚动。用一个后台线程每 50 ms 调一次 `PrintWindow`（进程先设成 per-monitor DPI aware），另开 3 个线程编码 PNG；用 `WriteConsoleInput` 逐字"打字"（每键 55–130 ms）。脚本用 Windows PowerShell 5.1 跑（C# 里直接用 System.Drawing），文件要带 BOM。
- **开场里按任何键都会跳过开场，而且这个键会被吞掉**：attach 到 shell 的控制台后用 `ReadConsoleOutputCharacter` 读第 10 行，以 `shulin` 开头说明开场（含解码）结束、提示符已经重画。
- 录制窗口弹出来后被手动最小化过一次（GetWindowRect 变成 160×28，帧全废）：录制线程发现 `IsIconic` 就 `ShowWindow(SW_SHOWNOACTIVATE)` 恢复（不抢焦点）。被别的窗口挡住不影响 `PrintWindow`。
- `rain` 打开的新标签页约 2 秒后也会开始播开场（录制时 Intro 还是 always），GIF 要在那之前结束：量每帧第 2 行的亮绿像素，找新标签页里开场文字出现的时刻。现在默认是 launch，重录时新标签页约 1 秒后会解码出 DESERT 大字，同样要在那之前结束。
- 剪辑：裁掉标签栏和边框（终端区域 x=8、y=41、1116×920）；从第一行开场文字出现前几帧开始；相同的帧合并；光标闪烁（A、B、A，B 只在一个格子里不同）合并成一帧，磷光让光标的差异框有 17×31，阈值用宽 ≤24、高 ≤36（打一个字至少变两格，不会被误合并；失败闪烁也不会）；每次停顿最长 2.2 秒，大字那一帧特意给满 2.2 秒；最后一帧只停 80 ms，接着从头循环。然后用 ffmpeg 的 concat 列表带上每帧时长，两遍：`palettegen=reserve_transparent=0`，再 `paletteuse=dither=none:diff_mode=rectangle` 加 `-fps_mode vfr`。
- PS7.4 以后，敲错命令会出现 `[General Feedback]` 提示（"最相似的命令是 matrix"），这是 PowerShell 自带的，录进去了。

## 用户的偏好

- **不要处理 profile 加载慢的问题**：用户说那台机子本来就慢，不是这个主题造成的，他自己解决。
- 动效要克制，不能影响性能（因此放弃了常驻的动态雨，改成静态雨幕 + 磷光）。
- 不能污染别的程序的配色（claude、codex 保留原生主题）。
- 动手大改之前先说方案。**提交和推送不用再问**（2026-10-17 用户明确授权，限本项目）。

## 开场结尾的大字（2026-10-18，用户在三个候选里选的）

"Welcome to the desert of the real" 改成：`W E L C O M E   T O   T H E`（小字，`#3D8A50`）、DESERT 用 figlet "ANSI Shadow" 大字（`█` 字面 `#00FF41`，框线阴影 `#008F11`，成品直接存在 `$MatrixDesert`，没有字库）、右对齐的 `O F   T H E   R E A L`。共 8 行、左边空 2 列，宽 51 列。出现方式选的是**片假名解码**：和 pwd 一样从左到右 14 帧 × 20 ms，解码边缘两列用雨滴头的 `#C7FFD1`，按键立即显示完整；开场被按键跳过时直接显示。窗口不到 52 列或 12 行时退回原来的一行小字。落选的：整句 3D 大字（20 行高，80 列放不下）、整句 Calvin S 细线体。

## 输出配色（2026-10-16，用户在 A/B/C/D 四个候选里选了 A）

以前 16 色几乎全是绿的，前景色 `#00FF41` 和 green `#00C832` 也几乎一样，git diff 的新增行和没改的行分不清。现在的分工是：提示符、输入高亮、雨幕和开场用自己的 RGB 矩阵绿（不受配色影响）；命令输出的正文用淡磷光色 `#B4F1C4`，16 色各有含义：red `#FF3E5B` 红药丸（删除、错误），green `#00E03C` / 亮 `#00FF41`（新增、成功、表头），yellow `#FFB000` 琥珀磷光（警告、commit 号），blue `#508CFF` 蓝药丸，purple `#C38BFF`，cyan `#2EE6D6`（`@@`、HEAD、详细信息）。所有颜色和背景的对比度至少 4.1（brightBlack `#4F7A5A`），正文 15.9。

- 不改用户的 `.gitconfig`：调色板对了，git 的默认颜色就都对了。
- PS7：Verbose 用青色、Debug 用紫色（默认和警告一样是黄色），图片和音视频用紫色，再补几种压缩包用红色；只在值还是 PowerShell 默认值时才改，所以用户在 `$PROFILE` 里先设的值会保留。PS5：`$Host.PrivateData` 里 Verbose 设成 DarkCyan、Debug 设成 DarkMagenta（对应配色里的 cyan 和 purple）；进度条默认是黄字配 DarkCyan 底，在这套配色下变成琥珀字配青色底，对比度只有 1.04，所以字改成 Black（截图确认过能看清）。PS7 的进度条是黑字配琥珀底，本来就清楚。
- **目录颜色保持薄荷绿 `#7DFFB8` 加粗**：用户说先看看效果，暂时不改成蓝色。

## `rain`：单独一个标签页下雨

着色器只能按配置设置，所以 `rain` 用一个专门的 WT 配置 "Matrix Rain"（固定 GUID `{4d415452-4958-5241-494e-6d696e696d61}`，即 "MATRIXRAINminima"）：commandline 是 `pwsh.exe -NoLogo` 或 PS5 的完整路径，Matrix Minimal 配色，`matrix-rain.hlsl`，**不设背景图**，字体从 `profiles.defaults` 继承。

- 第一次运行 `rain` 时，把这个配置**以文本方式**插到 `profiles.list` 末尾，用正则分词器数括号（`Get-ProfileList`，兼容注释、尾逗号、旧版 `"profiles": [...]`），缩进照抄第一个配置，保留 BOM 和换行符。然后运行 `wt -w 0 nt -p <guid> -d <当前目录，; 转义成 \;> <当前 shell> -NoLogo`。
- 在雨的标签页里（`$env:WT_PROFILE_ID` 等于这个 GUID）运行 `rain` 会再开一个下雨的标签页（2026-10-18 用户要求，以前只给提示）。`rain off` 只给提示，另外兼容旧版（ddfb813）：只把含有 `matrix-rain-clear.png` 且不是 Matrix Rain 的配置换回来。
- setup 跳过这个 GUID；uninstall 删除这个配置，而且在 `$inUse` 判断**之前**删（它也用 Matrix Minimal 配色）。
- 实测（2026-10-16，这台机子）：
  - 插入配置后立即 `wt -p <guid>`，WT 会**静默**换成别的配置打开（按 commandline 匹配到了 Windows PowerShell）；等 100 ms 就够了，代码里等 1 秒。
  - 在标签页里运行时，`-w 0` 指向这个标签页所在的窗口。WT 重建命令行时会给带空格的参数加引号（Program Files 下的 pwsh 7.6.0 正常）。`-d` 里用 `\;` 可以。
  - Store 版 pwsh 的 `$PSHOME` 在 WindowsApps 下，所以新标签页改用 `pwsh.exe`（走应用执行别名）启动。
  - 负载（RTX 4090，窗口 2560×1392；WT 进程，CPU 按一个核算）：只有静态标签页时 GPU 0.2%、CPU 0.3%；雨的标签页在前台时 GPU 0.7%、CPU 2.2%；**切到别的标签页**时 GPU 0.4%、CPU 2.5%；**最小化**时 GPU 0.6%、CPU 3.4%；关掉标签页后回落。所以切走或最小化都不会停，只能关掉标签页。提示语和 README 里已经这么写了。

## 提示符里的 Python 环境（2026-10-21，用户在四个候选里选了 A）

样子：`shulin (zion) main* >`，括号 `p:ghost`、环境名 `p:mint`（`#7DFFB8`），放在名字和分支之间。落选的有：放在行首、放在右侧、`py:zion` 文字标签。只做 Python 环境：调研了 Starship、Powerlevel10k、Pure 和 oh-my-posh，四家唯一都默认开启的就是 conda 和 venv。语言版本要启动进程去查，云上下文不是"被激活的环境"，所以都不做。

- 用的是 oh-my-posh 自带的 `python` 段：`display_mode: environment`；`fetch_version: false`（不启动 python，约 2 ms）；**`home_enabled: true`**（默认是 false，在家目录下环境名会被隐藏）；`default_venv_names` 扩展到 `.venv venv .env env .conda conda virtualenv`。名字是通用名时显示上一级目录名，这条规则对 `CONDA_DEFAULT_ENV` 也生效。conda 用 `-p` 建的环境，`CONDA_DEFAULT_ENV` 是整条路径（envs 目录里的环境才是名字），所以 VS Code 建的 `myproj\.conda` 会显示成 `myproj`。模板里用 `regexReplaceAll` 去掉 poetry 环境名末尾的 `-<8位哈希>-py3.x`。同时有 venv 和 conda 时，优先显示 venv。base 照常显示（和 conda 自己的习惯一致）。
- 重复前缀：oh-my-posh 的 init 会设 `VIRTUAL_ENV_DISABLE_PROMPT=1`（这时 CPython 的 Activate.ps1 不设 `VIRTUAL_ENV_PROMPT`，所以 `--prompt 别名` 不会显示，显示的是目录名；uv 和 virtualenv 不管这个变量都会设）。conda 的 hook 如果在主题**之后**加载（比如"Anaconda PowerShell Prompt"快捷方式），会把 `prompt` 改名成 `CondaPromptBackup` 再包一层，用 `Write-Host` 输出 `CONDA_PROMPT_MODIFIER`，结果出现 `(base) shulin (base)`。所以 `matrix-minimal.ps1` 在本主题的提示符生效时设 `$env:CONDA_CHANGEPS1 = 'false'`：`conda-hook.ps1` 里写死了 `ChangePs1 = $True`，但这样设之后 modifier 是空串，就不会输出了。`conda init` 写在 `profile.ps1`（CurrentUserAllHosts）里，比主题先加载，它的包装会被 oh-my-posh 换掉，本来就不会重复。
- conda 25.1.1 之前的版本配 PS 7.5+ 时，激活 base 之后再运行任何 `conda` 命令都会报 `invalid choice: ''`，不加载主题也一样，这是公开的 bug（conda/conda#14292，在 25.1.1 修好）。原因：激活脚本里写的是 `$Env:_CE_M = ""`，PS 7.5 起这样不再删除变量，而 PS 7.3 起空字符串会被当作参数，于是 `& $Env:CONDA_EXE $Env:_CE_M ...` 多传了两个空串。PS5 和 PS 7.4 没有这个问题。这台机子 2026-10-21 已经升级到 conda 26.1.1（`conda update` 只能升到 24.11.3，要写 `conda install -n base conda=26.1.1`；要回退就 `conda install --revision 0`）。朋友遇到这个问题，让他们升级 conda，不用在主题里处理。
- 用户的两个 profile 末尾有一个占位的 `conda` 函数：第一次运行时加载静态的 `anaconda3\shell\condabin\conda-hook.ps1`（约 0.1 秒）。`conda init` 的写法每次启动都要运行 conda.exe，在这台机子上约 3.3 秒。hook 是在主题之后加载的，所以靠 `CONDA_CHANGEPS1` 才不会重复显示环境名（已实测）。
- 测法：`-NoProfile` 下 dot-source 仓库里的 `matrix-minimal.ps1`，运行真实的 `activate.ps1` 或 conda hook，再用 `prompt 6>&1` 取输出（外层包装用 `Write-Host` 写的内容也能取到）。也可以 `oh-my-posh print primary --config ... --pwd ...` 配合环境变量测，记得 `env -u POSH_SESSION_ID`。

## 其他未完成的事

- 朋友的机子当初"没有开场动画"的确切原因没有复现出来，修复针对的是可能的原因。如果还有问题，让他重新运行安装并发 `Test-MatrixMinimal` 的输出。
- 朋友在运行 `irm | iex` 的同一个窗口里输入 `rain`，报"找不到命令"：那个窗口加载的还是旧版 profile，新开标签页就好。提议过在 `install.ps1` 结尾（仅 iex 安装时）当场重新加载 `matrix-terminal.ps1`，并把结尾提示改成"新命令要在新标签页里用"，用户还没决定。
- PS5 下的失败闪烁效果还没有目测确认过。
- 仓库没有 LICENSE（提过，用户还没要求）。
