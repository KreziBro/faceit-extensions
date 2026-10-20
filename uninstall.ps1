[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Host.UI.RawUI.WindowTitle = "FACEIT Extensions Uninstaller"

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
    Write-Host "  ${C_ORANGE}█████╗  ███████║██║     █████╗  ██║   ██║   ${C_WHITE}UNINSTALLER${C_RESET}"
    Write-Host "  ${C_ORANGE}██╔══╝  ██╔══██║██║     ██╔══╝  ██║   ██║   ${C_GRAY}v1.0.0${C_RESET}"
    Write-Host "  ${C_ORANGE}██║     ██║  ██║╚██████╗███████╗██║   ██║   ${C_RESET}"
    Write-Host "  ${C_ORANGE}╚═╝     ╚═╝  ╚═╝ ╚═════╝╚══════╝╚═╝   ╚═╝   ${C_RESET}"
    Write-Host ""
    Write-Host "  ${C_GRAY}Восстановление оригинального состояния клиента FACEIT${C_RESET}"
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
    Write-Failure "Настольный клиент FACEIT не найден."
    exit 1
}

$AvailableAppDirs = Get-ChildItem -Path $FaceitBase -Directory -Filter "app-*" | Sort-Object {
    try { [version]($_.Name -replace '^app-', '') } catch { $_.Name }
} -Descending

$TargetAppDir = $AvailableAppDirs[0].FullName
$ResourcesDir = Join-Path $TargetAppDir "resources"
$AsarArchive = Join-Path $ResourcesDir "app.asar"
$AsarBackupArchive = Join-Path $ResourcesDir "app.asar.backup"

$ActiveInstances = Get-Process -Name "FACEIT" -ErrorAction SilentlyContinue
if ($ActiveInstances) {
    Write-Step "Остановка активных процессов FACEIT..."
    Stop-Process -Name "FACEIT" -Force -ErrorAction SilentlyContinue
    
    $Retries = 0
    while ((Get-Process -Name "FACEIT" -ErrorAction SilentlyContinue) -and ($Retries -lt 10)) {
        Start-Sleep -Milliseconds 500
        $Retries++
    }
}

if (Test-Path $AsarBackupArchive) {
    Write-Step "Восстановление оригинального app.asar из резервной копии..."
    Copy-Item $AsarBackupArchive $AsarArchive -Force
    Remove-Item $AsarBackupArchive -Force -ErrorAction SilentlyContinue
    Write-Success "Оригинальный app.asar успешно восстановлен."
} else {
    Write-Host "  [!] Резервная копия не найдена, app.asar оставлен без изменений." -ForegroundColor Yellow
}

Write-Step "Очистка установленных модулей расширений..."
Remove-Item (Join-Path $ResourcesDir "extensionLoader.js") -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $ResourcesDir "extensionsManager.html") -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $ResourcesDir "managerPreload.js") -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $ResourcesDir "version.json") -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Success "Удаление завершено. Клиент возвращен в заводское состояние."
Write-Host ""
