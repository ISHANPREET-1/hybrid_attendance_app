param([switch]$Background)

$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
if ($Background) {
    $logDirectory = Join-Path $PSScriptRoot '.tools'
    New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
    $appProcess = Start-Process -FilePath powershell.exe `
        -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" `
        -WorkingDirectory $PSScriptRoot -WindowStyle Hidden `
        -RedirectStandardOutput (Join-Path $logDirectory 'app.stdout.log') `
        -RedirectStandardError (Join-Path $logDirectory 'app.stderr.log') -PassThru
    $appProcess.Id | Set-Content (Join-Path $logDirectory 'app-process.pid')
    Write-Host 'Starting Hybrid Attendance at http://127.0.0.1:8080'
    Write-Host "Startup logs: $logDirectory\app.stdout.log and app.stderr.log"
    return
}
$flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
if ($flutterCommand) {
    $flutterPath = $flutterCommand.Source
} elseif (Test-Path -LiteralPath '.tools\flutter\bin\flutter.bat') {
    $flutterPath = Join-Path $PSScriptRoot '.tools\flutter\bin\flutter.bat'
} else {
    throw 'Flutter SDK was not found. Install Flutter and add its bin directory to PATH.'
}
# Dart native hooks on Windows can fail when the SDK executable path contains spaces.
if ($flutterPath.Contains(' ')) {
    $fileSystem = New-Object -ComObject Scripting.FileSystemObject
    $flutterPath = $fileSystem.GetFile($flutterPath).ShortPath
}
$previousWindows = $env:FLUTTER_WINDOWS
$previousLinux = $env:FLUTTER_LINUX
try {
    # This launcher targets web and does not require desktop plugin symlinks.
    $env:FLUTTER_WINDOWS = 'false'
    $env:FLUTTER_LINUX = 'false'
    & $flutterPath --no-version-check pub get
    if ($LASTEXITCODE -ne 0) { throw 'Flutter dependency installation failed.' }
    & $flutterPath --no-version-check run -d web-server --web-hostname 127.0.0.1 --web-port 8080
} finally {
    $env:FLUTTER_WINDOWS = $previousWindows
    $env:FLUTTER_LINUX = $previousLinux
}
