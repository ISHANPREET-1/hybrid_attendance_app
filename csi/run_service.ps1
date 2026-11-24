<#
.SYNOPSIS
  Set up and run the CSI processing service on the classroom laptop (guide Step 44).

  powershell -ExecutionPolicy Bypass -File csi\run_service.ps1            # live, restarts on crash
  powershell -ExecutionPolicy Bypass -File csi\run_service.ps1 -Setup     # create venv + install only
  powershell -ExecutionPolicy Bypass -File csi\run_service.ps1 -DryRun    # print results, do not post

  Reads settings from csi\.env (copy csi\.env.example). Logs: csi\logs\csi_service.log
  Stop with Ctrl+C. Close "idf.py monitor" first: only one program can use COM3.
#>
param([switch]$Setup, [switch]$DryRun)
$ErrorActionPreference = 'Stop'
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Venv = Join-Path $Here 'venv'
$Py = Join-Path $Venv 'Scripts\python.exe'
Set-Location $Here

if (-not (Test-Path $Py)) {
  python -m venv $Venv
}
& $Py -m pip install --quiet --upgrade pip
& $Py -m pip install --quiet -r requirements.txt
if ($Setup) { Write-Host "Environment ready: $Py"; exit 0 }

if (-not (Test-Path '.env')) {
  Copy-Item '.env.example' '.env'
  throw 'Created csi\.env. Fill BACKEND_URL and CSI_SERVICE_TOKEN, then re-run.'
}
if (-not (Test-Path 'models\presence.joblib')) {
  throw 'No trained model. Record data (attendance_csi.record) and train (attendance_csi.train) first. See csi\README.md.'
}

$ServiceArgs = @('-m', 'attendance_csi.service')
if ($DryRun) { $ServiceArgs += '--dry-run' }
while ($true) {
  & $Py @ServiceArgs
  $code = $LASTEXITCODE
  if ($code -eq 0) { break }
  Write-Warning "CSI service exited with code $code; restarting in 5 seconds (Ctrl+C to stop)."
  Start-Sleep -Seconds 5
}
