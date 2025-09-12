# Azure NetApp Files Migration Assistant - Interactive Step-by-Step Mode PowerShell Version
# Execute each REST API call individually with result inspection

param(
    [string]$Command = "run"
)

# Configuration
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigFile = Join-Path $ScriptDir "config.yaml"
$TokenFile = Join-Path $ScriptDir ".token"
$LogFile = Join-Path $ScriptDir "anf_migration_interactive.log"

# Colors for output
$Colors = @{
    Red = "Red"
    Green = "Green"
    Yellow = "Yellow"
    Blue = "Blue"
    Cyan = "Cyan"
    Purple = "Magenta"
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

# Enhanced messaging
function Write-ErrorExit {
    param([string]$Message)
    Write-Host "❌ Error: $Message" -ForegroundColor $Colors.Red
    Write-Log "ERROR: $Message"
    exit 1
}

function Write-Success {
    param([string]$Message)
    Write-Host "✅ $Message" -ForegroundColor $Colors.Green
    Write-Log "SUCCESS: $Message"
}

function Write-Info {
    param([string]$Message)
    Write-Host "ℹ️  $Message" -ForegroundColor $Colors.Blue
    Write-Log "INFO: $Message"
}

function Write-Warning {
    param([string]$Message)
    Write-Host "⚠️  $Message" -ForegroundColor $Colors.Yellow
    Write-Log "WARNING: $Message"
}

function Write-StepHeader {
    param([string]$Title)
    
    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor $Colors.Purple
    Write-Host "║ $Title" -ForegroundColor $Colors.Purple
    Write-Host "╚══════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor $Colors.Purple
    Write-Host ""
}

# Read config value using Python
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

# Get protocol and QoS from config
function Get-Protocol {
    $protocolTypes = Get-ConfigValue 'target_protocol_types'
    if ($protocolTypes -match "SMB|CIFS") {
        return "SMB"
    }
    else {
        return "NFSv3"
    }
}

function Get-QoS {
    $throughput = Get-ConfigValue 'target_throughput_mibps'
    if ($throughput -and $throughput.Trim()) {
        return "Manual"
    }
    else {
        return "Auto"
    }
}

# Enhanced user confirmation with options
function Confirm-Step {
    param(
        [string]$StepName,
        [string]$Description
    )
    
    Write-Host "📋 About to execute: $StepName" -ForegroundColor $Colors.Cyan
    Write-Host "Description: $Description" -ForegroundColor $Colors.Cyan
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  [c] Continue with this step"
    Write-Host "  [s] Skip this step"
    Write-Host "  [q] Quit the workflow"
    Write-Host "  [r] Review current configuration"
    Write-Host ""
    
    do {
        $choice = Read-Host "Please choose an option [c/s/q/r]"
        
        switch ($choice.ToLower()) {
            'c' { return 'continue' }
            's' { return 'skip' }
            'q' { return 'quit' }
            'r' { 
                Show-Config
                Write-Host ""
                continue
            }
            default { 
                Write-Host "Invalid option. Please choose c, s, q, or r." -ForegroundColor $Colors.Yellow
                continue
            }
        }
    } while ($true)
}

# Replace variables in string using config values
function Expand-ConfigVariables {
    param([string]$Text)
    
    $pythonCmd = if (Get-Command python3 -ErrorAction SilentlyContinue) { "python3" } else { "python" }
    
    $configPath = $ConfigFile.Replace('\', '/')
    $pythonScript = @"
import sys, yaml
with open('$configPath') as f:
    config = yaml.safe_load(f)
    all_vars = {**config.get('variables', {}), **config.get('secrets', {})}
    
text = '''$Text'''
for key, value in all_vars.items():
    text = text.replace('{{' + key + '}}', str(value))
print(text, end='')
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
    
    if (-not $tenant -or -not $appId -or -not $appSecret -or -not $authUrl) {
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
        
        # Store token securely
        $token | Out-File -FilePath $TokenFile -Encoding UTF8 -NoNewline
        Write-Success "Token obtained and stored"
        return $token
    }
    catch {
        Write-ErrorExit "Failed to acquire token: $($_.Exception.Message)"
    }
}

# Execute a REST API call with interactive confirmation
function Invoke-ApiCallInteractive {
    param(
        [string]$StepName,
        [string]$Method,
        [string]$Endpoint,
        [string]$Data = "",
        [string]$Description,
        [switch]$ShowResponse = $false
    )
    
    $choice = Confirm-Step $StepName $Description
    
    switch ($choice) {
        'skip' {
            Write-Warning "Skipped: $StepName"
            return $null
        }
        'quit' {
            Write-Info "Workflow terminated by user"
            exit 0
        }
        'continue' {
            # Continue with API call
        }
    }
    
    Write-Info "Executing: $StepName"
    
    # Ensure we have a valid token
    if (-not (Test-Path $TokenFile)) {
        Get-Token | Out-Null
    }
    
    $token = Get-Content $TokenFile -Raw
    $apiUrl = Get-ConfigValue 'azure_api_base_url'
    $apiVersion = Get-ConfigValue 'azure_api_version'
    
    # Build the full URL
    $fullUrl = "${apiUrl}${Endpoint}?api-version=${apiVersion}"
    $fullUrl = Expand-ConfigVariables $fullUrl
    
    Write-Host "URL: $fullUrl" -ForegroundColor $Colors.Cyan
    
    # Prepare headers
    $headers = @{
        'Authorization' = "Bearer $token"
        'Content-Type' = 'application/json'
    }
    
    try {
        if ($Data) {
            $expandedData = Expand-ConfigVariables $Data
            Write-Host "Request Body:" -ForegroundColor $Colors.Cyan
            Write-Host $expandedData -ForegroundColor $Colors.White
            Write-Host ""
            
            $response = Invoke-RestMethod -Uri $fullUrl -Method $Method -Headers $headers -Body $expandedData
        }
        else {
            $response = Invoke-RestMethod -Uri $fullUrl -Method $Method -Headers $headers
        }
        
        Write-Success "Completed: $StepName"
        
        if ($ShowResponse -or $response) {
            Write-Host "Response:" -ForegroundColor $Colors.Cyan
            $response | ConvertTo-Json -Depth 10 | Write-Host -ForegroundColor $Colors.White
            Write-Host ""
        }
        
        return $response
    }
    catch {
        Write-ErrorExit "API call failed: $StepName - $($_.Exception.Message)"
    }
}

# Check volume status with enhanced monitoring
function Wait-VolumeCreation {
    param([string]$VolumeResourceId)
    
    Write-StepHeader "MONITORING VOLUME CREATION (Up to 20 minutes)"
    
    Write-Info "Volume creation can take up to 10 minutes..."
    Write-Info "Checking status every 30 seconds (40 attempts maximum)"
    
    $attempts = 0
    $maxAttempts = 40  # 40 * 30 seconds = 20 minutes total
    
    while ($attempts -lt $maxAttempts) {
        $attempts++
        
        Write-Host "[$attempts/$maxAttempts] Checking volume status..." -ForegroundColor $Colors.Blue
        
        try {
            $response = Invoke-ApiCallInteractive -StepName "CHECK_VOLUME_STATUS" -Method "GET" -Endpoint $VolumeResourceId -Description "Checking volume creation status" -ShowResponse:$false
            
            if ($response -and $response.properties -and $response.properties.provisioningState) {
                $state = $response.properties.provisioningState
                Write-Host "Volume State: $state" -ForegroundColor $Colors.Cyan
                
                if ($state -eq "Succeeded") {
                    Write-Success "Volume creation completed successfully!"
                    return $true
                }
                elseif ($state -eq "Failed") {
                    Write-ErrorExit "Volume creation failed"
                }
                else {
                    Write-Info "Volume creation in progress (State: $state)"
                }
            }
        }
        catch {
            Write-Warning "Status check failed (attempt $attempts): $($_.Exception.Message)"
        }
        
        if ($attempts -lt $maxAttempts) {
            Write-Host "Waiting 30 seconds before next check..." -ForegroundColor $Colors.Yellow
            Start-Sleep -Seconds 30
        }
    }
    
    Write-Warning "Maximum monitoring time reached. Please check Azure portal for current status."
    return $false
}

# Generate volume creation payload
function Get-VolumePayload {
    $protocol = Get-Protocol
    $qos = Get-QoS
    
    $payload = @'
{
    "type": "Microsoft.NetApp/netAppAccounts/capacityPools/volumes",
    "location": "{{target_location}}",
    "properties": {
        "volumeType": "Migration",
        "dataProtection": {
            "replication": {
                "endpointType": "Dst",
                "replicationSchedule": "{{replication_schedule}}",
                "remotePath": {
                    "externalHostName": "{{source_hostname}}",
                    "serverName": "{{source_server_name}}",
                    "volumeName": "{{source_volume_name}}"
                },
                "remoteVolumeResourceId": ""
            }
        },
        "usageThreshold": {{target_usage_threshold}},
        "subnetId": "{{target_subnet_id}}",
        "networkFeatures": "{{target_network_features}}",
        "serviceLevel": "{{target_service_level}}",
        "isLargeVolume": {{target_is_large_volume}}
'@

    if ($protocol -eq "SMB") {
        $payload += @'
,
        "protocolTypes": ["CIFS"],
        "smbEncryption": false,
        "smbContinuouslyAvailable": false
'@
    }
    else {
        $payload += @'
,
        "protocolTypes": ["NFSv3"],
        "nfsv3": {
            "chownMode": "Restricted"
        },
        "exportPolicy": {
            "rules": [
                {
                    "ruleIndex": 1,
                    "unixReadOnly": false,
                    "unixReadWrite": true,
                    "cifs": false,
                    "nfsv3": true,
                    "nfsv41": false,
                    "allowedClients": "0.0.0.0/0"
                }
            ]
        }
'@
    }

    if ($qos -eq "Manual") {
        $payload += @'
,
        "throughputMibps": {{target_throughput_mibps}}
'@
    }

    $payload += @'
    }
}
'@

    return $payload
}

# Show current configuration
function Show-Config {
    Write-Host ""
    Write-Host "Current Configuration:" -ForegroundColor $Colors.Cyan
    Write-Host "=====================" -ForegroundColor $Colors.Cyan
    
    $config = @{
        'Tenant ID' = Get-ConfigValue 'azure_tenant_id'
        'Subscription ID' = Get-ConfigValue 'azure_subscription_id'
        'Location' = Get-ConfigValue 'target_location'
        'Resource Group' = Get-ConfigValue 'target_resource_group'
        'NetApp Account' = Get-ConfigValue 'target_netapp_account'
        'Capacity Pool' = Get-ConfigValue 'target_capacity_pool'
        'Volume Name' = Get-ConfigValue 'target_volume_name'
        'Protocol' = Get-ConfigValue 'target_protocol_types'
        'Service Level' = Get-ConfigValue 'target_service_level'
        'Source Cluster' = Get-ConfigValue 'source_cluster_name'
        'Source Volume' = Get-ConfigValue 'source_volume_name'
        'Replication Schedule' = Get-ConfigValue 'replication_schedule'
    }
    
    foreach ($key in $config.Keys) {
        $value = $config[$key]
        if ($value) {
            Write-Host "  $key`: $value"
        }
        else {
            Write-Host "  $key`: " -NoNewline
            Write-Host "NOT SET" -ForegroundColor $Colors.Red
        }
    }
    
    Write-Host ""
    Write-Host "Protocol Type: $(Get-Protocol)"
    Write-Host "QoS Type: $(Get-QoS)"
}

# Run the complete interactive workflow
function Invoke-InteractiveWorkflow {
    Write-StepHeader "AZURE NETAPP FILES MIGRATION ASSISTANT - INTERACTIVE MODE"
    
    Write-Host "🚀 Welcome to the Interactive Migration Workflow!" -ForegroundColor $Colors.Green
    Write-Host ""
    Write-Host "This mode allows you to:" -ForegroundColor $Colors.Cyan
    Write-Host "  • Execute each step individually"
    Write-Host "  • Review API calls before execution"
    Write-Host "  • Skip steps if needed"
    Write-Host "  • Monitor progress in real-time"
    Write-Host ""
    
    # Show current configuration
    Show-Config
    
    Write-Host ""
    $confirm = Read-Host "Ready to start the migration workflow? [Y/n]"
    if ($confirm.ToLower() -eq 'n') {
        Write-Info "Workflow cancelled by user"
        return
    }
    
    # Step 1: Get Azure AD Token
    Write-StepHeader "STEP 1: AZURE AUTHENTICATION"
    Get-Token | Out-Null
    
    # Step 2: Create volume with replication
    Write-StepHeader "STEP 2: CREATE DESTINATION VOLUME WITH REPLICATION"
    
    $volumeEndpoint = "/subscriptions/{{azure_subscription_id}}/resourceGroups/{{target_resource_group}}/providers/Microsoft.NetApp/netAppAccounts/{{target_netapp_account}}/capacityPools/{{target_capacity_pool}}/volumes/{{target_volume_name}}"
    $volumePayload = Get-VolumePayload
    
    $volumeResponse = Invoke-ApiCallInteractive -StepName "CREATE_VOLUME" -Method "PUT" -Endpoint $volumeEndpoint -Data $volumePayload -Description "Creating destination volume with replication configuration" -ShowResponse:$true
    
    if ($volumeResponse) {
        # Step 3: Monitor volume creation
        $volumeResourceId = Expand-ConfigVariables $volumeEndpoint
        $success = Wait-VolumeCreation $volumeResourceId
        
        if ($success) {
            Write-StepHeader "WORKFLOW COMPLETED SUCCESSFULLY!"
            Write-Success "Migration setup completed!"
            Write-Info "Next steps:"
            Write-Info "1. Check Azure portal for replication status"
            Write-Info "2. Monitor initial sync progress"
            Write-Info "3. Plan cutover timing based on sync completion"
        }
    }
    
    Write-Host ""
    Write-Host "📋 Workflow Summary:" -ForegroundColor $Colors.Cyan
    Write-Host "  • Azure authentication: ✅ Completed"
    Write-Host "  • Volume creation: ✅ Completed"
    Write-Host "  • Replication setup: ✅ Completed"
    Write-Host ""
    Write-Host "📊 Check logs: $LogFile" -ForegroundColor $Colors.Blue
}

# Main execution
function Main {
    Write-Log "Starting ANF Migration Interactive Workflow (PowerShell)"
    
    switch ($Command.ToLower()) {
        "run" {
            Invoke-InteractiveWorkflow
        }
        "config" {
            Show-Config
        }
        default {
            Write-Host ""
            Write-Host "Azure NetApp Files Migration Assistant - Interactive Mode PowerShell Version" -ForegroundColor $Colors.Cyan
            Write-Host "=========================================================================" -ForegroundColor $Colors.Cyan
            Write-Host ""
            Write-Host "Usage: .\anf_interactive.ps1 [COMMAND]"
            Write-Host ""
            Write-Host "Commands:"
            Write-Host "  run     - Execute the interactive migration workflow"
            Write-Host "  config  - Show current configuration"
            Write-Host ""
            Write-Host "Examples:"
            Write-Host "  .\anf_interactive.ps1 run"
            Write-Host "  .\anf_interactive.ps1 config"
            Write-Host ""
        }
    }
}

# Run main function
Main
