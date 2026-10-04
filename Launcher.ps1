#requires -Version 5.1
$ErrorActionPreference = 'Stop'

$AppName = 'Claude Multi-Route Launcher'
$Version = '1.0.0'
$DataRoot = Join-Path $env:LOCALAPPDATA 'ClaudeMultiRouteLauncher'
$ProfilesDir = Join-Path $DataRoot 'profiles'
$SettingsPath = Join-Path $DataRoot 'settings.json'
$StatePath = Join-Path $DataRoot 'launcher-state.json'
$ProjectsPath = Join-Path $DataRoot 'projects.json'

New-Item -ItemType Directory -Path $DataRoot -Force | Out-Null
New-Item -ItemType Directory -Path $ProfilesDir -Force | Out-Null

function Write-Title {
    Clear-Host
    Write-Host '============================================================' -ForegroundColor Cyan
    Write-Host '   Claude Multi-Route Launcher - Public Edition 1.0.2' -ForegroundColor Cyan
    Write-Host '============================================================' -ForegroundColor Cyan
    Write-Host ''
}

function Pause-Launcher {
    Write-Host ''
    [void](Read-Host '按 Enter 继续')
}

function Get-SafeName([string]$Name) {
    $safe = ($Name -replace '[\\/:*?"<>|]', '_').Trim()
    if ([string]::IsNullOrWhiteSpace($safe)) { throw '名称不能为空。' }
    return $safe
}

function Get-DefaultProjectsRoot {
    $docs = [Environment]::GetFolderPath('MyDocuments')
    if ([string]::IsNullOrWhiteSpace($docs)) {
        $docs = $HOME
    }
    return (Join-Path $docs 'ClaudeProjects')
}

function New-Settings {
    return [pscustomobject]@{
        first_run_completed = $false
        projects_root = (Get-DefaultProjectsRoot)
        claude_path = ''
    }
}

function Load-Settings {
    if (-not (Test-Path $SettingsPath)) { return (New-Settings) }
    try {
        $s = Get-Content -LiteralPath $SettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -eq $s.first_run_completed) { $s | Add-Member -NotePropertyName first_run_completed -NotePropertyValue $false }
        if ($null -eq $s.projects_root -or [string]::IsNullOrWhiteSpace([string]$s.projects_root)) {
            $s | Add-Member -Force -NotePropertyName projects_root -NotePropertyValue (Get-DefaultProjectsRoot)
        }
        if ($null -eq $s.claude_path) { $s | Add-Member -NotePropertyName claude_path -NotePropertyValue '' }
        return $s
    } catch {
        return (New-Settings)
    }
}

function Save-Settings($Settings) {
    $Settings | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $SettingsPath -Encoding UTF8
}

function New-State {
    return [pscustomobject]@{
        last_profile_id = ''
        last_project = ''
        recent_projects = @()
        last_selections = @()
        model_status = @()
    }
}

function Load-State {
    if (-not (Test-Path $StatePath)) { return (New-State) }
    try {
        $s = Get-Content -LiteralPath $StatePath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -eq $s.last_profile_id) { $s | Add-Member -NotePropertyName last_profile_id -NotePropertyValue '' }
        if ($null -eq $s.last_project) { $s | Add-Member -NotePropertyName last_project -NotePropertyValue '' }
        if ($null -eq $s.recent_projects) { $s | Add-Member -NotePropertyName recent_projects -NotePropertyValue @() }
        if ($null -eq $s.last_selections) { $s | Add-Member -NotePropertyName last_selections -NotePropertyValue @() }
        if ($null -eq $s.model_status) { $s | Add-Member -NotePropertyName model_status -NotePropertyValue @() }
        return $s
    } catch {
        return (New-State)
    }
}

function Save-State($State) {
    $State | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $StatePath -Encoding UTF8
}

function Get-LastSelection($State, [string]$ProfileId) {
    return @($State.last_selections | Where-Object { $_.profile_id -eq $ProfileId } | Select-Object -First 1)
}

function Set-LastSelection($State, [string]$ProfileId, [string]$Model, [string]$Project) {
    $remaining = @($State.last_selections | Where-Object { $_.profile_id -ne $ProfileId })
    $entry = [pscustomobject]@{
        profile_id = $ProfileId
        model = $Model
        project = $Project
    }
    $State.last_selections = @($entry) + $remaining
    $State.last_profile_id = $ProfileId
    $State.last_project = $Project

    $recent = @($Project) + @($State.recent_projects | Where-Object { $_ -ne $Project })
    if ($recent.Count -gt 5) { $recent = $recent[0..4] }
    $State.recent_projects = $recent
    Save-State $State
}

function Get-ModelStatus($State, [string]$ProfileId, [string]$Model) {
    return @($State.model_status | Where-Object {
        $_.profile_id -eq $ProfileId -and $_.model -eq $Model
    } | Select-Object -First 1)
}

function Set-ModelStatus($State, [string]$ProfileId, [string]$Model, [bool]$Ok, [string]$Message) {
    $remaining = @($State.model_status | Where-Object {
        -not ($_.profile_id -eq $ProfileId -and $_.model -eq $Model)
    })
    $entry = [pscustomobject]@{
        profile_id = $ProfileId
        model = $Model
        ok = $Ok
        checked_at = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        message = $Message
    }
    $State.model_status = @($entry) + $remaining
    Save-State $State
}

function Get-StatusLabel($State, [string]$ProfileId, [string]$Model) {
    $x = @(Get-ModelStatus $State $ProfileId $Model)
    if ($x.Count -eq 0) { return '[?] 未检测' }
    $time = [string]$x[0].checked_at
    if ([bool]$x[0].ok) { return "[OK] $time" }
    return "[X] $time"
}

function New-ProjectsStore {
    return [pscustomobject]@{ projects = @() }
}

function Load-Projects {
    if (-not (Test-Path $ProjectsPath)) { return (New-ProjectsStore) }
    try {
        $p = Get-Content -LiteralPath $ProjectsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -eq $p.projects) { $p | Add-Member -NotePropertyName projects -NotePropertyValue @() }
        return $p
    } catch {
        return (New-ProjectsStore)
    }
}

