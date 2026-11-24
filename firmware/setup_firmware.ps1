<#
.SYNOPSIS
  Build, flash and monitor the ESP32 CSI firmware for Hybrid Attendance (guide Steps 4-9).

.DESCRIPTION
  Run inside the "ESP-IDF 6.1 PowerShell" (so idf.py is on PATH), from the repository root:

    powershell -ExecutionPolicy Bypass -File firmware\setup_firmware.ps1 -Action all -Port COM3

  1. Clones Espressif's esp-csi at a pinned commit into firmware\.esp-csi (once).
  2. Uses examples\get-started\csi_recv_router unchanged, layering our settings on top:
       sdkconfig.defaults (example) -> firmware\sdkconfig.attendance -> firmware\sdkconfig.wifi
  3. set-target esp32, build, flash, monitor. Build/flash output is saved to firmware\logs\
     as evidence for the phase report.

  The build downloads the esp_csi_gain_ctrl component from components.espressif.com,
  so the laptop needs internet access for the first build.

.PARAMETER Action
  build | flash | monitor | all (build + flash + monitor)
.PARAMETER Clean
  Delete the previous sdkconfig/build so changed defaults or Wi-Fi credentials take effect.
#>
param(
  [ValidateSet('build', 'flash', 'monitor', 'all')] [string]$Action = 'all',
  [string]$Port = 'COM3',
  [string]$Target = 'esp32',
  [switch]$Clean
)
$ErrorActionPreference = 'Stop'
$EspCsiCommit = '8633d67152db2808f141cc1595970aa9cf406045'   # esp-csi master, 2026-04-22
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Src = Join-Path $Here '.esp-csi'
$Project = Join-Path $Src 'examples\get-started\csi_recv_router'
$Overlay = Join-Path $Here 'sdkconfig.attendance'
$Wifi = Join-Path $Here 'sdkconfig.wifi'
$Logs = Join-Path $Here 'logs'
New-Item -ItemType Directory -Force -Path $Logs | Out-Null

if (-not (Get-Command idf.py -ErrorAction SilentlyContinue)) {
  throw 'idf.py not found. Open the "ESP-IDF 6.1 PowerShell" (or run export.ps1) first.'
}
idf.py --version
if (-not (Test-Path $Wifi)) {
  Copy-Item (Join-Path $Here 'sdkconfig.wifi.example') $Wifi
  throw "Created $Wifi. Edit it with the attendance Wi-Fi SSID and password, then re-run."
}
if ((Get-Content $Wifi -Raw) -match 'change-me') {
  throw "Set the real Wi-Fi password in $Wifi first."
}

if (-not (Test-Path $Project)) {
  git clone https://github.com/espressif/esp-csi.git $Src
  git -C $Src checkout $EspCsiCommit
}
$Defaults = "sdkconfig.defaults;$($Overlay -replace '\\','/');$($Wifi -replace '\\','/')"

Push-Location $Project
try {
  if ($Clean -or -not (Test-Path 'sdkconfig')) {
    Remove-Item -Force -ErrorAction SilentlyContinue 'sdkconfig'
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue 'build'
    idf.py -D "SDKCONFIG_DEFAULTS=$Defaults" set-target $Target
  }
  $Stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
  if ($Action -in 'build', 'all') {
    idf.py -D "SDKCONFIG_DEFAULTS=$Defaults" build 2>&1 | Tee-Object -FilePath (Join-Path $Logs "build_$Stamp.log")
    if ($LASTEXITCODE -ne 0) { throw 'Build failed. Read the FIRST error in the log (docs/HARDWARE_SETUP.md, Troubleshooting).' }
    # Show the effective settings that matter, for the phase report.
    Select-String -Path 'sdkconfig' -Pattern 'CONFIG_ESP_WIFI_CSI_ENABLED|CONFIG_ESP_CONSOLE_UART_BAUDRATE|CONFIG_EXAMPLE_WIFI_SSID|CONFIG_EXAMPLE_WIFI_CONN_MAX_RETRY'
  }
  if ($Action -in 'flash', 'all') {
    Write-Host "Flashing on $Port. If it waits at 'Connecting...', hold BOOT until writing starts."
    idf.py -p $Port flash 2>&1 | Tee-Object -FilePath (Join-Path $Logs "flash_$Stamp.log")
    if ($LASTEXITCODE -ne 0) { throw "Flash failed. Close any program using $Port (idf.py monitor, the CSI service) and retry." }
  }
  if ($Action -in 'monitor', 'all') {
    Write-Host 'Expect "got ip:" then CSI_DATA lines. Exit with Ctrl+]. Close the monitor before running the Python collector.'
    idf.py -p $Port monitor
  }
} finally {
  Pop-Location
}
