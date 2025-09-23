# Azure NetApp Files Migration Assistant - Prerequisites Checker
# Run this in PowerShell to verify all requirements

# Function to refresh environment variables without restarting PowerShell
function Update-EnvironmentPath {
    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH","User")
    Write-Host "   Environment PATH refreshed" -ForegroundColor Gray
}

Write-Host "Azure NetApp Files Migration Assistant - Prerequisites Check" -ForegroundColor Green
Write-Host "======================================================================" -ForegroundColor Green
Write-Host ""

$allGood = $true

# 1. Check Git Bash
Write-Host "Checking Git Bash..." -ForegroundColor Cyan
$gitBashPath = "C:\Program Files\Git\bin\bash.exe"
if (Test-Path $gitBashPath) {
    Write-Host "Git Bash found at: $gitBashPath" -ForegroundColor Green
    try {
        $gitVersion = & $gitBashPath --version 2>&1 | Select-Object -First 1
        Write-Host "   Version: $gitVersion" -ForegroundColor Gray
    } catch {
        Write-Host "Git Bash found but may have issues" -ForegroundColor Yellow
    }
} else {
    Write-Host "Git Bash not found!" -ForegroundColor Red
    Write-Host "   Install from: https://git-scm.com/download/win" -ForegroundColor Yellow
    $allGood = $false
}

Write-Host ""

# 2. Check Python
Write-Host "Checking Python..." -ForegroundColor Cyan
$pythonCmd = $null

# Test python3
if (Get-Command python3 -ErrorAction SilentlyContinue) {
    try {
        $version = python3 --version 2>&1 | Out-String -Stream | Where-Object { $_ -like "Python *" } | Select-Object -First 1
        if ($version -and $version -like "Python *" -and $version -notlike "*was not found*") {
            $pythonCmd = "python3"
            Write-Host "python3 works: $version" -ForegroundColor Green
        } else {
            throw "Windows Store stub or error"
        }
    } catch {
        Write-Host "python3 command exists but doesn't work" -ForegroundColor Yellow
        $python3Path = (Get-Command python3).Source
        if ($python3Path -like "*WindowsApps*") {
            Write-Host "Detected Windows Store stub at: $python3Path" -ForegroundColor Gray
        }
    }
}

# Test python
if (-not $pythonCmd -and (Get-Command python -ErrorAction SilentlyContinue)) {
    try {
        $version = python --version 2>&1 | Out-String -Stream | Where-Object { $_ -like "Python *" } | Select-Object -First 1
        if ($version -and $version -like "Python *" -and $version -notlike "*was not found*") {
            $pythonCmd = "python"
            Write-Host " python works: $version" -ForegroundColor Green
        } else {
            throw "Windows Store stub or error"
        }
    } catch {
        Write-Host "  python command exists but doesn't work" -ForegroundColor Yellow
    }
}

# Test py launcher
if (-not $pythonCmd -and (Get-Command py -ErrorAction SilentlyContinue)) {
    try {
        $version = py --version 2>&1 | Out-String -Stream | Where-Object { $_ -like "Python *" } | Select-Object -First 1
        if ($version -and $version -like "Python *" -and $version -notlike "*was not found*") {
            $pythonCmd = "py"
            Write-Host " py launcher works: $version" -ForegroundColor Green
        } else {
            throw "Python launcher error"
        }
    } catch {
        Write-Host "  py launcher exists but doesn't work" -ForegroundColor Yellow
    }
}