function Save-Projects($Store) {
    $Store | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $ProjectsPath -Encoding UTF8
}

function Normalize-BaseUrl([string]$Url) {
    $u = $Url.Trim().TrimEnd('/')
    $u = $u -replace '(?i)/v1$', ''
    if ($u -notmatch '^https?://') { throw 'Base URL 必须以 http:// 或 https:// 开头。' }
    return $u
}

function Endpoint([string]$BaseUrl, [string]$Path) {
    return ((Normalize-BaseUrl $BaseUrl) + '/v1/' + $Path.TrimStart('/'))
}

function Write-EncryptedSecretFromSecureString([string]$Path, [Security.SecureString]$Secure) {
    $encrypted = $Secure | ConvertFrom-SecureString
    [IO.File]::WriteAllText($Path, $encrypted, [Text.Encoding]::ASCII)
}

function Write-EncryptedSecretFromPlainText([string]$Path, [string]$Plain) {
    $secure = ConvertTo-SecureString $Plain -AsPlainText -Force
    try { Write-EncryptedSecretFromSecureString $Path $secure }
    finally { $secure = $null }
}

function Read-EncryptedSecret([string]$Path) {
    if (-not (Test-Path $Path)) { throw '找不到该线路的加密密钥文件。' }
    $encrypted = (Get-Content -LiteralPath $Path -Raw).Trim()
    if ([string]::IsNullOrWhiteSpace($encrypted)) { throw '密钥文件为空。' }
    $secure = $encrypted | ConvertTo-SecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

function Get-ProfileEntries {
    $items = @()
    Get-ChildItem -Path $ProfilesDir -Filter '*.json' -File -ErrorAction SilentlyContinue |
        Sort-Object Name | ForEach-Object {
            try {
                $obj = Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
                $items += [pscustomobject]@{
                    Id = $_.BaseName
                    File = $_.FullName
                    SecretFile = [IO.Path]::ChangeExtension($_.FullName, '.secret')
                    Name = [string]$obj.name
                    BaseUrl = [string]$obj.base_url
                    AuthMode = [string]$obj.auth_mode
                }
            } catch {
                Write-Host "忽略损坏的线路配置：$($_.Name)" -ForegroundColor Yellow
            }
        }
    return $items
}

function Save-Profile([string]$Name, [string]$BaseUrl, [string]$AuthMode, [string]$PlainKey = $null, [Security.SecureString]$SecureKey = $null) {
    $safe = Get-SafeName $Name
    $profilePath = Join-Path $ProfilesDir ($safe + '.json')
    $secretPath = Join-Path $ProfilesDir ($safe + '.secret')
    $normalized = Normalize-BaseUrl $BaseUrl

    [pscustomobject]@{
        name = $Name
        base_url = $normalized
        auth_mode = $AuthMode
    } | ConvertTo-Json | Set-Content -LiteralPath $profilePath -Encoding UTF8

    if ($null -ne $SecureKey) {
        Write-EncryptedSecretFromSecureString $secretPath $SecureKey
    } elseif ($null -ne $PlainKey) {
        Write-EncryptedSecretFromPlainText $secretPath $PlainKey
    } else {
        throw '未提供 API Key。'
    }
}

function Import-NewApiJson {
    Write-Title
    Write-Host '一键导入 New API / 兼容连接信息' -ForegroundColor Green
    Write-Host ''
    Write-Host '示例：{"_type":"newapi_channel_conn","key":"sk-...","url":"https://gateway.example.com"}' -ForegroundColor DarkGray
    Write-Host ''
    $raw = Read-Host '粘贴完整一行 JSON'
    try { $obj = $raw | ConvertFrom-Json }
    catch { throw 'JSON 格式不正确。' }

    $url = [string]$obj.url
    $key = [string]$obj.key
    if ([string]::IsNullOrWhiteSpace($url)) { throw 'JSON 中没有有效的 url。' }
    if ([string]::IsNullOrWhiteSpace($key)) { throw 'JSON 中没有有效的 key。' }

    $normalized = Normalize-BaseUrl $url
    $defaultName = ([Uri]$normalized).Host
    $name = Read-Host "线路名称（直接 Enter 使用 $defaultName）"
    if ([string]::IsNullOrWhiteSpace($name)) { $name = $defaultName }

    $safe = Get-SafeName $name
    if (Test-Path (Join-Path $ProfilesDir ($safe + '.json'))) {
        $overwrite = Read-Host '同名线路已存在，是否覆盖？[y/N]'
        if ($overwrite -notmatch '^[Yy]$') { return }
    }

    try { Save-Profile $name $normalized 'bearer' $key $null }
    finally {
        $key = $null
        $raw = $null
        $obj = $null
        [GC]::Collect()
    }

    Write-Host ''
    Write-Host '导入成功。API Key 已使用 Windows 当前用户加密保存。' -ForegroundColor Green
    Pause-Launcher
}

function Add-Profile {
    Write-Title
    Write-Host '手动新增线路' -ForegroundColor Green
    Write-Host ''

    $name = Read-Host '线路名称'
    $url = Read-Host 'Base URL'

    Write-Host ''
    Write-Host '认证方式：'
    Write-Host '  1. Bearer Token（ANTHROPIC_AUTH_TOKEN，很多兼容网关常用）'
    Write-Host '  2. x-api-key（ANTHROPIC_API_KEY，Anthropic API 常用）'
    $a = Read-Host '请选择 [1/2，默认 1]'
    $mode = $(if ($a -eq '2') { 'api_key' } else { 'bearer' })

    $secure = Read-Host 'API Key（输入内容不会显示）' -AsSecureString
    try { Save-Profile $name $url $mode $null $secure }
    finally { $secure = $null }

    Write-Host ''
    Write-Host '线路已保存。' -ForegroundColor Green
    Pause-Launcher
}

function Choose-Profile([string]$Purpose) {
    $profiles = @(Get-ProfileEntries)
    if ($profiles.Count -eq 0) {
        Write-Host '当前没有保存任何 API 线路。' -ForegroundColor Yellow
        Pause-Launcher
        return $null
    }

    Write-Host $Purpose -ForegroundColor Green
    Write-Host ''
    for ($i = 0; $i -lt $profiles.Count; $i++) {
        Write-Host ("  {0}. {1} [{2}]" -f ($i + 1), $profiles[$i].Name, $profiles[$i].BaseUrl)
    }
    Write-Host '  0. 返回'

    $c = Read-Host '请选择'
    $n = 0
    if (-not [int]::TryParse($c, [ref]$n) -or $n -lt 0 -or $n -gt $profiles.Count) { return $null }
    if ($n -eq 0) { return $null }
    return $profiles[$n - 1]
}

function Update-Key {
    Write-Title
    $p = Choose-Profile '选择要更新 Key 的线路'
    if ($null -eq $p) { return }

    $secure = Read-Host '输入新的 API Key（输入不显示）' -AsSecureString
    try { Write-EncryptedSecretFromSecureString $p.SecretFile $secure }
    finally { $secure = $null }

    Write-Host ''
    Write-Host 'API Key 已更新。' -ForegroundColor Green
    Pause-Launcher
}

function Edit-Profile {
    Write-Title
    $p = Choose-Profile '选择要编辑的线路'
    if ($null -eq $p) { return }

    $url = Read-Host "Base URL（Enter 保持 $($p.BaseUrl)）"
    if ([string]::IsNullOrWhiteSpace($url)) { $url = $p.BaseUrl }
    $url = Normalize-BaseUrl $url

    Write-Host "当前认证方式：$($p.AuthMode)"
    Write-Host '1. Bearer Token'
    Write-Host '2. x-api-key'
    $a = Read-Host '认证方式（Enter 保持不变）'
    $mode = $p.AuthMode
    if ($a -eq '1') { $mode = 'bearer' }
    elseif ($a -eq '2') { $mode = 'api_key' }

    [pscustomobject]@{
        name = $p.Name
        base_url = $url
        auth_mode = $mode
    } | ConvertTo-Json | Set-Content -LiteralPath $p.File -Encoding UTF8

    Write-Host ''
    Write-Host '线路参数已更新。' -ForegroundColor Green
    Pause-Launcher
}

function Remove-Profile {
    Write-Title
    $p = Choose-Profile '选择要删除的线路'
    if ($null -eq $p) { return }

    $ok = Read-Host "确定删除 '$($p.Name)'？[y/N]"
    if ($ok -match '^[Yy]$') {
        Remove-Item -LiteralPath $p.File -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $p.SecretFile -Force -ErrorAction SilentlyContinue
        Write-Host '已删除。' -ForegroundColor Green
        Pause-Launcher
    }
}

function Manage-Projects($Settings) {
    while ($true) {
        $store = Load-Projects
        $items = @($store.projects)

        Write-Title
        Write-Host '项目快捷入口' -ForegroundColor Green
        Write-Host "默认项目根目录：$($Settings.projects_root)" -ForegroundColor DarkGray
        Write-Host ''

        if ($items.Count -eq 0) {
            Write-Host '暂无项目快捷入口。' -ForegroundColor Yellow
        } else {
            for ($i = 0; $i -lt $items.Count; $i++) {
                Write-Host ("  {0}. {1} -> {2}" -f ($i + 1), $items[$i].name, $items[$i].path)
            }
        }

        Write-Host ''
        Write-Host '  A. 新增项目'
        Write-Host '  R. 重命名项目'
        Write-Host '  P. 修改项目路径'
        Write-Host '  D. 删除项目'
        Write-Host '  B. 返回'
        Write-Host ''

        $c = Read-Host '请选择'
        if ($c -match '^[Bb]$') { return }

        if ($c -match '^[Aa]$') {
            $name = (Read-Host '项目名称（例如：Web采集引擎）').Trim()
            if ([string]::IsNullOrWhiteSpace($name)) {
                Write-Host '项目名称不能为空。' -ForegroundColor Red
                Pause-Launcher
                continue
            }

            $defaultPath = Join-Path ([string]$Settings.projects_root) (Get-SafeName $name)
            $path = (Read-Host "项目路径（直接 Enter 使用 $defaultPath）").Trim()
            if ([string]::IsNullOrWhiteSpace($path)) { $path = $defaultPath }

            if (-not [IO.Path]::IsPathRooted($path)) {
                Write-Host '项目路径必须是完整路径。' -ForegroundColor Red
                Pause-Launcher
                continue
            }

            $dup = @($store.projects | Where-Object { $_.name -eq $name -or $_.path -eq $path })
            if ($dup.Count -gt 0) {
                Write-Host '已存在同名项目或相同路径，未重复添加。' -ForegroundColor Yellow
                Pause-Launcher
                continue
            }

            if (-not (Test-Path $path)) {
                $create = Read-Host '目录不存在，是否创建？[Y/n]'
                if ($create -notmatch '^[Nn]$') {
                    New-Item -ItemType Directory -Path $path -Force | Out-Null
                }
            }

            $store.projects = @($store.projects) + [pscustomobject]@{ name = $name; path = $path }
            Save-Projects $store
            continue
        }

        if ($items.Count -eq 0) {
            Write-Host '当前没有项目。' -ForegroundColor Yellow
            Pause-Launcher
            continue
        }

        $raw = Read-Host '项目序号'
        $n = 0
        if (-not [int]::TryParse($raw, [ref]$n) -or $n -lt 1 -or $n -gt $items.Count) {
            Write-Host '项目序号无效。' -ForegroundColor Red
            Pause-Launcher
            continue
        }
        $target = $items[$n - 1]

        if ($c -match '^[Rr]$') {
            $newName = Read-Host "新名称（当前：$($target.name)）"
            if (-not [string]::IsNullOrWhiteSpace($newName)) {
                $target.name = $newName.Trim()
                Save-Projects $store
            }
            continue
        }

        if ($c -match '^[Pp]$') {
            $newPath = Read-Host "新路径（当前：$($target.path)）"
            if (-not [string]::IsNullOrWhiteSpace($newPath)) {
                $newPath = $newPath.Trim()
                if (-not [IO.Path]::IsPathRooted($newPath)) {
                    Write-Host '项目路径必须是完整路径。' -ForegroundColor Red
                    Pause-Launcher
                    continue
                }
                $target.path = $newPath
                Save-Projects $store
            }
            continue
        }

        if ($c -match '^[Dd]$') {
            $ok = Read-Host "确定删除 '$($target.name)'？[y/N]"
            if ($ok -match '^[Yy]$') {
                $newItems = @()
                for ($j = 0; $j -lt $items.Count; $j++) {
                    if ($j -ne ($n - 1)) { $newItems += $items[$j] }
                }
                $store.projects = $newItems
                Save-Projects $store
            }
            continue
        }

        Write-Host '选择无效。' -ForegroundColor Red
        Pause-Launcher
    }
}

function Build-Headers([string]$AuthMode, [string]$Key, [bool]$ForMessage = $false) {
    $h = @{}
    if ($AuthMode -eq 'api_key') { $h['x-api-key'] = $Key }
    else { $h['Authorization'] = "Bearer $Key" }

    if ($ForMessage) {
        $h['anthropic-version'] = '2023-06-01'
        $h['content-type'] = 'application/json'
    }
    return $h
}

function Get-Models([string]$BaseUrl, [string]$AuthMode, [string]$Key) {
    try {
        $r = Invoke-RestMethod -Method Get -Uri (Endpoint $BaseUrl 'models') -Headers (Build-Headers $AuthMode $Key $false) -TimeoutSec 20
        $models = @()
        if ($null -ne $r.data) {
            $models = @($r.data | ForEach-Object { [string]$_.id } | Where-Object { $_ })
        } elseif ($r -is [Array]) {
            $models = @($r | ForEach-Object { [string]$_.id } | Where-Object { $_ })
        }

        $claudeModels = @($models | Where-Object { $_ -match '(?i)claude|haiku|sonnet|opus|fable' } | Sort-Object -Unique)
        if ($claudeModels.Count -gt 0) { return $claudeModels }
        return @($models | Sort-Object -Unique)
    } catch {
        Write-Host ''
        Write-Host '无法自动读取 /v1/models。该网关可能不提供模型列表，可手动输入模型 ID。' -ForegroundColor Yellow
        Write-Host $_.Exception.Message -ForegroundColor DarkYellow
        return @()
    }
}

function Test-Model([string]$BaseUrl, [string]$AuthMode, [string]$Key, [string]$Model) {
    $body = @{
        model = $Model
        max_tokens = 8
        messages = @(@{ role = 'user'; content = 'Reply with OK only.' })
    } | ConvertTo-Json -Depth 6

    try {
        $r = Invoke-RestMethod -Method Post -Uri (Endpoint $BaseUrl 'messages') -Headers (Build-Headers $AuthMode $Key $true) -Body $body -TimeoutSec 35
        $txt = ''
        if ($null -ne $r.content) {
            $x = @($r.content | Where-Object { $_.type -eq 'text' } | Select-Object -First 1)
            if ($x.Count -gt 0) { $txt = [string]$x[0].text }
        }
        return [pscustomobject]@{ Ok = $true; Message = $(if ($txt) { "OK: $txt" } else { '接口正常' }) }
    } catch {
        $msg = $_.Exception.Message
        try { if ($_.ErrorDetails.Message) { $msg = $_.ErrorDetails.Message } } catch {}
        return [pscustomobject]@{ Ok = $false; Message = $msg }
    }
}

function Scan-AllModels($State, $Profile, [string]$Key, $Models) {
    Write-Host ''
    Write-Host '批量检测会给每个模型发送一个极小 API 请求，可能产生少量费用。' -ForegroundColor Yellow
    $c = Read-Host '确认检测全部模型？[y/N]'
    if ($c -notmatch '^[Yy]$') { return }

    foreach ($m in $Models) {
        Write-Host ("测试 {0} ... " -f $m) -NoNewline
        $t = Test-Model $Profile.BaseUrl $Profile.AuthMode $Key $m
        Set-ModelStatus $State $Profile.Id $m $t.Ok $t.Message
        if ($t.Ok) { Write-Host '可用' -ForegroundColor Green }
        else { Write-Host '不可用' -ForegroundColor Red }
    }
    Pause-Launcher
}

function Resolve-ClaudeCommand($Settings) {
    if (-not [string]::IsNullOrWhiteSpace([string]$Settings.claude_path)) {
        $configured = [string]$Settings.claude_path
        if (Test-Path $configured) { return $configured }
    }

    $cmd = Get-Command claude -ErrorAction SilentlyContinue
    if ($cmd) {
        if ($cmd.Path) { return $cmd.Path }
        if ($cmd.Source) { return $cmd.Source }
    }
    return $null
}

function Show-ClaudeInstallHelp {
    Write-Host ''
    Write-Host '未检测到 Claude Code。Public Edition 不会自动下载安装软件。' -ForegroundColor Yellow
    Write-Host '官方推荐的 Windows 安装方式之一：' -ForegroundColor Cyan
    Write-Host '  PowerShell:  irm https://claude.ai/install.ps1 | iex'
    Write-Host '  WinGet:      winget install Anthropic.ClaudeCode'
    Write-Host '安装后请重新打开启动器，并运行：claude --version' -ForegroundColor DarkGray
    Write-Host '官方文档：https://code.claude.com/docs/en/setup' -ForegroundColor DarkGray
}

function Environment-Menu($Settings) {
    while ($true) {
        Write-Title
        Write-Host '环境检查 / Settings' -ForegroundColor Green
        Write-Host ''

        Write-Host ("Windows PowerShell：{0}" -f $PSVersionTable.PSVersion)

        $claude = Resolve-ClaudeCommand $Settings
        if ($claude) {
            try {
                $ver = (& $claude --version 2>&1 | Select-Object -First 1)
                Write-Host "Claude Code：OK - $ver" -ForegroundColor Green
                Write-Host "路径：$claude" -ForegroundColor DarkGray
            } catch {
                Write-Host "Claude Code：发现命令，但版本检测失败 - $claude" -ForegroundColor Yellow
            }
        } else {
            Write-Host 'Claude Code：未检测到' -ForegroundColor Red
            Show-ClaudeInstallHelp
        }

        $wt = Get-Command wt.exe -ErrorAction SilentlyContinue
        Write-Host ("Windows Terminal：{0}" -f $(if ($wt) { '已安装（可选）' } else { '未检测到（可选，不影响使用）' }))

        $git = Get-Command git.exe -ErrorAction SilentlyContinue
        Write-Host ("Git for Windows：{0}" -f $(if ($git) { '已安装（可选）' } else { '未检测到（可选）' }))
        Write-Host "默认项目根目录：$($Settings.projects_root)"
        Write-Host "用户数据目录：$DataRoot" -ForegroundColor DarkGray

        Write-Host ''
        Write-Host '  C. 设置/修改 Claude 可执行文件路径'
        Write-Host '  R. 恢复 Claude 自动检测'
        Write-Host '  P. 修改默认项目根目录'
        Write-Host '  B. 返回'
        Write-Host ''

        $c = Read-Host '请选择'
        if ($c -match '^[Bb]$') { return }

        if ($c -match '^[Cc]$') {
            $path = (Read-Host '输入 claude.exe / claude.cmd 的完整路径').Trim()
            if (-not (Test-Path $path)) {
                Write-Host '文件不存在。' -ForegroundColor Red
                Pause-Launcher
                continue
            }
            $Settings.claude_path = $path
            Save-Settings $Settings
            continue
        }

        if ($c -match '^[Rr]$') {
            $Settings.claude_path = ''
            Save-Settings $Settings
            continue
        }

        if ($c -match '^[Pp]$') {
            $path = (Read-Host "新的项目根目录（当前：$($Settings.projects_root)）").Trim()
            if (-not [string]::IsNullOrWhiteSpace($path)) {
                if (-not [IO.Path]::IsPathRooted($path)) {
                    Write-Host '必须使用完整路径。' -ForegroundColor Red
                    Pause-Launcher
                    continue
                }
                $Settings.projects_root = $path
                Save-Settings $Settings
            }
            continue
        }
    }
}

function Ensure-FirstRun($Settings) {
    if ([bool]$Settings.first_run_completed) { return }

    Write-Title
    Write-Host '首次使用向导 / First-run wizard' -ForegroundColor Green
    Write-Host ''
    Write-Host '这是第三方本地启动辅助工具，不是 Anthropic 官方产品。' -ForegroundColor Yellow
    Write-Host '它不会附带 Claude Code，也不会绕过任何订阅、计费、地区或服务条款限制。' -ForegroundColor Yellow
    Write-Host ''

    $claude = Resolve-ClaudeCommand $Settings
    if ($claude) {
        try {
            $ver = (& $claude --version 2>&1 | Select-Object -First 1)
            Write-Host "Claude Code：已检测到 - $ver" -ForegroundColor Green
        } catch {
            Write-Host 'Claude Code：已检测到命令，但版本读取失败。' -ForegroundColor Yellow
        }
    } else {
        Show-ClaudeInstallHelp
    }

    Write-Host ''
    $defaultRoot = [string]$Settings.projects_root
    $projectRoot = (Read-Host "默认项目根目录（直接 Enter 使用 $defaultRoot）").Trim()
    if (-not [string]::IsNullOrWhiteSpace($projectRoot)) {
        if (-not [IO.Path]::IsPathRooted($projectRoot)) { throw '项目根目录必须是完整路径。' }
        $Settings.projects_root = $projectRoot
    }

    if (-not (Test-Path $Settings.projects_root)) {
        $create = Read-Host '项目根目录不存在，是否创建？[Y/n]'
        if ($create -notmatch '^[Nn]$') {
            New-Item -ItemType Directory -Path $Settings.projects_root -Force | Out-Null
        }
    }

    $Settings.first_run_completed = $true
    Save-Settings $Settings

    Write-Host ''
    Write-Host '首次设置完成。线路/API Key 请在主菜单由使用者本人添加。' -ForegroundColor Green
    Pause-Launcher
}

function Select-Project($Settings, $State, [string]$ProfileId, [string]$PresetProject = '') {
    if (-not [string]::IsNullOrWhiteSpace($PresetProject) -and (Test-Path $PresetProject)) {
        return $PresetProject
    }

    $sel = @(Get-LastSelection $State $ProfileId)
    $default = [string]$Settings.projects_root
    if ($sel.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$sel[0].project)) {
        $default = [string]$sel[0].project
    } elseif (-not [string]::IsNullOrWhiteSpace([string]$State.last_project)) {
        $default = [string]$State.last_project
    }

    Write-Host ''
    $store = Load-Projects
    $shortcuts = @($store.projects | Where-Object {
        -not [string]::IsNullOrWhiteSpace([string]$_.name) -and
        -not [string]::IsNullOrWhiteSpace([string]$_.path) -and
        [IO.Path]::IsPathRooted([string]$_.path)
    })

    if ($shortcuts.Count -gt 0) {
        Write-Host '项目快捷入口：' -ForegroundColor Cyan
        for ($i = 0; $i -lt $shortcuts.Count; $i++) {
            Write-Host ("  P{0}. {1} -> {2}" -f ($i + 1), $shortcuts[$i].name, $shortcuts[$i].path)
        }
        Write-Host ''
    }

    $recent = @($State.recent_projects)
    if ($recent.Count -gt 0) {
        Write-Host '最近项目：' -ForegroundColor DarkCyan
        for ($i = 0; $i -lt $recent.Count; $i++) {
            Write-Host ("  R{0}. {1}" -f ($i + 1), $recent[$i])
        }
        Write-Host ''
    }

    $v = Read-Host "项目目录（Enter 使用 $default；可输入 P1/R1 或直接路径）"
    if ([string]::IsNullOrWhiteSpace($v)) {
        $project = $default
    } elseif ($v -match '^[Pp](\d+)$') {
        $n = [int]$Matches[1]
        if ($n -lt 1 -or $n -gt $shortcuts.Count) { throw '项目快捷入口序号无效。' }
        $project = [string]$shortcuts[$n - 1].path
    } elseif ($v -match '^[Rr](\d+)$') {
        $n = [int]$Matches[1]
        if ($n -lt 1 -or $n -gt $recent.Count) { throw '最近项目序号无效。' }
        $project = [string]$recent[$n - 1]
    } else {
        $project = $v.Trim()
    }

    if (-not [IO.Path]::IsPathRooted($project)) { throw '项目路径必须是完整路径。' }

    if (-not (Test-Path $project)) {
        $c = Read-Host '目录不存在，创建？[Y/n]'
        if ($c -match '^[Nn]$') { return $null }
        New-Item -ItemType Directory -Path $project -Force | Out-Null
    }
    return $project
}

