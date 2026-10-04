Claude Multi-Route Launcher - Public Edition 1.0.2

[⬇️ Download Public Edition 1.0.2](https://github.com/Open-bookwriter/claude-code-multi-route-launcher/releases/download/v1.0.2/Claude_Multi_Route_Launcher_Public_Edition_1.0.2.zip)

[View all releases](https://github.com/Open-bookwriter/claude-code-multi-route-launcher/releases)
==================================================

定位
----
一个 Windows 本地辅助启动器，用于：
- 启动 Claude Code 官方/默认认证；
- 保存多条 Anthropic-compatible API / LLM Gateway 线路；
- 获取网关公开的模型列表；
- 在启动前做轻量可用性测试；
- 保存项目快捷入口；
- 快速切换线路、模型和项目。

重要声明
--------
- 本项目不是 Anthropic 官方产品，与 Anthropic 无隶属或背书关系。
- 本包不包含 Claude Code 本体，也不会自动安装 Claude Code。
- 本工具不会绕过订阅、API 计费、地区限制、账号政策或服务条款。
- 第三方网关返回的模型名称只是该网关的声明；启动器无法验证其真实上游模型身份。
- 使用第三方 API / 网关时，请自行评估数据隐私、价格、稳定性与服务条款。

系统要求
--------
- Windows 10 1809+ / Windows 11
- Windows PowerShell 5.1+
- Claude Code 已安装（推荐使用 Anthropic 官方原生安装方式）
- Windows Terminal：可选
- Git for Windows：可选

Claude Code 官方 Windows 安装方式（截至 Public Edition 1.0.2 发布时）：
PowerShell:
  irm https://claude.ai/install.ps1 | iex

WinGet:
  winget install Anthropic.ClaudeCode

验证：
  claude --version

官方安装文档：
  https://code.claude.com/docs/en/setup

快速开始
--------
1. 解压整个文件夹到任意你有写权限的位置。
2. 双击 Open-Launcher.cmd（推荐）或 Start-Launcher.cmd。
3. 首次运行会执行环境检查与项目目录设置。
4. 如果使用官方 Claude 登录：主菜单按 O。
5. 如果使用自己的 API / 网关：
   - J：粘贴 New API 连接 JSON；或
   - A：手动添加 Base URL + Key。
6. 选择线路 -> 选择模型 -> 选择项目 -> 启动 Claude Code。

主菜单
------
Enter  快速启动最近一次 API 线路 / 模型 / 项目
O      官方/默认认证启动（不注入网关 Key）
M      使用最近 API 线路重新选择模型并启动
J      一键导入 New API JSON
A      手动新增 API 线路
K      更新 API Key
E      编辑线路 Base URL / 认证方式
P      管理项目快捷入口
P1...  从主菜单直接启动命名项目
C      环境检查 / 设置 Claude 可执行文件路径 / 默认项目目录
D      删除线路
Q      退出

模型状态
--------
[?]  未检测
[OK] 最近一次检测成功 + 时间
[X]  最近一次检测失败 + 时间

注意：模型列表“存在”不代表当前一定可用；真正启动前仍会进行实时轻量检测。
S 批量检测会对每个模型发出请求，可能产生少量 API 费用。

用户数据与隐私
--------------
Public Edition 的程序目录不保存用户 Key。
运行后，用户数据默认保存在：
  %LOCALAPPDATA%\ClaudeMultiRouteLauncher\

其中：
- profiles\*.json      线路名称、Base URL、认证方式（不含明文 Key）
- profiles\*.secret    Windows 当前用户 DPAPI 加密后的 Key
- launcher-state.json  最近线路、模型、项目和检测状态
- projects.json        项目名称与本地路径
- settings.json        本地设置

不要将上述用户数据目录打包发给其他人。
DPAPI 密钥通常只能由创建它的 Windows 用户上下文解密。

无固定盘符依赖
--------------
Public Edition 不依赖 D: 或任何固定安装目录。
默认项目目录为当前 Windows 用户的“文档\ClaudeProjects”。
Claude Code 默认通过 PATH 自动发现；也可在 C -> 设置中手动指定 claude.exe / claude.cmd。

API 兼容说明
------------
自动模型发现使用：
  GET <Base URL>/v1/models

模型可用性测试使用 Anthropic Messages 兼容接口：
  POST <Base URL>/v1/messages

如果网关不提供 /v1/models，可以手动输入模型 ID。
如果网关只支持 OpenAI Chat Completions 而不兼容 Anthropic Messages，则不能直接用于 Claude Code 此启动模式。

更新/重新分发
------------
公开发布时只分发此压缩包内的程序文件。
不要附带任何运行后生成的 profiles、*.secret、launcher-state.json、projects.json、settings.json。

建议发布前自行选择适合你的开源/商业许可证。


Public Edition 1.0.2 Windows PowerShell 5.1 compatibility hotfix:
- PowerShell scripts are encoded as UTF-8 with BOM.
- This prevents Chinese text from being misread as the system ANSI code page.
- Fixes startup ParserError / UnexpectedToken errors seen on some Chinese Windows systems.


Public Edition 1.0.2 validation status:
- Clean Windows first-run flow: PASS
- API route import: PASS
- Model list retrieval: PASS
- Live model availability test: PASS
- Claude Code launch: PASS
- Real chat response: PASS

This release contains no bundled API key, account session, provider credential,
personal project history, or preconfigured third-party API route.
