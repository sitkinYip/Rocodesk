<#
.SYNOPSIS
    Launch the lineup helper in a browser (Windows dev workflow).

.DESCRIPTION
    Two concrete problems this script solves:

      1. On this machine `bash` points at WSL, and WSL has NO distribution
         installed. Running flutter there only ever yields
         "command not found". Use PowerShell, not bash.

      2. Flutter lives in F:\flutter. It is on the user PATH now, but an
         already-open terminal does not pick up environment changes, so the
         script adds it explicitly for this session.

    WHY THE DEFAULT IS A STATIC RELEASE BUILD, NOT `flutter run`:

      `flutter run -d chrome` needs to both launch a browser and open a
      WebSocket debug channel. In this environment the channel fails:

          DevHandler: Failed to create WebSocket debug connection:
            WebSocketException: Connection to 'http://127.0.0.1:.../ws#'
            was not upgraded to websocket

      When that happens the dev server still answers on the port, but
      `main.dart.js` is only a ~7.5 KB bootstrap shell (the real code was
      supposed to arrive over the dead channel). The browser therefore shows
      a BLANK PAGE, which looks like an app bug but is not.

      A release build has no such dependency: main.dart.js is ~2.8 MB and
      self-contained, so serving it statically always works.

      Trade-off, stated plainly: no hot reload. After editing code, re-run
      this script (it rebuilds).

    NOTE: this file is intentionally pure ASCII. Windows PowerShell 5.1 reads
    .ps1 files as ANSI, so non-ASCII bytes break parsing (it mis-reads them and
    reports bogus "unexpected token }" errors). Keep it ASCII.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File app\run_web.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File app\run_web.ps1 -Port 9000

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File app\run_web.ps1 -DevServer

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File app\run_web.ps1 -CheckOnly
#>
[CmdletBinding()]
param(
    # Port for the local web server.
    [int]$Port = 8080,

    # Which browser to use: chrome / edge / msedge / firefox.
    [string]$Browser = 'chrome',

    # Only run analyze + tests; do not start the app.
    [switch]$CheckOnly,

    # Use `flutter run` (hot reload) instead of a static release build.
    # Expect a BLANK PAGE on this machine - see .DESCRIPTION.
    [switch]$DevServer,

    # Skip the rebuild in static mode (serve the existing build/web as-is).
    [switch]$NoBuild
)

$ErrorActionPreference = 'Stop'

# ---- 1. Locate Flutter -----------------------------------------------------
# Try, in order: flutter on PATH, then FLUTTER_ROOT, then a known local install.
# Deliberately not a single hard-coded absolute path, so a clone works anywhere.
$flutterBin = $null
$onPath = Get-Command flutter -ErrorAction SilentlyContinue
if ($onPath) {
    $flutterBin = Split-Path -Parent $onPath.Source
} elseif ($env:FLUTTER_ROOT -and (Test-Path (Join-Path $env:FLUTTER_ROOT 'bin\flutter.bat'))) {
    $flutterBin = Join-Path $env:FLUTTER_ROOT 'bin'
} elseif (Test-Path 'F:\flutter\bin\flutter.bat') {
    $flutterBin = 'F:\flutter\bin'
}

if (-not $flutterBin) {
    Write-Host "[X] Flutter not found." -ForegroundColor Red
    Write-Host "    Put it on PATH, or set FLUTTER_ROOT, or install:"
    Write-Host "    https://docs.flutter.dev/get-started/install/windows"
    exit 1
}

# An already-open terminal does not refresh PATH on its own.
if ($env:Path -notlike "*$flutterBin*") {
    $env:Path = "$flutterBin;$env:Path"
    Write-Host "- added $flutterBin to this session PATH" -ForegroundColor DarkGray
}

# ---- 2. Work from the app directory ----------------------------------------
$appDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $appDir

Write-Host ""
Write-Host "Lineup Helper - local dev launcher" -ForegroundColor Cyan
Write-Host "  dir     : $appDir"
Write-Host "  flutter : $(& flutter --version 2>&1 | Select-Object -First 1)"
Write-Host ""

