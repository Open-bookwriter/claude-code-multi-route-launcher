$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Target = Join-Path $Root 'Open-Launcher.cmd'
if (-not (Test-Path $Target)) { throw '找不到 Open-Launcher.cmd' }

$Desktop = [Environment]::GetFolderPath('Desktop')
$LinkPath = Join-Path $Desktop 'Claude Multi-Route Launcher.lnk'
$PowerShellIcon = Join-Path $PSHOME 'powershell.exe'

$Shell = New-Object -ComObject WScript.Shell
$Shortcut = $Shell.CreateShortcut($LinkPath)
$Shortcut.TargetPath = $Target
$Shortcut.WorkingDirectory = $Root
$Shortcut.IconLocation = "$PowerShellIcon,0"
$Shortcut.Description = 'Claude Multi-Route Launcher - Public Edition'
$Shortcut.Save()

Write-Host ''
Write-Host '桌面快捷方式已创建：' -ForegroundColor Green
Write-Host $LinkPath
Write-Host ''
Write-Host '本公开版使用 Windows 自带图标，不包含 Anthropic/Claude 官方商标图标。' -ForegroundColor DarkGray
Write-Host ''
Read-Host '按 Enter 退出'
