param([switch]$Background, [switch]$SkipBuild, [int]$Port = 8080)
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
$pythonCommand = Get-Command python -ErrorAction Stop
$logDirectory = Join-Path $PSScriptRoot '.tools'
New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
$venvPython = Join-Path $PSScriptRoot '.tools/venv/Scripts/python.exe'
if (-not (Test-Path -LiteralPath $venvPython)) {
    & $pythonCommand.Source -m venv .tools/venv
    if ($LASTEXITCODE -ne 0) { throw 'Could not create backend virtual environment.' }
}
& $venvPython -c "import sqlalchemy, psycopg, argon2, dotenv" 2>$null
if ($LASTEXITCODE -ne 0) {
    & $venvPython -m pip install -r requirements.txt
    if ($LASTEXITCODE -ne 0) { throw 'Backend dependency installation failed.' }
}
if (-not $SkipBuild) {
    $flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
    if ($flutterCommand) {
        $flutterPath = $flutterCommand.Source
    } elseif (Test-Path -LiteralPath '.tools\flutter\bin\flutter.bat') {
        $flutterPath = Join-Path $PSScriptRoot '.tools\flutter\bin\flutter.bat'
    } else {
        throw 'Flutter SDK missing. Install Flutter or extract it into .tools/flutter.'
    }
    if ($flutterPath.Contains(' ')) {
        $fileSystem = New-Object -ComObject Scripting.FileSystemObject
        $flutterPath = $fileSystem.GetFile($flutterPath).ShortPath
    }
    $previousWindows = $env:FLUTTER_WINDOWS
    $previousLinux = $env:FLUTTER_LINUX
    try {
        $env:FLUTTER_WINDOWS = 'false'
        $env:FLUTTER_LINUX = 'false'
        & $flutterPath --no-version-check pub get
        if ($LASTEXITCODE -ne 0) { throw 'Flutter dependency installation failed.' }
        & $flutterPath --no-version-check build web --no-web-resources-cdn
        if ($LASTEXITCODE -ne 0) { throw 'Flutter web build failed.' }
    } finally {
        $env:FLUTTER_WINDOWS = $previousWindows
        $env:FLUTTER_LINUX = $previousLinux
    }
}
if (-not (Test-Path -LiteralPath 'build/web/index.html')) {
    throw 'No web build exists. Run without -SkipBuild first.'
}
if ($Background) {
    $appProcess = Start-Process -FilePath $venvPython `
        -ArgumentList "backend/server.py --port $Port" `
        -WorkingDirectory $PSScriptRoot -WindowStyle Hidden `
        -RedirectStandardOutput (Join-Path $logDirectory 'app.stdout.log') `
        -RedirectStandardError (Join-Path $logDirectory 'app.stderr.log') -PassThru
    $appProcess.Id | Set-Content (Join-Path $logDirectory 'app-process.pid')
    Write-Host "Hybrid Attendance starting at http://127.0.0.1:$Port (PID $($appProcess.Id))"
} else {
    & $venvPython backend/server.py --port $Port
}