if (-not $pythonCmd) {
    Write-Host " No working Python found!" -ForegroundColor Red
    Write-Host ""
    Write-Host " Auto-Install Available: Python" -ForegroundColor Cyan
    Write-Host "   Would you like to automatically install Python? This will:" -ForegroundColor Yellow
    Write-Host "   • Download and install the latest Python from python.org" -ForegroundColor Gray
    Write-Host "   • Add Python to your PATH automatically" -ForegroundColor Gray
    Write-Host "   • Install pip package manager" -ForegroundColor Gray
    Write-Host ""
    $response = Read-Host "   Install Python automatically? (y/N)"
    
    if ($response -eq 'y' -or $response -eq 'Y') {
        Write-Host ""
        Write-Host "   Installing Python..." -ForegroundColor Cyan
        
        try {
            # Download Python installer
            $pythonUrl = "https://www.python.org/ftp/python/3.12.6/python-3.12.6-amd64.exe"
            $installerPath = "$env:TEMP\python-installer.exe"
            
            Write-Host "   Downloading Python installer..." -ForegroundColor Gray
            Invoke-WebRequest -Uri $pythonUrl -OutFile $installerPath -ErrorAction Stop
            
            Write-Host "   Running Python installer..." -ForegroundColor Gray
            # Install Python silently with PATH and pip
            $installArgs = "/quiet InstallAllUsers=0 PrependPath=1 Include_pip=1 Include_test=0"
            Start-Process -FilePath $installerPath -ArgumentList $installArgs -Wait -ErrorAction Stop
            
            Write-Host "   Cleaning up installer..." -ForegroundColor Gray
            Remove-Item $installerPath -ErrorAction SilentlyContinue
            
            Write-Host "   Python installation completed!" -ForegroundColor Green
            Write-Host "   Refreshing environment variables..." -ForegroundColor Gray
            Update-EnvironmentPath
            
            # Re-test Python detection
            Write-Host "   Testing Python installation..." -ForegroundColor Gray
            if (Get-Command python -ErrorAction SilentlyContinue) {
                try {
                    $version = python --version 2>&1
                    if ($version -like "Python *") {
                        $pythonCmd = "python"
                        Write-Host "   Python now works: $version" -ForegroundColor Green
                        Write-Host "   No restart required - continuing with checks..." -ForegroundColor Green
                    }
                } catch {
                    Write-Host "   Python installed but may need a PowerShell restart to work properly" -ForegroundColor Yellow
                }
            } else {
                Write-Host "   Python installed but may need a PowerShell restart to work properly" -ForegroundColor Yellow
            }
            Write-Host ""
            
        } catch {
            Write-Host "   Failed to install Python automatically: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "   Please install Python manually from: https://python.org/downloads/" -ForegroundColor Yellow
            Write-Host "   Make sure to check 'Add to PATH' during installation" -ForegroundColor Yellow
        }
    } else {
        Write-Host "   Skipping Python installation" -ForegroundColor Gray
        Write-Host "   Manual install from: https://python.org/downloads/" -ForegroundColor Yellow
        Write-Host "   Make sure to check 'Add to PATH' during installation" -ForegroundColor Yellow
    }
    
    # Only mark as failed if Python installation was declined or failed
    if (-not $pythonCmd) {
        $allGood = $false
    }
}

Write-Host ""