$TouchedEnv = @(
    'ANTHROPIC_BASE_URL',
    'ANTHROPIC_AUTH_TOKEN',
    'ANTHROPIC_API_KEY',
    'ANTHROPIC_MODEL',
    'ANTHROPIC_DEFAULT_FABLE_MODEL',
    'ANTHROPIC_DEFAULT_FABLE_MODEL_NAME',
    'ANTHROPIC_DEFAULT_HAIKU_MODEL',
    'ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME',
    'ANTHROPIC_DEFAULT_SONNET_MODEL',
    'ANTHROPIC_DEFAULT_SONNET_MODEL_NAME',
    'ANTHROPIC_DEFAULT_OPUS_MODEL',
    'ANTHROPIC_DEFAULT_OPUS_MODEL_NAME',
    'ANTHROPIC_CUSTOM_MODEL_OPTION',
    'ANTHROPIC_CUSTOM_MODEL_OPTION_NAME',
    'CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC'
)

function Get-EnvSnapshot {
    $snap = @{}
    foreach ($name in $TouchedEnv) {
        $exists = Test-Path ("Env:" + $name)
        $value = [Environment]::GetEnvironmentVariable($name, 'Process')
        $snap[$name] = [pscustomobject]@{ Exists = $exists; Value = $value }
    }
    return $snap
}

