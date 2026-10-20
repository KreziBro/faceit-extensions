[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Host.UI.RawUI.WindowTitle = "FACEIT Extensions Installer"

$ESC = [char]27
$C_ORANGE = "$ESC[38;2;255;85;0m"
$C_GREEN = "$ESC[38;2;0;179;89m"
$C_RED = "$ESC[38;2;220;60;60m"
$C_GRAY = "$ESC[38;2;150;150;160m"
$C_WHITE = "$ESC[38;2;255;255;255m"
$C_RESET = "$ESC[0m"

function Write-FaceitBanner {
    Write-Host ""
    Write-Host "  ${C_ORANGE}███████╗ █████╗  ██████╗███████╗██╗████████╗${C_RESET}"
    Write-Host "  ${C_ORANGE}██╔════╝██╔══██╗██╔════╝██╔════╝██║╚══██╔══╝${C_RESET}"
    Write-Host "  ${C_ORANGE}█████╗  ███████║██║     █████╗  ██║   ██║   ${C_WHITE}EXTENSIONS${C_RESET}"
    Write-Host "  ${C_ORANGE}██╔══╝  ██╔══██║██║     ██╔══╝  ██║   ██║   ${C_GRAY}v1.0.0${C_RESET}"
    Write-Host "  ${C_ORANGE}██║     ██║  ██║╚██████╗███████╗██║   ██║   ${C_RESET}"
    Write-Host "  ${C_ORANGE}╚═╝     ╚═╝  ╚═╝ ╚═════╝╚══════╝╚═╝   ╚═╝   ${C_RESET}"
    Write-Host ""
    Write-Host "  ${C_GRAY}Установка нативных модулей расширений для клиента FACEIT${C_RESET}"
    Write-Host ""
}

function Write-Step {
    param([string]$Message)
    Write-Host "  ${C_ORANGE}[>]${C_RESET} ${C_WHITE}$Message${C_RESET}"
}

function Write-Success {
    param([string]$Message)
    Write-Host "  ${C_GREEN}[OK]${C_RESET} ${C_GREEN}$Message${C_RESET}"
}

function Write-Failure {
    param([string]$Message)
    Write-Host "  ${C_RED}[FAIL]${C_RESET} ${C_RED}$Message${C_RESET}"
}

Write-FaceitBanner

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
if (-not $ScriptRoot) { $ScriptRoot = Get-Location }

function Find-FaceitDirectory {
    $Candidates = [System.Collections.Generic.List[string]]::new()
    try {
        $Proc = Get-Process -Name "FACEIT" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($Proc -and $Proc.Path) {
            $Candidate = Split-Path -Parent (Split-Path -Parent $Proc.Path)
            if ($Candidate) { $Candidates.Add($Candidate) }
        }
    } catch {}

    if ($env:LOCALAPPDATA) {
        $Candidates.Add((Join-Path $env:LOCALAPPDATA "FACEIT"))
    }

    if ($env:USERPROFILE) {
        $Candidates.Add((Join-Path $env:USERPROFILE "AppData\Local\FACEIT"))
    } elseif ($HOME) {
        $Candidates.Add((Join-Path $HOME "AppData\Local\FACEIT"))
    }

    try {
        $RegKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\FACEIT"
        if (Test-Path $RegKey) {
            $Loc = (Get-ItemProperty -Path $RegKey -Name "InstallLocation" -ErrorAction SilentlyContinue).InstallLocation
            if ($Loc) { $Candidates.Add($Loc) }
        }
    } catch {}

    if ($env:ProgramFiles) {
        $Candidates.Add((Join-Path $env:ProgramFiles "FACEIT"))
    }
    if (${env:ProgramFiles(x86)}) {
        $Candidates.Add((Join-Path ${env:ProgramFiles(x86)} "FACEIT"))
    }

    try {
        $UserDirs = Get-ChildItem -Path "C:\Users" -Directory -ErrorAction SilentlyContinue
        foreach ($U in $UserDirs) {
            $Candidates.Add((Join-Path $U.FullName "AppData\Local\FACEIT"))
        }
    } catch {}

    foreach ($P in $Candidates) {
        if ([string]::IsNullOrWhiteSpace($P)) { continue }
        if (Test-Path $P) {
            $Apps = Get-ChildItem -Path $P -Directory -Filter "app-*" -ErrorAction SilentlyContinue
            if ($Apps -and $Apps.Count -gt 0) {
                return $P
            }
        }
    }
    return $null
}

$FaceitBase = Find-FaceitDirectory

if (-not $FaceitBase) {
    Write-Failure "Настольный клиент FACEIT не найден в системе."
    Write-Host "  Открываю страницу загрузки клиента: https://www.faceit.com/en/client" -ForegroundColor Yellow
    Start-Process "https://www.faceit.com/en/client"
    exit 1
}

$AvailableAppDirs = Get-ChildItem -Path $FaceitBase -Directory -Filter "app-*" | Sort-Object {
    try { [version]($_.Name -replace '^app-', '') } catch { $_.Name }
} -Descending

$TargetAppDir = $AvailableAppDirs[0].FullName
$ResourcesDir = Join-Path $TargetAppDir "resources"
$FaceitExecutable = Join-Path $TargetAppDir "FACEIT.exe"
$AsarArchive = Join-Path $ResourcesDir "app.asar"
$AsarBackupArchive = Join-Path $ResourcesDir "app.asar.backup"

Write-Step "Обнаружен каталог клиента FACEIT: $TargetAppDir"

if ($AvailableAppDirs.Count -gt 1) {
    for ($i = 1; $i -lt $AvailableAppDirs.Count; $i++) {
        $OldAppDir = $AvailableAppDirs[$i].FullName
        Write-Step "Удаление устаревшей папки версии: $($AvailableAppDirs[$i].Name)..."
        try {
            Remove-Item -Path $OldAppDir -Recurse -Force -ErrorAction SilentlyContinue
        } catch {}
    }
}

$ActiveInstances = Get-Process -Name "FACEIT" -ErrorAction SilentlyContinue
if ($ActiveInstances) {
    Write-Step "Завершение активных процессов FACEIT..."
    Stop-Process -Name "FACEIT" -Force -ErrorAction SilentlyContinue
    
    $Retries = 0
    while ((Get-Process -Name "FACEIT" -ErrorAction SilentlyContinue) -and ($Retries -lt 10)) {
        Start-Sleep -Milliseconds 500
        $Retries++
    }
}

$AlreadyInstalled = (Test-Path $AsarBackupArchive) -or (Test-Path (Join-Path $ResourcesDir "extensionLoader.js"))

if ($AlreadyInstalled) {
    Write-Host ""
    Write-Host "  [!] Faceit Extensions уже установлен в этом клиенте" -ForegroundColor Yellow
    $ReinstallPrompt = Read-Host "  Выполнить переустановку или обновление? (Y/n)"
    if (-not [string]::IsNullOrWhiteSpace($ReinstallPrompt) -and $ReinstallPrompt.Trim().ToLower() -eq 'n') {
        Write-Host "  Операция отменена. Выход." -ForegroundColor Gray
        exit 0
    }
    Write-Step "Обновление файлов Faceit Extensions..."
} else {
    Write-Step "Создание резервной копии app.asar.backup..."
    Copy-Item $AsarArchive $AsarBackupArchive -Force
}

Write-Step "Установка файлов загрузчика..."
$SourceComponents = Join-Path $ScriptRoot "src"
Copy-Item (Join-Path $SourceComponents "extensionLoader.js") (Join-Path $ResourcesDir "extensionLoader.js") -Force
Copy-Item (Join-Path $SourceComponents "extensionsManager.html") (Join-Path $ResourcesDir "extensionsManager.html") -Force
Copy-Item (Join-Path $SourceComponents "managerPreload.js") (Join-Path $ResourcesDir "managerPreload.js") -Force
if (Test-Path (Join-Path $SourceComponents "version.json")) {
    Copy-Item (Join-Path $SourceComponents "version.json") (Join-Path $ResourcesDir "version.json") -Force
}

Write-Step "Внедрение хука загрузчика в app.asar..."
$PatcherModule = Join-Path $ScriptRoot "src\patcher.js"

$env:ELECTRON_RUN_AS_NODE = "1"
$PatchProc = Start-Process -FilePath $FaceitExecutable -ArgumentList "`"$PatcherModule`"", "`"$AsarBackupArchive`"", "`"$AsarArchive`"" -Wait -PassThru -NoNewWindow
$env:ELECTRON_RUN_AS_NODE = $null

if ($PatchProc.ExitCode -ne 0) {
    Write-Failure "Ошибка патчинга с кодом $($PatchProc.ExitCode)"
    exit 1
}

$TargetExtensionsDir = Join-Path $FaceitBase "extensions"
if (-not (Test-Path $TargetExtensionsDir)) {
    New-Item -ItemType Directory -Path $TargetExtensionsDir -Force | Out-Null
}

$InstallScriptPath = Join-Path $ScriptRoot "src\Install-Extension.ps1"
Copy-Item $InstallScriptPath (Join-Path $TargetExtensionsDir "Install-Extension.ps1") -Force
if (Test-Path (Join-Path $ScriptRoot "version.json")) {
    Copy-Item (Join-Path $ScriptRoot "version.json") (Join-Path $TargetExtensionsDir "version.json") -Force
}

Write-Step "Развертывание предустановленных расширений..."
$BundledSource = Join-Path $ScriptRoot "extensions"
if (Test-Path $BundledSource) {
    Get-ChildItem -Path $BundledSource -Directory | ForEach-Object {
        $Dest = Join-Path $TargetExtensionsDir $_.Name
        if (-not (Test-Path $Dest)) {
            Copy-Item $_.FullName $Dest -Recurse -Force
        }
    }
}

$ConfigFile = Join-Path $TargetExtensionsDir "config.json"
if (-not (Test-Path $ConfigFile)) {
    $DefaultConfig = @{
        performanceMode = $true
        zoomFactor = 0.95
        disabledExtensions = @("repeek", "cpjienndjbobchlaklajagacpiepclek", "kodlabmmaalpolkfolgpahbjehalecki")
    }
    $DefaultConfig | ConvertTo-Json | Set-Content -Path $ConfigFile -Encoding UTF8
}

Write-Host ""
Write-Success "Faceit Extensions успешно установлен."
Write-Host ""
Write-Host "  Параметры и управление:" -ForegroundColor White
Write-Host "    Нажмите CTRL SHIFT E или кликните FACEIT EXTENSIONS в клиенте" -ForegroundColor Gray
Write-Host "    Встроенные дополнения: Repeek, Faceit UI Cleaner, VisusGG" -ForegroundColor Gray
Write-Host "    Масштаб интерфейса: CTRL Колесо мыши или кнопки в настройках" -ForegroundColor Gray
Write-Host "    Аппаратное ускорение GPU активно по умолчанию" -ForegroundColor Gray
Write-Host "    Консоль разработчика: F12" -ForegroundColor Gray
Write-Host ""

$Prompt = Read-Host "  Запустить клиент FACEIT сейчас? (Y/n)"
if ([string]::IsNullOrWhiteSpace($Prompt) -or $Prompt.Trim().ToLower() -eq 'y') {
    Start-Process (Join-Path $FaceitBase "FACEIT.exe")
}
