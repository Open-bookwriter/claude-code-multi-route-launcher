Claude Multi-Route Launcher - Security Notes
============================================

1. API Key 存储
- Key 不写入 JSON 配置。
- Key 使用 Windows PowerShell ConvertFrom-SecureString，在 Windows 上由当前用户上下文加密。
- 加密文件保存在：%LOCALAPPDATA%\ClaudeMultiRouteLauncher\profiles\*.secret

2. 不要分享用户数据目录
即便 *.secret 不是明文，也不要上传、共享或提交以下目录：
  %LOCALAPPDATA%\ClaudeMultiRouteLauncher\

3. 运行时凭据
启动器仅在启动 Claude Code 的当前进程环境中临时设置网关 URL 与凭据；Claude Code 退出后会恢复启动器原有的环境变量值。

4. 第三方网关风险
第三方网关可能读取你的提示词、代码、文件摘要和模型请求。只有在你信任该提供商时才使用。

5. 模型身份
/v1/models 返回的模型名称和成功响应只能证明网关接受该模型 ID，不能由本启动器证明真实上游模型身份。

6. 官方模式
主菜单 O 会清除本启动器管理的网关变量后启动 Claude Code 默认认证，避免把保存的第三方网关凭据注入官方模式。

7. 不自动安装
Public Edition 不自动执行远程安装脚本，也不修改防火墙、系统代理或系统级网络设置。
