# Azure NetApp Files Migration Assistant Script Runner - PowerShell Version
# Handles token management and enhanced workflow execution

param(
    [string]$Command = "help",
    [string]$Parameter1,
    [string]$Parameter2
)

# Configuration
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigFile = Join-Path $ScriptDir "config.yaml"
$TokenFile = Join-Path $ScriptDir ".token"
$LogFile = Join-Path $ScriptDir "anf_migration.log"

# Colors for output (PowerShell compatible)
$Colors = @{
    Red = "Red"
    Green = "Green"
    Yellow = "Yellow"
    Blue = "Blue"
    Cyan = "Cyan"
    White = "White"
}

# Logging function
function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "$timestamp - $Message"
    Write-Host $logEntry
    Add-Content -Path $LogFile -Value $logEntry
}

# Error handling
function Write-ErrorExit {
    param([string]$Message)
    Write-Host "❌ Error: $Message" -ForegroundColor $Colors.Red
    Write-Log "ERROR: $Message"
    exit 1
}

# Success message
function Write-Success {
    param([string]$Message)
    Write-Host "✅ $Message" -ForegroundColor $Colors.Green
    Write-Log "SUCCESS: $Message"
}

# Warning message
function Write-Warning {
    param([string]$Message)
    Write-Host "⚠️  $Message" -ForegroundColor $Colors.Yellow
    Write-Log "WARNING: $Message"
}

# Info message
function Write-Info {
    param([string]$Message)
    Write-Host "ℹ️  $Message" -ForegroundColor $Colors.Blue
    Write-Log "INFO: $Message"
}

# Check if required tools are available
function Test-Dependencies {
    Write-Info "Checking dependencies..."
    
    # Check for curl (or Invoke-WebRequest as PowerShell alternative)
    if (-not (Get-Command curl -ErrorAction SilentlyContinue)) {
        Write-Warning "curl not found - using PowerShell Invoke-WebRequest instead"
    }
    
    # Check for Python
    if (-not (Get-Command python -ErrorAction SilentlyContinue) -and -not (Get-Command python3 -ErrorAction SilentlyContinue)) {
        Write-ErrorExit "Python is required but not installed"
    }
    
    # Check for jq (optional)
    if (-not (Get-Command jq -ErrorAction SilentlyContinue)) {
        Write-Warning "jq not found - JSON parsing will be limited"
    }
    
    Write-Success "Dependencies check passed"
}

# Validate configuration
function Test-Config {
    Write-Info "Validating configuration..."
    
    if (-not (Test-Path $ConfigFile)) {
        Write-ErrorExit "Configuration file $ConfigFile not found"
    }
    
    # Validation passed - show current config
    Write-Success "Configuration is valid"
    Write-Host ""
    & "$ScriptDir\anf_workflow.ps1" -Command "config"
}

