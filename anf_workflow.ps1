# Azure NetApp Files Migration Assistant - Dynamic Workflow PowerShell Version
# Reads configuration from config.yaml at runtime

param(
    [string]$Command = "help"
)

# Configuration
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigFile = Join-Path $ScriptDir "config.yaml"
$TokenFile = Join-Path $ScriptDir ".token"
$LogFile = Join-Path $ScriptDir "anf_migration.log"

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

# Info message
function Write-Info {
    param([string]$Message)
    Write-Host "ℹ️  $Message" -ForegroundColor $Colors.Blue
    Write-Log "INFO: $Message"
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

# Execute a REST API call with current config values
function Invoke-ApiCall {
    param(
        [string]$StepName,
        [string]$Method,
        [string]$Endpoint,
        [string]$Data = "",
        [string]$Description
    )
    
    Write-Info "Step: $StepName - $Description"
    
    # Ensure we have a valid token
    if (-not (Test-Path $TokenFile)) {
        Get-Token
    }
    
    $token = Get-Content $TokenFile -Raw
    $apiUrl = Get-ConfigValue 'azure_api_base_url'
    $apiVersion = Get-ConfigValue 'azure_api_version'
    
    # Build the full URL
    $fullUrl = "${apiUrl}${Endpoint}?api-version=${apiVersion}"
    
    # Replace variables in URL and data
    $fullUrl = Expand-ConfigVariables $fullUrl
    
    # Prepare headers
    $headers = @{
        'Authorization' = "Bearer $token"
        'Content-Type' = 'application/json'
    }
    
    try {
        if ($Data) {
            $expandedData = Expand-ConfigVariables $Data
            $response = Invoke-RestMethod -Uri $fullUrl -Method $Method -Headers $headers -Body $expandedData
        }
        else {
            $response = Invoke-RestMethod -Uri $fullUrl -Method $Method -Headers $headers
        }
        
        Write-Success "Completed: $StepName"
        return $response
    }
    catch {
        Write-ErrorExit "API call failed: $StepName - $($_.Exception.Message)"
    }
}

# Get protocol type from config
function Get-Protocol {
    $protocol = Get-ConfigValue 'target_protocol_types'
    
    switch ($protocol.ToUpper()) {
        "NFSV3" { return "NFSv3" }
        "NFSV4.1" { return "NFSv4.1" }
        "CIFS" { return "SMB" }
        "SMB" { return "SMB" }
        default { return "NFSv3" }
    }
}

# Get QoS type from config
function Get-QoS {
    $throughput = Get-ConfigValue 'target_throughput_mibps'
    
    if ($throughput -and $throughput.Trim()) {
        return "Manual"
    }
    else {
        return "Auto"
    }
}

# Generate volume creation payload based on protocol/QoS
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
        'API Version' = Get-ConfigValue 'azure_api_version'
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

# Run the complete workflow
function Invoke-Workflow {
    Write-Info "Starting Azure NetApp Files Migration Workflow"
    
    # Step 1: Get token
    Get-Token | Out-Null
    
    # Step 2: Create volume with replication
    Write-Info "Creating destination volume with replication..."
    
    $volumeEndpoint = "/subscriptions/{{azure_subscription_id}}/resourceGroups/{{target_resource_group}}/providers/Microsoft.NetApp/netAppAccounts/{{target_netapp_account}}/capacityPools/{{target_capacity_pool}}/volumes/{{target_volume_name}}"
    $volumePayload = Get-VolumePayload
    
    Invoke-ApiCall -StepName "CREATE_VOLUME" -Method "PUT" -Endpoint $volumeEndpoint -Data $volumePayload -Description "Creating destination volume with replication configuration" | Out-Null
    
    Write-Success "Workflow completed successfully!"
    Write-Info "Check the Azure portal to monitor the replication status"
}

# Main execution
function Main {
    Write-Log "Starting ANF Migration Workflow (PowerShell)"
    
    switch ($Command.ToLower()) {
        "run" {
            Invoke-Workflow
        }
        "config" {
            Show-Config
        }
        "token" {
            Get-Token
        }
        default {
            Write-Host ""
            Write-Host "Azure NetApp Files Migration Workflow - PowerShell Version" -ForegroundColor $Colors.Cyan
            Write-Host "=========================================================" -ForegroundColor $Colors.Cyan
            Write-Host ""
            Write-Host "Usage: .\anf_workflow.ps1 [COMMAND]"
            Write-Host ""
            Write-Host "Commands:"
            Write-Host "  run     - Execute the complete migration workflow"
            Write-Host "  config  - Show current configuration"
            Write-Host "  token   - Get new Azure AD token"
            Write-Host ""
            Write-Host "Examples:"
            Write-Host "  .\anf_workflow.ps1 run"
            Write-Host "  .\anf_workflow.ps1 config"
            Write-Host ""
        }
    }
}

# Run main function
Main