function Restore-EnvSnapshot($Snapshot) {
    foreach ($name in $TouchedEnv) {
        $entry = $Snapshot[$name]
        if ($entry.Exists) { Set-Item -Path ("Env:" + $name) -Value $entry.Value }
        else { Remove-Item -Path ("Env:" + $name) -ErrorAction SilentlyContinue }
    }
}

function Clear-RouteEnv {
    foreach ($name in $TouchedEnv) {
        Remove-Item -Path ("Env:" + $name) -ErrorAction SilentlyContinue
    }
}

function Configure-ModelFamily([string]$Model) {
    if ($Model -match '(?i)fable') {
        $env:ANTHROPIC_DEFAULT_FABLE_MODEL = $Model
        $env:ANTHROPIC_DEFAULT_FABLE_MODEL_NAME = $Model
        return 'fable'
    }
    if ($Model -match '(?i)haiku') {
        $env:ANTHROPIC_DEFAULT_HAIKU_MODEL = $Model
        $env:ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME = $Model
        return 'haiku'
    }
    if ($Model -match '(?i)sonnet') {
        $env:ANTHROPIC_DEFAULT_SONNET_MODEL = $Model
        $env:ANTHROPIC_DEFAULT_SONNET_MODEL_NAME = $Model
        return 'sonnet'
    }
    if ($Model -match '(?i)opus') {
        $env:ANTHROPIC_DEFAULT_OPUS_MODEL = $Model
        $env:ANTHROPIC_DEFAULT_OPUS_MODEL_NAME = $Model
        return 'opus'
    }

    $env:ANTHROPIC_CUSTOM_MODEL_OPTION = $Model
    $env:ANTHROPIC_CUSTOM_MODEL_OPTION_NAME = $Model
    return $Model
}