# 3. Check PyYAML
Write-Host " Checking PyYAML..." -ForegroundColor Cyan
if ($pythonCmd) {
    try {
        $yamlTest = & $pythonCmd -c "import yaml; print('PyYAML version:', yaml.__version__)" 2>&1
        if ($yamlTest -match "PyYAML version:") {
            Write-Host " PyYAML installed: $yamlTest" -ForegroundColor Green
        } else {
            Write-Host " PyYAML not installed!" -ForegroundColor Red
            Write-Host ""
            Write-Host " Auto-Install Available: PyYAML" -ForegroundColor Cyan
            $response = Read-Host "   Install PyYAML automatically? (y/N)"
            
            if ($response -eq 'y' -or $response -eq 'Y') {
                Write-Host "   Installing PyYAML..." -ForegroundColor Gray
                try {
                    & $pythonCmd -m pip install PyYAML
                    Write-Host "   PyYAML installed successfully!" -ForegroundColor Green
                } catch {
                    Write-Host "   Failed to install PyYAML: $($_.Exception.Message)" -ForegroundColor Red
                    Write-Host "   Run manually: pip install PyYAML" -ForegroundColor Yellow
                    $allGood = $false
                }
            } else {
                Write-Host "   Skipping PyYAML installation" -ForegroundColor Gray
                Write-Host "   Run manually: pip install PyYAML" -ForegroundColor Yellow
                $allGood = $false
            }
        }
    } catch {
        Write-Host " PyYAML not installed!" -ForegroundColor Red
        Write-Host ""
        Write-Host " Auto-Install Available: PyYAML" -ForegroundColor Cyan
        $response = Read-Host "   Install PyYAML automatically? (y/N)"
        
        if ($response -eq 'y' -or $response -eq 'Y') {
            Write-Host "   Installing PyYAML..." -ForegroundColor Gray
            try {
                & $pythonCmd -m pip install PyYAML
                Write-Host "   PyYAML installed successfully!" -ForegroundColor Green
            } catch {
                Write-Host "   Failed to install PyYAML: $($_.Exception.Message)" -ForegroundColor Red
                Write-Host "   Run manually: pip install PyYAML" -ForegroundColor Yellow
                $allGood = $false
            }
        } else {
            Write-Host "   Skipping PyYAML installation" -ForegroundColor Gray
            Write-Host "   Run manually: pip install PyYAML" -ForegroundColor Yellow
            $allGood = $false
        }
    }
} else {
    Write-Host "  Skipping PyYAML check (Python not available)" -ForegroundColor Gray
}

Write-Host ""

# 4. Check curl
Write-Host " Checking curl..." -ForegroundColor Cyan
if (Get-Command curl -ErrorAction SilentlyContinue) {
    try {
        $curlVersion = (curl --version 2>&1 | Select-Object -First 1) -join ""
        Write-Host " curl available: $curlVersion" -ForegroundColor Green
    } catch {
        Write-Host "  curl command exists but may have issues" -ForegroundColor Yellow
    }
} else {
    Write-Host " curl not found!" -ForegroundColor Red
    Write-Host "   curl should be built-in on Windows 10 1803+. Try updating Windows." -ForegroundColor Yellow
    $allGood = $false
}

Write-Host ""

# 5. Test Git Bash + Python integration
Write-Host " Testing Git Bash + Python integration..." -ForegroundColor Cyan
if ((Test-Path $gitBashPath) -and $pythonCmd) {
    try {
        $bashTest = & $gitBashPath -c "python --version; python -c 'import yaml; print(\"Integration test passed\")'" 2>&1
        if ($bashTest -like "*Integration test passed*") {
            Write-Host " Git Bash + Python + PyYAML integration works!" -ForegroundColor Green
        } else {
            Write-Host "  Integration test had issues: $bashTest" -ForegroundColor Yellow
        }
    } catch {
        Write-Host " Git Bash + Python integration failed!" -ForegroundColor Red
        Write-Host "   This may cause issues with the migration script" -ForegroundColor Yellow
        $allGood = $false
    }
} else {
    Write-Host "  Skipping integration test (missing components)" -ForegroundColor Gray
}

Write-Host ""

# 6. Check project files
Write-Host " Checking project files..." -ForegroundColor Cyan
$projectFiles = @(
    "anf_interactive.sh",
    "setup_wizard.py",
    "config.template.yaml"
)

foreach ($file in $projectFiles) {
    if (Test-Path $file) {
        Write-Host " Found: $file" -ForegroundColor Green
    } else {
        Write-Host " Missing: $file" -ForegroundColor Red
        $allGood = $false
    }
}

Write-Host ""