# ---- 3. Check first, so compile errors are not mistaken for UI bugs --------
# flutter writes progress/telemetry lines to stderr, and with
# $ErrorActionPreference='Stop' PowerShell turns native stderr into a
# terminating error. Relax it just for this call, then restore.
Write-Host "- running static analysis..." -ForegroundColor DarkGray
$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$analyze = & flutter analyze 2>&1 | Out-String
$analyzeExit = $LASTEXITCODE
$ErrorActionPreference = $prevEap

# Match real compile errors only. `flutter analyze` also prints "info" level
# lints, which must NOT block a launch.
if ($analyze -match '(^|\s)error\s+-') {
    Write-Host "[X] Compile errors. Fix these before launching:" -ForegroundColor Red
    Write-Host $analyze
    exit 1
}
Write-Host "  [OK] no compile errors (analyze exit $analyzeExit)" -ForegroundColor Green

if ($CheckOnly) {
    Write-Host "- running tests..." -ForegroundColor DarkGray
    & flutter test
    exit $LASTEXITCODE
}

# ---- 4. Launch -------------------------------------------------------------
if ($DevServer) {
    Write-Host "- DEV SERVER MODE (hot reload)" -ForegroundColor Yellow
    Write-Host "  WARNING: may show a blank page - see the note at the top of this file." -ForegroundColor Yellow
    Write-Host "- starting. first run compiles, about 30-60s." -ForegroundColor DarkGray
    Write-Host ""
    # Do NOT name this variable $args: that is a PowerShell automatic variable
    # and assigning to it is a parse error.
    $flutterArgs = @('run', '-d', $Browser, '--web-port', $Port)
    & flutter @flutterArgs
    exit $LASTEXITCODE
}

# ---- 4b. Static release build (the reliable path) --------------------------
if (-not $NoBuild) {
    Write-Host "- building release web bundle..." -ForegroundColor DarkGray
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & flutter build web --release 2>&1 | Out-String | Write-Host
    $buildExit = $LASTEXITCODE
    $ErrorActionPreference = $prevEap
    if ($buildExit -ne 0) {
        Write-Host "[X] build failed (exit $buildExit)" -ForegroundColor Red
        exit $buildExit
    }
}

$js = Join-Path $appDir 'build\web\main.dart.js'
if (-not (Test-Path $js)) {
    Write-Host "[X] missing $js" -ForegroundColor Red
    Write-Host "    run without -NoBuild to produce it." -ForegroundColor Red
    exit 1
}

# A tiny shell means the build is not a real release bundle, which is exactly
# the condition that produces a blank page.
$jsSize = (Get-Item $js).Length
Write-Host ("  [OK] main.dart.js = {0:N1} MB" -f ($jsSize / 1MB)) -ForegroundColor Green
if ($jsSize -lt 1000000) {
    Write-Host "  [!] that is too small for a release bundle (expect about 2.8 MB)" -ForegroundColor Yellow
    Write-Host "      the page will probably be blank." -ForegroundColor Yellow
}

# Serve it. Python is used because a plain static server with correct MIME
# types is what makes Flutter web work (`text/javascript` for main.dart.js).
# Try, in order: python on PATH (py launcher first on Windows), then the
# well-known bundled runtime on this machine.
$py = $null
foreach ($cand in @('py', 'python', 'python3')) {
    $found = Get-Command $cand -ErrorAction SilentlyContinue
    if ($found) { $py = $found.Source; break }
}
if (-not $py) {
    $bundled = 'C:\Users\sitkinYip\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\python\python.exe'
    if (Test-Path $bundled) { $py = $bundled }
}
if (-not $py) {
    Write-Host "[X] Python not found - needed to serve the build." -ForegroundColor Red
    Write-Host "    Install Python, or serve build\web with any static server." -ForegroundColor Red
    exit 1
}
Write-Host "  using python: $py" -ForegroundColor DarkGray

Write-Host ""
Write-Host "  serving http://127.0.0.1:$Port" -ForegroundColor Cyan
Write-Host "  (no hot reload - re-run this script after editing code)" -ForegroundColor DarkGray
Write-Host "  press Ctrl+C to stop" -ForegroundColor DarkGray
Write-Host ""

# Open the browser ourselves; the server does not do it.
Start-Process "http://127.0.0.1:$Port" -ErrorAction SilentlyContinue

& $py -X utf8 (Join-Path $appDir 'serve_web.py') $Port