function Launch-RouteClaude($Settings, $State, $Profile, [string]$Model, [string]$Project, [string]$Key) {
    $claude = Resolve-ClaudeCommand $Settings
    if (-not $claude) {
        Show-ClaudeInstallHelp
        Pause-Launcher
        return
    }

    $snapshot = Get-EnvSnapshot
    try {
        Clear-RouteEnv
        $env:ANTHROPIC_BASE_URL = Normalize-BaseUrl $Profile.BaseUrl
        $env:ANTHROPIC_MODEL = $Model
        $env:CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = '1'

        if ($Profile.AuthMode -eq 'api_key') {
            $env:ANTHROPIC_API_KEY = $Key
        } else {
            $env:ANTHROPIC_AUTH_TOKEN = $Key
        }

        $launchModel = Configure-ModelFamily $Model
        Set-LastSelection $State $Profile.Id $Model $Project

        Write-Host ''
        Write-Host '正在启动 Claude Code...' -ForegroundColor Green
        Write-Host "线路：$($Profile.Name)"
        Write-Host "模型：$Model"
        Write-Host "项目：$Project"
        Write-Host ''

        Push-Location $Project
        try { & $claude --model $launchModel }
        finally { Pop-Location }
    } finally {
        Restore-EnvSnapshot $snapshot
    }
}

