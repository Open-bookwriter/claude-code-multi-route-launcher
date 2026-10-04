Claude Multi-Route Launcher - Public Edition
============================================

1.0.2
-----
- Release candidate promoted after clean Windows end-to-end validation.
- First-run wizard PASS.
- Claude Code auto-detection PASS.
- No D: drive dependency PASS.
- New API JSON import PASS.
- Model discovery PASS.
- Live model test PASS.
- Project directory handling PASS.
- Claude Code launch PASS.
- Real conversation through imported API route PASS.
- Synced the visible launcher title to version 1.0.2.

1.0.1
-----
- Hotfix: saved PowerShell scripts as UTF-8 with BOM for Windows PowerShell 5.1.
- Fixes garbled Chinese text and ParserError / UnexpectedToken errors when launching on Chinese Windows.

1.0.0
-----
- First public/distribution-ready release.
- Removed fixed D: drive and machine-specific paths.
- Removed all preconfigured gateway/provider data.
- Stores runtime user data under %LOCALAPPDATA%\ClaudeMultiRouteLauncher.
- Added first-run wizard and environment diagnostics.
- Added official/default Claude Code launch mode without gateway credentials.
- Added configurable Claude executable path.
- Added New API JSON import and manual Bearer/x-api-key profiles.
- Added model discovery, manual model entry, live model testing and status timestamps.
- Added recent-project and named-project shortcuts.
- Added main-menu model switch and project quick-launch commands.
- Added environment snapshot/restore around Claude Code sessions.
- Uses only documented Claude Code routing/model environment variables.
- Removed custom Anthropic/Claude logo artwork from the distributable package.