# Extract value from YAML config
function Get-ConfigValue {
    param([string]$Key)
    
    $pythonCmd = if (Get-Command python3 -ErrorAction SilentlyContinue) { "python3" } else { "python" }
    
    $configPath = $ConfigFile.Replace('\', '/')
    $pythonScript = @"
import yaml
with open('$configPath') as f:
    config = yaml.safe_load(f)
    all_vars = {**config.get('variables', {}), **config.get('secrets', {})}
    print(all_vars.get('$Key', ''))
"@
    
    return & $pythonCmd -c $pythonScript
}

# Get Azure AD token
function Get-Token {
    Write-Info "Requesting Azure AD token..."
    
    $tenant = Get-ConfigValue 'azure_tenant_id'
    $appId = Get-ConfigValue 'azure_app_id'
    $appSecret = Get-ConfigValue 'azure_app_secret'
    $authUrl = Get-ConfigValue 'azure_auth_base_url'
    
    if (-not $tenant -or -not $appId -or -not $appSecret) {
        Write-ErrorExit "Missing required authentication parameters in config"
    }
    
    $tokenUrl = "${authUrl}${tenant}/oauth2/token"
    $body = @{
        grant_type = "client_credentials"
        client_id = $appId
        client_secret = $appSecret
        resource = "https://management.azure.com/"
    }
    
    try {
        $response = Invoke-RestMethod -Uri $tokenUrl -Method Post -Body $body -ContentType "application/x-www-form-urlencoded"
        $token = $response.access_token
        
        # Save token to file
        $token | Out-File -FilePath $TokenFile -Encoding UTF8
        Write-Success "Token acquired and saved to $TokenFile"
        return $token
    }
    catch {
        Write-ErrorExit "Failed to acquire token: $($_.Exception.Message)"
    }
}

# Run a workflow script
function Invoke-Workflow {
    param([string]$ScriptName)
    
    Write-Info "Running workflow: $ScriptName"
    
    if ($ScriptName -like "*.sh") {
        # Convert to PowerShell script name
        $psScriptName = $ScriptName -replace '\.sh$', '.ps1'
    } else {
        $psScriptName = $ScriptName
    }
    
    $scriptPath = Join-Path $ScriptDir $psScriptName
    
    if (-not (Test-Path $scriptPath)) {
        Write-ErrorExit "Workflow script not found: $scriptPath"
    }
    
    & $scriptPath
}

# Generate and run workflow
function Invoke-GenerateAndRun {
    param(
        [string]$Protocol,
        [string]$QoS
    )
    
    Write-Info "Generating and running workflow for Protocol: $Protocol, QoS: $QoS"
    
    # Use the dynamic workflow
    & "$ScriptDir\anf_workflow.ps1" -Command "run"
}

# Show usage information
function Show-Usage {
    Write-Host ""
    Write-Host "Azure NetApp Files Migration Assistant - PowerShell Runner" -ForegroundColor $Colors.Cyan
    Write-Host "=============================================================" -ForegroundColor $Colors.Cyan
    Write-Host ""
    Write-Host "Usage: .\anf_runner.ps1 [COMMAND] [OPTIONS]"
    Write-Host ""
    Write-Host "Commands:"
    Write-Host "  setup                   - Interactive configuration wizard"
    Write-Host "  validate                - Validate configuration"
    Write-Host "  token                   - Get new Azure AD token"
    Write-Host "  run [SCRIPT]           - Run a specific workflow script"
    Write-Host "  generate [PROTOCOL] [QOS] - Generate and run workflow"
    Write-Host "  list                    - List available workflow scripts"
    Write-Host ""
    Write-Host "Getting Started:"
    Write-Host "  .\anf_runner.ps1 setup                - First-time configuration wizard"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  .\anf_runner.ps1 setup                - Interactive setup wizard"
    Write-Host "  .\anf_runner.ps1 validate"
    Write-Host "  .\anf_runner.ps1 generate NFSv3 Auto"
    Write-Host "  .\anf_runner.ps1 generate SMB Manual"
    Write-Host "  .\anf_runner.ps1 run anf_workflow.ps1"
    Write-Host ""
}

# List available workflows
function Show-WorkflowList {
    Write-Host "Available workflow options:"
    Write-Host "  🚀 anf_workflow.ps1 - Dynamic workflow (reads config.yaml at runtime)"
    
    # Show any legacy static workflows if they exist
    $legacyWorkflows = Get-ChildItem -Path $ScriptDir -Name "workflow_*.ps1" -ErrorAction SilentlyContinue
    if ($legacyWorkflows) {
        Write-Host "  📄 Legacy static workflows:"
        $legacyWorkflows | ForEach-Object { Write-Host "     $_" }
    }
    
    Write-Host ""
    Write-Host "Supported protocol/QoS combinations:"
    Write-Host "  📁 NFSv3 + Auto QoS"
    Write-Host "  📁 NFSv3 + Manual QoS"
    Write-Host "  📁 CIFS + Auto QoS"
    Write-Host "  📁 CIFS + Manual QoS"
    
    Write-Host ""
    Write-Host "Current configuration:"
    & "$ScriptDir\anf_workflow.ps1" -Command "config"
}

# Main execution
function Main {
    Write-Log "Starting ANF Migration Assistant Runner (PowerShell)"
    
    switch ($Command.ToLower()) {
        "setup" {
            Write-Info "Starting interactive setup wizard..."
            $pythonCmd = if (Get-Command python3 -ErrorAction SilentlyContinue) { "python3" } else { "python" }
            & $pythonCmd "$ScriptDir\setup_wizard.py"
        }
        "validate" {
            Test-Dependencies
            Test-Config
        }
        "token" {
            Test-Dependencies
            Get-Token
        }
        "run" {
            if (-not $Parameter1) {
                Write-ErrorExit "Please specify a workflow script to run"
            }
            Test-Dependencies
            try {
                Test-Config
            }
            catch {
                Write-ErrorExit "Configuration validation failed"
            }
            Invoke-Workflow $Parameter1
        }
        "generate" {
            Test-Dependencies
            try {
                Test-Config
            }
            catch {
                Write-ErrorExit "Configuration validation failed"
            }
            Invoke-GenerateAndRun $Parameter1 $Parameter2
        }
        "list" {
            Show-WorkflowList
        }
        default {
            if ($Command -eq "help" -or $Command -eq "--help" -or $Command -eq "-h" -or $Command -eq "") {
                Show-Usage
            }
            else {
                Write-ErrorExit "Unknown command: $Command. Use `'.\anf_runner.ps1 help`' for usage information."
            }
        }
    }
}

# Run main function
Main