function Launch-OfficialClaude($Settings, [string]$Project) {
    $claude = Resolve-ClaudeCommand $Settings
    if (-not $claude) {
        Show-ClaudeInstallHelp
        Pause-Launcher
        return
    }

    $snapshot = Get-EnvSnapshot
    try {
        Clear-RouteEnv
        Write-Host ''
        Write-Host '正在使用 Claude Code 默认/官方认证启动...' -ForegroundColor Green
        Write-Host "项目：$Project"
        Write-Host ''
        Push-Location $Project
        try { & $claude }
        finally { Pop-Location }
    } finally {
        Restore-EnvSnapshot $snapshot
    }
}

function Start-WithProfile($Settings, $State, $Profile, [string]$PresetModel = '', [string]$PresetProject = '') {
    $key = Read-EncryptedSecret $Profile.SecretFile
    try {
        $models = @(Get-Models $Profile.BaseUrl $Profile.AuthMode $key)
        $model = $PresetModel

        if (-not [string]::IsNullOrWhiteSpace($model)) {
            Write-Title
            Write-Host "快速启动：$($Profile.Name) / $model" -ForegroundColor Green
            Write-Host '正在实时确认模型可用性...'
            $t = Test-Model $Profile.BaseUrl $Profile.AuthMode $key $model
            Set-ModelStatus $State $Profile.Id $model $t.Ok $t.Message
            if (-not $t.Ok) {
                Write-Host '上次模型当前不可用，将进入模型选择。' -ForegroundColor Yellow
                $model = ''
                Pause-Launcher
            }
        }

        while ([string]::IsNullOrWhiteSpace($model)) {
            Write-Title
            Write-Host "当前线路：$($Profile.Name)" -ForegroundColor Green
            Write-Host "Base URL：$($Profile.BaseUrl)"
            Write-Host ''

            if ($models.Count -eq 0) {
                $model = (Read-Host '请输入模型 ID（输入 B 返回）').Trim()
                if ($model -match '^[Bb]$') { return }
                break
            }

            for ($i = 0; $i -lt $models.Count; $i++) {
                $label = Get-StatusLabel $State $Profile.Id $models[$i]
                Write-Host ("  {0}. {1}  {2}" -f ($i + 1), $models[$i], $label)
            }
            Write-Host ''
            Write-Host '  S. 批量检测全部模型（会产生少量 API 调用）'
            Write-Host '  0. 手动输入模型 ID'
            Write-Host '  B. 返回线路选择'

            $c = Read-Host '请选择模型'
            if ($c -match '^[Bb]$') { return }
            if ($c -match '^[Ss]$') {
                Scan-AllModels $State $Profile $key $models
                continue
            }

            if ($c -eq '0') {
                $candidate = (Read-Host '模型 ID').Trim()
            } else {
                $n = 0
                if (-not [int]::TryParse($c, [ref]$n) -or $n -lt 1 -or $n -gt $models.Count) {
                    Write-Host '选择无效。' -ForegroundColor Red
                    Pause-Launcher
                    continue
                }
                $candidate = $models[$n - 1]
            }

            Write-Host ''
            Write-Host "快速检测 $candidate ..." -ForegroundColor Cyan
            $t = Test-Model $Profile.BaseUrl $Profile.AuthMode $key $candidate
            Set-ModelStatus $State $Profile.Id $candidate $t.Ok $t.Message
            if ($t.Ok) {
                Write-Host "可用：$($t.Message)" -ForegroundColor Green
                $model = $candidate
            } else {
                Write-Host '不可用：' -ForegroundColor Red
                Write-Host $t.Message -ForegroundColor Yellow
                Pause-Launcher
            }
        }

        $project = Select-Project $Settings $State $Profile.Id $PresetProject
        if ($null -eq $project) { return }
        Launch-RouteClaude $Settings $State $Profile $model $project $key
    } finally {
        $key = $null
        [GC]::Collect()
    }
}