# Auto-fix option for Windows Store Python stub issue
if (-not $pythonCmd -and ((Get-Command python3 -ErrorAction SilentlyContinue) -or (Get-Command python -ErrorAction SilentlyContinue))) {
    Write-Host ""
    Write-Host " Auto-Fix Available: Windows Store Python Stub Issue" -ForegroundColor Cyan
    Write-Host "   The system has python commands but they don't work (Windows Store stubs)" -ForegroundColor Gray
    Write-Host ""
    
    Write-Host "   Would you like to automatically fix this? This will:" -ForegroundColor Yellow
    Write-Host "    Remove non-functional Windows Store Python stubs" -ForegroundColor Gray
    Write-Host "    Keep all real Python installations intact" -ForegroundColor Gray
    Write-Host "    No changes to system PATH or registry" -ForegroundColor Gray
    Write-Host ""
    $response = Read-Host "   Apply fix? (y/N)"
    
    if ($response -eq 'y' -or $response -eq 'Y') {
        Write-Host ""
        Write-Host "    Applying Windows Store Python stub fix..." -ForegroundColor Cyan
        
        $fixed = $false
        
        # Remove python3.exe stub if it exists and is problematic
        $python3Stub = "$env:LOCALAPPDATA\Microsoft\WindowsApps\python3.exe"
        if (Test-Path $python3Stub) {
            try {
                Remove-Item $python3Stub -Force -ErrorAction Stop
                Write-Host "    Removed python3.exe stub" -ForegroundColor Green
                $fixed = $true
            } catch {
                Write-Host "     Could not remove python3.exe stub (may need admin rights)" -ForegroundColor Yellow
            }
        }
        
        # Remove python.exe stub if it exists and is problematic
        $pythonStub = "$env:LOCALAPPDATA\Microsoft\WindowsApps\python.exe"
        if (Test-Path $pythonStub) {
            try {
                Remove-Item $pythonStub -Force -ErrorAction Stop
                Write-Host "    Removed python.exe stub" -ForegroundColor Green
                $fixed = $true
            } catch {
                Write-Host "     Could not remove python.exe stub (may need admin rights)" -ForegroundColor Yellow
            }
        }
        
        if ($fixed) {
            Write-Host "    Re-testing Python after fix..." -ForegroundColor Cyan
            
            # Re-test Python detection
            if (Get-Command python -ErrorAction SilentlyContinue) {
                try {
                    $version = python --version 2>&1
                    if ($version -like "Python *") {
                        $pythonCmd = "python"
                        Write-Host "    Python now works: $version" -ForegroundColor Green
                        $allGood = $true
                        
                        # Test PyYAML again
                        try {
                            $yamlTest = python -c "import yaml; print('PyYAML available')" 2>&1
                            if ($yamlTest -like "*PyYAML available*") {
                                Write-Host "    PyYAML also working!" -ForegroundColor Green
                            }
                        } catch {
                            Write-Host "     PyYAML still needs installation: pip install PyYAML" -ForegroundColor Cyan
                        }
                    }
                } catch {
                    Write-Host "     Python still not working after fix" -ForegroundColor Yellow
                }
            }
        } else {
            Write-Host "     No stub files found to remove" -ForegroundColor Cyan
        }
        
        Write-Host ""
    } else {
        Write-Host "     Skipping auto-fix" -ForegroundColor Gray
        Write-Host ""
    }
}

# Final result
Write-Host "======================================================================" -ForegroundColor Green
if ($allGood) {
    Write-Host " ALL PREREQUISITES MET!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Ready to run the Azure NetApp Files Migration Assistant!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "1. Run setup wizard: " -NoNewline; Write-Host '& "C:\Program Files\Git\bin\bash.exe" -c "./anf_interactive.sh setup"' -ForegroundColor Yellow
    Write-Host "2. Run migration: " -NoNewline; Write-Host '& "C:\Program Files\Git\bin\bash.exe" -c "./anf_interactive.sh"' -ForegroundColor Yellow
} else {
    Write-Host " SOME PREREQUISITES ARE MISSING!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please fix the issues above before running the migration assistant." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Tip: Run this script again after installing missing components" -ForegroundColor Cyan
}
Write-Host "======================================================================" -ForegroundColor Green
