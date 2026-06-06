$ErrorActionPreference = "Stop"

$ProjectDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ProjectDir

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Stock Monitor - Quick Start" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# ---- Step 1: Check Python ----
Write-Host "[1/5] Checking Python..." -ForegroundColor Yellow

$pythonCmd = $null
foreach ($cmd in @("python", "python3", "py")) {
    try {
        $version = & $cmd --version 2>&1
        if ($LASTEXITCODE -eq 0) {
            $pythonCmd = $cmd
            Write-Host "  Found Python: $version" -ForegroundColor Green
            break
        }
    } catch {
        continue
    }
}

if (-not $pythonCmd) {
    Write-Host "  [ERROR] Python not found!" -ForegroundColor Red
    Write-Host "  Please install Python 3.9+: https://www.python.org/downloads/" -ForegroundColor Red
    Write-Host "  Make sure to check 'Add Python to PATH' during installation" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

# ---- Step 2: Check/Create venv ----
Write-Host ""
Write-Host "[2/5] Checking virtual environment..." -ForegroundColor Yellow

$VenvDir = Join-Path $ProjectDir "venv"

if (-not (Test-Path $VenvDir)) {
    Write-Host "  Creating virtual environment..." -ForegroundColor Yellow
    & $pythonCmd -m venv $VenvDir
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  [ERROR] Failed to create virtual environment!" -ForegroundColor Red
        Read-Host "Press Enter to exit"
        exit 1
    }
    Write-Host "  Virtual environment created" -ForegroundColor Green
} else {
    Write-Host "  Virtual environment exists" -ForegroundColor Green
}

# ---- Step 3: Activate venv ----
Write-Host ""
Write-Host "[3/5] Activating virtual environment..." -ForegroundColor Yellow

$ActivateScript = Join-Path $VenvDir "Scripts\Activate.ps1"
if (-not (Test-Path $ActivateScript)) {
    Write-Host "  [ERROR] Activation script not found!" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

& $ActivateScript
Write-Host "  Virtual environment activated" -ForegroundColor Green

# ---- Step 4: Install dependencies ----
Write-Host ""
Write-Host "[4/5] Checking dependencies..." -ForegroundColor Yellow

$RequirementsFile = Join-Path $ProjectDir "requirements.txt"
if (-not (Test-Path $RequirementsFile)) {
    Write-Host "  [ERROR] requirements.txt not found!" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

$streamlitInstalled = $false
try {
    $null = & python -c "import streamlit" 2>&1
    if ($LASTEXITCODE -eq 0) {
        $streamlitInstalled = $true
    }
} catch {}

if (-not $streamlitInstalled) {
    Write-Host "  Installing dependencies (first time may take a few minutes)..." -ForegroundColor Yellow
    & python -m pip install --upgrade pip -q
    & python -m pip install -r $RequirementsFile
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  [ERROR] Failed to install dependencies!" -ForegroundColor Red
        Write-Host "  Try manually: pip install -r requirements.txt" -ForegroundColor Red
        Read-Host "Press Enter to exit"
        exit 1
    }
    Write-Host "  Dependencies installed" -ForegroundColor Green
} else {
    Write-Host "  Dependencies already installed" -ForegroundColor Green
}

# ---- Step 5: Start app ----
Write-Host ""
Write-Host "[5/5] Starting application..." -ForegroundColor Yellow
Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Starting... Browser will open automatically" -ForegroundColor Green
Write-Host "  URL: http://localhost:8501" -ForegroundColor Green
Write-Host "  Press Ctrl+C to stop" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""

& streamlit run (Join-Path $ProjectDir "app.py") --server.headless=true

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "  [ERROR] Application failed to start!" -ForegroundColor Red
    Write-Host "  Try manually: streamlit run app.py" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}