function Get-ValidProjectShortcuts {
    $store = Load-Projects
    return @($store.projects | Where-Object {
        -not [string]::IsNullOrWhiteSpace([string]$_.name) -and
        -not [string]::IsNullOrWhiteSpace([string]$_.path) -and
        [IO.Path]::IsPathRooted([string]$_.path)
    })
}

function Start-ProjectShortcut($Settings, $State, $Profiles, $Shortcut) {
    $profile = $null
    $selection = $null

    if (-not [string]::IsNullOrWhiteSpace([string]$State.last_profile_id)) {
        $p = @($Profiles | Where-Object { $_.Id -eq $State.last_profile_id } | Select-Object -First 1)
        if ($p.Count -gt 0) {
            $profile = $p[0]
            $s = @(Get-LastSelection $State $profile.Id)
            if ($s.Count -gt 0) { $selection = $s[0] }
        }
    }

    if ($null -eq $profile -or $null -eq $selection) {
        Write-Title
        Write-Host "项目快捷启动：$($Shortcut.name)" -ForegroundColor Green
        Write-Host ''
        $profile = Choose-Profile '请选择 API 线路'
        if ($null -eq $profile) { return }
        Start-WithProfile $Settings $State $profile '' $Shortcut.path
        return
    }

    Start-WithProfile $Settings $State $profile ([string]$selection.model) $Shortcut.path
}

function Switch-Model-And-Start($Settings, $State, $Profiles) {
    $profile = $null
    if (-not [string]::IsNullOrWhiteSpace([string]$State.last_profile_id)) {
        $p = @($Profiles | Where-Object { $_.Id -eq $State.last_profile_id } | Select-Object -First 1)
        if ($p.Count -gt 0) { $profile = $p[0] }
    }
    if ($null -eq $profile) {
        Write-Title
        $profile = Choose-Profile '请选择 API 线路'
        if ($null -eq $profile) { return }
    }
    Start-WithProfile $Settings $State $profile '' ([string]$State.last_project)
}

function Start-OfficialMode($Settings, $State) {
    $default = [string]$Settings.projects_root
    if (-not [string]::IsNullOrWhiteSpace([string]$State.last_project)) { $default = [string]$State.last_project }
    $project = (Read-Host "项目目录（直接 Enter 使用 $default）").Trim()
    if ([string]::IsNullOrWhiteSpace($project)) { $project = $default }
    if (-not [IO.Path]::IsPathRooted($project)) { throw '项目路径必须是完整路径。' }
    if (-not (Test-Path $project)) {
        $c = Read-Host '目录不存在，创建？[Y/n]'
        if ($c -match '^[Nn]$') { return }
        New-Item -ItemType Directory -Path $project -Force | Out-Null
    }
    $State.last_project = $project
    Save-State $State
    Launch-OfficialClaude $Settings $project
}

