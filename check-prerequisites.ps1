# Azure NetApp Files Migration Assistant - Prerequisites Checker
# Run this in PowerShell to verify all requirements

Write-Host "🚀 Azure NetApp Files Migration Assistant - Prerequisites Check" -ForegroundColor Green
Write-Host "=" * 70 -ForegroundColor Green
Write-Host ""

$allGood = $true

# 1. Check Git Bash
Write-Host "🔧 Checking Git Bash..." -ForegroundColor Cyan
$gitBashPath = "C:\Program Files\Git\bin\bash.exe"
if (Test-Path $gitBashPath) {
    Write-Host "✅ Git Bash found at: $gitBashPath" -ForegroundColor Green
    try {
        $gitVersion = & $gitBashPath --version 2>&1 | Select-Object -First 1
        Write-Host "   Version: $gitVersion" -ForegroundColor Gray
    } catch {
        Write-Host "⚠️  Git Bash found but may have issues" -ForegroundColor Yellow
    }
} else {
    Write-Host "❌ Git Bash not found!" -ForegroundColor Red
    Write-Host "   Install from: https://git-scm.com/download/win" -ForegroundColor Yellow
    $allGood = $false
}

Write-Host ""

# 2. Check Python
Write-Host "🐍 Checking Python..." -ForegroundColor Cyan
$pythonCmd = $null

# Test python3
if (Get-Command python3 -ErrorAction SilentlyContinue) {
    try {
        $version = python3 --version 2>&1
        if ($version -like "Python *") {
            $pythonCmd = "python3"
            Write-Host "✅ python3 works: $version" -ForegroundColor Green
        }
    } catch {
        Write-Host "⚠️  python3 command exists but doesn't work (likely Windows Store stub)" -ForegroundColor Yellow
    }
}

# Test python
if (-not $pythonCmd -and (Get-Command python -ErrorAction SilentlyContinue)) {
    try {
        $version = python --version 2>&1
        if ($version -like "Python *") {
            $pythonCmd = "python"
            Write-Host "✅ python works: $version" -ForegroundColor Green
        }
    } catch {
        Write-Host "⚠️  python command exists but doesn't work" -ForegroundColor Yellow
    }
}

# Test py launcher
if (-not $pythonCmd -and (Get-Command py -ErrorAction SilentlyContinue)) {
    try {
        $version = py --version 2>&1
        if ($version -like "Python *") {
            $pythonCmd = "py"
            Write-Host "✅ py launcher works: $version" -ForegroundColor Green
        }
    } catch {
        Write-Host "⚠️  py launcher exists but doesn't work" -ForegroundColor Yellow
    }
}

if (-not $pythonCmd) {
    Write-Host "❌ No working Python found!" -ForegroundColor Red
    Write-Host "   Install from: https://python.org/downloads/" -ForegroundColor Yellow
    Write-Host "   Make sure to check 'Add to PATH' during installation" -ForegroundColor Yellow
    $allGood = $false
}

Write-Host ""

# 3. Check PyYAML
Write-Host "📦 Checking PyYAML..." -ForegroundColor Cyan
if ($pythonCmd) {
    try {
        $yamlTest = & $pythonCmd -c "import yaml; print('PyYAML version:', yaml.__version__)" 2>&1
        if ($yamlTest -like "*PyYAML version:*") {
            Write-Host "✅ PyYAML installed: $yamlTest" -ForegroundColor Green
        } else {
            Write-Host "❌ PyYAML not installed!" -ForegroundColor Red
            Write-Host "   Run: pip install PyYAML" -ForegroundColor Yellow
            $allGood = $false
        }
    } catch {
        Write-Host "❌ PyYAML not installed!" -ForegroundColor Red
        Write-Host "   Run: pip install PyYAML" -ForegroundColor Yellow
        $allGood = $false
    }
} else {
    Write-Host "⏭️  Skipping PyYAML check (Python not available)" -ForegroundColor Gray
}

Write-Host ""

# 4. Check curl
Write-Host "🌐 Checking curl..." -ForegroundColor Cyan
if (Get-Command curl -ErrorAction SilentlyContinue) {
    try {
        $curlVersion = curl --version 2>&1 | Select-Object -First 1
        Write-Host "✅ curl available: $curlVersion" -ForegroundColor Green
    } catch {
        Write-Host "⚠️  curl command exists but may have issues" -ForegroundColor Yellow
    }
} else {
    Write-Host "❌ curl not found!" -ForegroundColor Red
    Write-Host "   curl should be built-in on Windows 10 1803+. Try updating Windows." -ForegroundColor Yellow
    $allGood = $false
}

Write-Host ""

# 5. Test Git Bash + Python integration
Write-Host "🔗 Testing Git Bash + Python integration..." -ForegroundColor Cyan
if (Test-Path $gitBashPath -and $pythonCmd) {
    try {
        $bashTest = & $gitBashPath -c "python --version && python -c 'import yaml; print(`"Integration test passed`")'" 2>&1
        if ($bashTest -like "*Integration test passed*") {
            Write-Host "✅ Git Bash + Python + PyYAML integration works!" -ForegroundColor Green
        } else {
            Write-Host "⚠️  Integration test had issues: $bashTest" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "❌ Git Bash + Python integration failed!" -ForegroundColor Red
        Write-Host "   This may cause issues with the migration script" -ForegroundColor Yellow
        $allGood = $false
    }
} else {
    Write-Host "⏭️  Skipping integration test (missing components)" -ForegroundColor Gray
}

Write-Host ""

# 6. Check project files
Write-Host "📁 Checking project files..." -ForegroundColor Cyan
$projectFiles = @(
    "anf_interactive.sh",
    "setup_wizard.py",
    "config.template.yaml"
)

foreach ($file in $projectFiles) {
    if (Test-Path $file) {
        Write-Host "✅ Found: $file" -ForegroundColor Green
    } else {
        Write-Host "❌ Missing: $file" -ForegroundColor Red
        $allGood = $false
    }
}

Write-Host ""

# Final result
Write-Host "=" * 70 -ForegroundColor Green
if ($allGood) {
    Write-Host "🎉 ALL PREREQUISITES MET!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Ready to run the Azure NetApp Files Migration Assistant!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "1. Run setup wizard: " -NoNewline; Write-Host '& "C:\Program Files\Git\bin\bash.exe" -c "./anf_interactive.sh setup"' -ForegroundColor Yellow
    Write-Host "2. Run migration: " -NoNewline; Write-Host '& "C:\Program Files\Git\bin\bash.exe" -c "./anf_interactive.sh"' -ForegroundColor Yellow
} else {
    Write-Host "❌ SOME PREREQUISITES ARE MISSING!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please fix the issues above before running the migration assistant." -ForegroundColor Yellow
}
Write-Host "=" * 70 -ForegroundColor Green