$Settings = Load-Settings
Ensure-FirstRun $Settings

while ($true) {
    $Settings = Load-Settings
    $State = Load-State
    $profiles = @(Get-ProfileEntries)

    Write-Title
    if ($profiles.Count -gt 0) {
        Write-Host 'API 线路：' -ForegroundColor Green
        for ($i = 0; $i -lt $profiles.Count; $i++) {
            Write-Host ("  {0}. {1} [{2}]" -f ($i + 1), $profiles[$i].Name, $profiles[$i].BaseUrl)
        }
        Write-Host ''
    } else {
        Write-Host '尚未添加 API 线路。可以使用 O 直接进入 Claude 官方/默认认证，或添加自己的 API 线路。' -ForegroundColor Yellow
        Write-Host ''
    }

    $quickProfile = $null
    $quickSelection = $null
    if (-not [string]::IsNullOrWhiteSpace([string]$State.last_profile_id)) {
        $p = @($profiles | Where-Object { $_.Id -eq $State.last_profile_id } | Select-Object -First 1)
        if ($p.Count -gt 0) {
            $quickProfile = $p[0]
            $s = @(Get-LastSelection $State $quickProfile.Id)
            if ($s.Count -gt 0) { $quickSelection = $s[0] }
        }
    }

    if ($null -ne $quickProfile -and $null -ne $quickSelection) {
        Write-Host ("  Enter. 快速启动：{0} / {1} / {2}" -f $quickProfile.Name, $quickSelection.model, $quickSelection.project) -ForegroundColor Cyan
    }

    $projectShortcuts = @(Get-ValidProjectShortcuts)
    if ($projectShortcuts.Count -gt 0) {
        Write-Host ''
        Write-Host '项目快捷启动：' -ForegroundColor Magenta
        for ($i = 0; $i -lt $projectShortcuts.Count; $i++) {
            Write-Host ("  P{0}. {1} -> {2}" -f ($i + 1), $projectShortcuts[$i].name, $projectShortcuts[$i].path)
        }
    }

    Write-Host ''
    Write-Host '  O. 官方/默认认证启动（不使用网关 Key）'
    Write-Host '  M. 切换模型并启动（使用最近 API 线路）'
    Write-Host '  J. 一键导入 New API JSON'
    Write-Host '  A. 手动新增 API 线路'
    Write-Host '  K. 更新线路 API Key'
    Write-Host '  E. 编辑线路地址/认证'
    Write-Host '  P. 管理项目快捷入口'
    Write-Host '  C. 环境检查/设置'
    Write-Host '  D. 删除线路'
    Write-Host '  Q. 退出'
    Write-Host ''

    $choice = Read-Host '请选择'

    if ([string]::IsNullOrWhiteSpace($choice) -and $null -ne $quickProfile -and $null -ne $quickSelection) {
        try { Start-WithProfile $Settings $State $quickProfile ([string]$quickSelection.model) ([string]$quickSelection.project) }
        catch { Write-Host "启动失败：$($_.Exception.Message)" -ForegroundColor Red; Pause-Launcher }
        continue
    }

    if ($choice -match '^[Pp](\d+)$') {
        $pn = [int]$Matches[1]
        if ($pn -ge 1 -and $pn -le $projectShortcuts.Count) {
            try { Start-ProjectShortcut $Settings $State $profiles $projectShortcuts[$pn - 1] }
            catch { Write-Host "项目快捷启动失败：$($_.Exception.Message)" -ForegroundColor Red; Pause-Launcher }
        } else {
            Write-Host '项目快捷入口序号无效。' -ForegroundColor Red
            Pause-Launcher
        }
        continue
    }

    if ($choice -match '^[Qq]$') { break }
    if ($choice -match '^[Oo]$') { try { Start-OfficialMode $Settings $State } catch { Write-Host $_.Exception.Message -ForegroundColor Red; Pause-Launcher }; continue }
    if ($choice -match '^[Mm]$') { try { Switch-Model-And-Start $Settings $State $profiles } catch { Write-Host $_.Exception.Message -ForegroundColor Red; Pause-Launcher }; continue }
    if ($choice -match '^[Jj]$') { try { Import-NewApiJson } catch { Write-Host $_.Exception.Message -ForegroundColor Red; Pause-Launcher }; continue }
    if ($choice -match '^[Aa]$') { try { Add-Profile } catch { Write-Host $_.Exception.Message -ForegroundColor Red; Pause-Launcher }; continue }
    if ($choice -match '^[Kk]$') { try { Update-Key } catch { Write-Host $_.Exception.Message -ForegroundColor Red; Pause-Launcher }; continue }
    if ($choice -match '^[Ee]$') { try { Edit-Profile } catch { Write-Host $_.Exception.Message -ForegroundColor Red; Pause-Launcher }; continue }
    if ($choice -match '^[Pp]$') { try { Manage-Projects $Settings } catch { Write-Host $_.Exception.Message -ForegroundColor Red; Pause-Launcher }; continue }
    if ($choice -match '^[Cc]$') { try { Environment-Menu $Settings } catch { Write-Host $_.Exception.Message -ForegroundColor Red; Pause-Launcher }; continue }
    if ($choice -match '^[Dd]$') { try { Remove-Profile } catch { Write-Host $_.Exception.Message -ForegroundColor Red; Pause-Launcher }; continue }

    $n = 0
    if ([int]::TryParse($choice, [ref]$n) -and $n -ge 1 -and $n -le $profiles.Count) {
        try { Start-WithProfile $Settings $State $profiles[$n - 1] }
        catch { Write-Host "启动失败：$($_.Exception.Message)" -ForegroundColor Red; Pause-Launcher }
    } else {
        Write-Host '选择无效。' -ForegroundColor Red
        Pause-Launcher
    }
}
