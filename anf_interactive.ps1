[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('menu','setup','peering','break','monitor','config','diagnose','token','help')]
    [string]$Command = 'menu',

    [Parameter(Position = 1)]
    [string]$Config = 'config.json'
)

# Azure NetApp Files Migration Assistant - PowerShell Interactive Tool
# Goal: Replace anf_interactive.sh with a Windows-native experience.

$Script:ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$Script:LogFile    = Join-Path $Script:ScriptRoot 'anf_migration_interactive.log'
$Script:ConfigPath = if ([System.IO.Path]::IsPathRooted($Config)) { $Config } else { Join-Path $Script:ScriptRoot $Config }
$Script:AuthToken  = $null
$Script:InteractionMode     = 'full'
$Script:MonitoringMode      = 'full'
$Script:MigrationSyncStarted = $false

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = 'INFO'
    )
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$timestamp] [$Level] $Message"
    Add-Content -Path $Script:LogFile -Value $line
}

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO]  $Message" -ForegroundColor Cyan
    Write-Log -Message $Message -Level 'INFO'
}

function Write-Success {
    param([string]$Message)
    Write-Host "[OK]    $Message" -ForegroundColor Green
    Write-Log -Message $Message -Level 'SUCCESS'
}

function Write-Warn {
    param([string]$Message)
    Write-Host "[WARN]  $Message" -ForegroundColor Yellow
    Write-Log -Message $Message -Level 'WARN'
}

function Write-ErrorStyled {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
    Write-Log -Message $Message -Level 'ERROR'
}

function Read-AnfYesNo {
    param(
        [string]$Question,
        [bool]$DefaultYes = $false
    )

    $defaultPrompt = if ($DefaultYes) { '(Y/n)' } else { '(y/N)' }

    while ($true) {
        $answer = Read-Host "$Question $defaultPrompt"
        if ([string]::IsNullOrWhiteSpace($answer)) {
            return $DefaultYes
        }

        switch -Regex ($answer.Trim()) {
            '^(y|yes)$' { return $true }
            '^(n|no)$'  { return $false }
            default {
                Write-Warn "Please answer yes (y) or no (n)."
            }
        }
    }
}

function Test-Dependency {
    param([string]$CommandName)
    if (Get-Command $CommandName -ErrorAction SilentlyContinue) {
        return $true
    }
    Write-ErrorStyled "Required command '$CommandName' was not found in PATH."
    return $false
}

function Get-AnfConfig {
    [OutputType([pscustomobject])]
    param(
        [string]$Path
    )

    if (-not (Test-Path -Path $Path)) {
        throw "Config file not found: $Path"
    }

    try {
        $raw = Get-Content -Path $Path -Raw
        $json = $raw | ConvertFrom-Json
    }
    catch {
        throw "Failed to parse config JSON at '$Path': $($_.Exception.Message)"
    }

    if (-not $json.variables -or -not $json.secrets) {
        throw "Config JSON must contain 'variables' and 'secrets' objects."
    }

    [pscustomobject]@{
        Path      = $Path
        Variables = $json.variables
        Secrets   = $json.secrets
    }
}

function Show-AnfConfig {
    param([pscustomobject]$ConfigObject)

    $v = $ConfigObject.Variables

    Write-Host "" 
    Write-Host "=== Current Configuration (`$($ConfigObject.Path)`) ===" -ForegroundColor Magenta

    Write-Host "Azure:" -ForegroundColor White
    Write-Host "  Tenant ID        : $($v.azure_tenant_id)"
    Write-Host "  Subscription ID  : $($v.azure_subscription_id)"
    Write-Host "  App ID           : $($v.azure_app_id)"
    Write-Host "  API Base URL     : $($v.azure_api_base_url)"
    Write-Host "  Auth Base URL    : $($v.azure_auth_base_url)"
    Write-Host "  API Version      : $($v.azure_api_version)"
    Write-Host "" 

    Write-Host "Target ANF:" -ForegroundColor White
    Write-Host "  Location         : $($v.target_location)"
    Write-Host "  Resource Group   : $($v.target_resource_group)"
    Write-Host "  NetApp Account   : $($v.target_netapp_account)"
    Write-Host "  Capacity Pool    : $($v.target_capacity_pool)"
    Write-Host "  Service Level    : $($v.target_service_level)"
    Write-Host "  Volume Name      : $($v.target_volume_name)"

    $bytes = [int64]$v.target_usage_threshold
    if ($bytes -gt 0) {
        $gib = [math]::Floor($bytes / 1GB)
        Write-Host "  Volume Size      : $gib GiB ($bytes bytes)"
    } else {
        Write-Host "  Volume Size      : <not set>"
    }

    Write-Host "  Protocol         : $($v.target_protocol_types)"
    Write-Host "  Large Volume     : $($v.target_is_large_volume)"
    Write-Host "  Subnet ID        : $($v.target_subnet_id)"

    if ($v.target_zones) {
        $zones = ($v.target_zones | ForEach-Object { $_ }) -join ', '
        Write-Host "  Zones            : $zones"
    }

    if ($v.target_throughput_mibps -and $v.target_throughput_mibps.ToString().Trim()) {
        Write-Host "  Manual QoS       : $($v.target_throughput_mibps) MiB/s"
    } else {
        Write-Host "  Manual QoS       : <auto>"
    }

    Write-Host "" 
    Write-Host "Source ONTAP:" -ForegroundColor White
    Write-Host "  Cluster Name     : $($v.source_cluster_name)"
    Write-Host "  SVM Name         : $($v.source_svm_name)"
    Write-Host "  Volume Name      : $($v.source_volume_name)"

    if ($v.source_peer_addresses) {
        if ($v.source_peer_addresses -is [System.Collections.IEnumerable]) {
            $peers = ($v.source_peer_addresses | ForEach-Object { $_ }) -join ', '
        } else {
            $peers = $v.source_peer_addresses.ToString()
        }
        Write-Host "  Peer Addresses   : $peers"
    }

    Write-Host "" 
    Write-Host "Replication:" -ForegroundColor White
    Write-Host "  Schedule         : $($v.replication_schedule)"

    Write-Host "" 
}

function Invoke-AnfShowEditConfig {
    param([pscustomobject]$ConfigObject)

    # Always reload config from disk so changes made outside this process are visible
    try {
        $ConfigObject = Get-AnfConfig -Path $Script:ConfigPath
    } catch {
        Write-ErrorStyled $_.Exception.Message
        return
    }

    Show-AnfConfig -ConfigObject $ConfigObject

    Write-Host "" 
    Write-Host "Edit options:" -ForegroundColor White
    Write-Host "  1) Edit in Notepad"
    Write-Host "  2) Run interactive setup wizard in this console"
    Write-Host "  0) Skip editing"
    Write-Host "" 
    $choice = Read-Host "Choose an option [1/2/0]"

    switch ($choice) {
        '1' {
            try {
                Write-Info "Opening config in Notepad: $($ConfigObject.Path)"
                Start-Process notepad.exe $ConfigObject.Path | Out-Null
            }
            catch {
                Write-ErrorStyled "Failed to launch Notepad: $($_.Exception.Message)"
            }
        }
        '2' {
            Invoke-AnfSetupWizard -ConfigPath $ConfigObject.Path
        }
        default {
            Write-Info "Skipping config edit."
        }
    }
}

function Invoke-AnfSetupWizard {
    param(
        [string]$ConfigPath
    )

    Write-Host "" 
    Write-Host "============================================" -ForegroundColor Green
    Write-Host " Azure NetApp Files Migration Assistant" -ForegroundColor Green
    Write-Host " Interactive Setup Wizard (JSON)" -ForegroundColor Green
    Write-Host "============================================" -ForegroundColor Green
    Write-Host "Config file: $ConfigPath" -ForegroundColor Gray
    Write-Host "" 
    Write-Host "This wizard will walk you through the required values." -ForegroundColor Gray
    Write-Host "Press ENTER to keep the value shown in [brackets] or type a new value to change it." -ForegroundColor Gray
    Write-Host "You can always edit the raw JSON later via the Show / Edit option in the main menu." -ForegroundColor Gray
    Write-Host "" 

    # Load existing config or template/new
    $configJson = $null
    $templatePath = Join-Path $Script:ScriptRoot 'config.template.json'

    if (Test-Path -Path $ConfigPath) {
        try {
            $configJson = (Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json)
            Write-Info "Loaded existing config.json"
        } catch {
            Write-Warn "Existing config.json is invalid JSON. Starting from template or blank."
        }
    }

    if (-not $configJson) {
        if (Test-Path -Path $templatePath) {
            try {
                $configJson = (Get-Content -Path $templatePath -Raw | ConvertFrom-Json)
                Write-Info "Loaded config.template.json as starting point"
            } catch {
                Write-Warn "Template config.template.json is invalid JSON. Starting with empty config."
            }
        }
    }

    if (-not $configJson) {
        $configJson = [pscustomobject]@{
            secrets   = @{}
            variables = @{}
        }
    }

    if (-not $configJson.variables) { $configJson | Add-Member -MemberType NoteProperty -Name variables -Value (@{}) }
    if (-not $configJson.secrets)   { $configJson | Add-Member -MemberType NoteProperty -Name secrets   -Value (@{}) }

    $v = $configJson.variables
    $s = $configJson.secrets

    function Read-Field {
        param(
            [string]$Prompt,
            [object]$Current,
            [switch]$Required
        )
        $defaultText = if ($null -ne $Current -and $Current.ToString().Length -gt 0) { " [$Current]" } else { "" }
        while ($true) {
            $value = Read-Host "$Prompt$defaultText"
            if ([string]::IsNullOrWhiteSpace($value)) {
                if ($Required -and ([string]::IsNullOrWhiteSpace([string]$Current))) {
                    Write-Warn "This field is required."
                    continue
                }
                return $Current
            }
            return $value
        }
    }

    # Azure basics
    Write-Host "Azure configuration" -ForegroundColor White
    Write-Host "Use an Azure AD service principal with NetApp Contributor permissions on the target subscription." -ForegroundColor Gray
    Write-Host "If you haven't created one, you can run 'az ad sp create-for-rbac --name ANFMigrate' in Azure Cloud Shell." -ForegroundColor Gray
    Write-Host "" 

    $v.azure_subscription_id = Read-Field "Azure Subscription ID" $v.azure_subscription_id -Required
    $v.azure_tenant_id       = Read-Field "Azure Tenant ID"       $v.azure_tenant_id       -Required
    $v.azure_app_id          = Read-Field "Azure App (Client) ID" $v.azure_app_id          -Required

    # Auth URL options (Commercial/Gov/Custom) like original wizard
    Write-Host "" -ForegroundColor Gray
    Write-Host "Auth URL options:" -ForegroundColor Gray
    Write-Host "  1. Commercial (default) - https://login.microsoftonline.com/" -ForegroundColor Gray
    Write-Host "  2. Government          - https://login.microsoftonline.us/" -ForegroundColor Gray
    Write-Host "  3. Other               - specify custom URL" -ForegroundColor Gray

    $currentAuth = ($v.azure_auth_base_url  ?? 'https://login.microsoftonline.com/')
    $currentSelection = if ($currentAuth -like '*login.microsoftonline.com*') { '1' }
                        elseif ($currentAuth -like '*login.microsoftonline.us*') { '2' }
                        else { '3' }

    $authChoice = Read-Field "Select Auth URL (1/2/3)" $currentSelection -Required
    switch ($authChoice) {
        '1' {
            $v.azure_auth_base_url = 'https://login.microsoftonline.com/'
        }
        '2' {
            $v.azure_auth_base_url = 'https://login.microsoftonline.us/'
        }
        '3' {
            $v.azure_auth_base_url = Read-Field "Custom Auth base URL" $currentAuth -Required
        }
        default {
            Write-Warn "Unrecognized choice. Using Commercial default (https://login.microsoftonline.com/)."
            $v.azure_auth_base_url = 'https://login.microsoftonline.com/'
        }
    }

    $v.azure_api_base_url    = Read-Field "API base URL"          ($v.azure_api_base_url   ?? 'https://management.azure.com')
    $v.azure_api_version     = Read-Field "API version"           ($v.azure_api_version    ?? '2025-06-01')
    Write-Host "" 
    Write-Host "Target ANF configuration" -ForegroundColor White

    # Azure region with soft validation similar to original wizard
    $validRegions = @(
        'eastus','eastus2','westus','westus2','westus3','centralus','northcentralus','southcentralus',
        'canadacentral','canadaeast','brazilsouth','northeurope','westeurope','francecentral',
        'uksouth','ukwest','germanywc','norwayeast','switzerlandnorth','uaenorth',
        'southafricanorth','australiaeast','australiasoutheast','southeastasia','eastasia',
        'japaneast','japanwest','koreacentral','centralindia','southindia','westindia'
    )
    while ($true) {
        $loc = Read-Field "Target Azure region (e.g. eastus)" ($v.target_location ?? 'eastus') -Required
        if ($validRegions -contains $loc.ToLowerInvariant()) {
            $v.target_location = $loc
            break
        }
        Write-Warn "'$loc' might not be a recognized Azure region."
        $cont = Read-Host "Continue anyway with this region? (Y/n)"
        if ([string]::IsNullOrWhiteSpace($cont) -or $cont -match '^[Yy]') {
            $v.target_location = $loc
            break
        }
    }

    $v.target_resource_group = Read-Field "Target resource group"               $v.target_resource_group  -Required
    $v.target_netapp_account = Read-Field "NetApp account name"                 $v.target_netapp_account  -Required
    $v.target_capacity_pool  = Read-Field "Capacity pool name"                  $v.target_capacity_pool   -Required

    # Service level with validation like original
    while ($true) {
        $level = Read-Field "Service level (Standard/Premium/Ultra)" ($v.target_service_level ?? 'Standard') -Required
        if (@('Standard','Premium','Ultra') -contains $level) {
            $v.target_service_level = $level
            break
        }
        Write-Warn "Service level must be one of: Standard, Premium, Ultra."
    }
    $v.target_volume_name    = Read-Field "Target volume name"                  $v.target_volume_name     -Required

    # Volume size in GiB -> bytes
    $currentBytes = 0
    if ($v.target_usage_threshold) { [void][int64]::TryParse($v.target_usage_threshold.ToString(), [ref]$currentBytes) }
    $currentGiB = if ($currentBytes -gt 0) { [math]::Floor($currentBytes / 1GB) } else { 100 }
    $sizeGiB    = Read-Field "Target volume size in GiB" $currentGiB -Required
    if ($sizeGiB -match '^[0-9]+$') {
        $v.target_usage_threshold = [int64]$sizeGiB * 1GB
    } else {
        Write-Warn "Invalid size entered; keeping previous value ($currentBytes bytes)."
    }

    # Protocol with validation like original
    while ($true) {
        $proto = Read-Field "Protocol (CIFS/NFSv3/NFSv4.1)" ($v.target_protocol_types ?? 'CIFS') -Required
        if (@('CIFS','NFSv3','NFSv4.1') -contains $proto) {
            $v.target_protocol_types = $proto
            break
        }
        Write-Warn "Protocol must be one of: CIFS, NFSv3, NFSv4.1."
    }

    Write-Host "" -ForegroundColor Gray
    Write-Host "Subnet resource ID should look like:" -ForegroundColor Gray
    Write-Host "  /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Network/virtualNetworks/<vnet>/subnets/<subnet>" -ForegroundColor Gray
    $v.target_subnet_id      = Read-Field "Subnet resource ID"               $v.target_subnet_id -Required

    # Availability zones as simple number -> array (0 = no zone)
    $currentZone = $null
    if ($v.target_zones) {
        if ($v.target_zones -is [System.Collections.IEnumerable]) {
            $currentZone = ($v.target_zones | Select-Object -First 1)
        } else {
            $currentZone = $v.target_zones
        }
    }
    while ($true) {
        $zoneInput = Read-Field "Availability zone (0 for none, 1/2/3 for specific AZ)" $currentZone
        if ([string]::IsNullOrWhiteSpace($zoneInput)) {
            # Keep existing value
            break
        }
        switch ($zoneInput) {
            '0' {
                $v.target_zones = @()
                break
            }
            '1' { $v.target_zones = @('1'); break }
            '2' { $v.target_zones = @('2'); break }
            '3' { $v.target_zones = @('3'); break }
            default {
                Write-Warn "Availability zone must be 0 (none), 1, 2, or 3."
            }
        }
        if ($zoneInput -in '0','1','2','3') { break }
    }

    # Optional QoS throughput (0 or blank = Auto)
    $qosInput = Read-Field "Manual QoS throughput (MiB/s, 0 or blank for auto)" $v.target_throughput_mibps
    if ([string]::IsNullOrWhiteSpace($qosInput) -or $qosInput -eq '0') {
        $v.target_throughput_mibps = ""
    } else {
        $v.target_throughput_mibps = $qosInput
    }

    Write-Host "" 
    Write-Host "Source ONTAP configuration" -ForegroundColor White
    Write-Host "Log into your ONTAP cluster (ssh admin@<cluster-mgmt-IP>) and use CLI commands to find these values." -ForegroundColor Gray
    Write-Host "  • Cluster name:      cluster identity show" -ForegroundColor Gray
    Write-Host "  • Volumes & SVM:     volume show" -ForegroundColor Gray
    Write-Host "  • SVM for a volume:  volume show -volume <VOLUME> -fields vserver" -ForegroundColor Gray
    Write-Host "" -ForegroundColor Gray
    $v.source_cluster_name = Read-Field "Source cluster name/hostname" $v.source_cluster_name -Required
    $v.source_svm_name     = Read-Field "Source SVM name"           $v.source_svm_name -Required
    $v.source_volume_name  = Read-Field "Source volume name"        $v.source_volume_name -Required

    # Peer addresses as comma-separated list
    $currentPeers = $null
    if ($v.source_peer_addresses) {
        if ($v.source_peer_addresses -is [System.Collections.IEnumerable]) {
            $currentPeers = ($v.source_peer_addresses -join ',')
        } else {
            $currentPeers = $v.source_peer_addresses.ToString()
        }
    }
    Write-Host "" -ForegroundColor Gray
    Write-Host "You can find LIF IP addresses in ONTAP with:" -ForegroundColor Gray
    Write-Host "  network interface show -vserver <SVM> -fields address" -ForegroundColor Gray
    $peerInput = Read-Field "Peer IP addresses (comma-separated, blank to keep)" $currentPeers
    if (-not [string]::IsNullOrWhiteSpace($peerInput)) {
        $v.source_peer_addresses = $peerInput.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    }

    Write-Host "" 
    Write-Host "Replication settings" -ForegroundColor White
    Write-Host "Common schedules are Hourly, Daily, or Weekly. This controls how often ONTAP updates the replication." -ForegroundColor Gray
    while ($true) {
        $sched = Read-Field "Replication schedule (Hourly/Daily/Weekly)" ($v.replication_schedule ?? 'Hourly')
        if (@('Hourly','Daily','Weekly') -contains $sched) {
            $v.replication_schedule = $sched
            break
        }
        Write-Warn "Replication schedule must be one of: Hourly, Daily, Weekly."
    }

    # Build a ConfigObject for summary
    $summaryObject = [pscustomobject]@{
        Path      = $ConfigPath
        Variables = $v
        Secrets   = $s
    }

    Write-Host "" 
    Write-Host "Summary of updated configuration:" -ForegroundColor Magenta
    Show-AnfConfig -ConfigObject $summaryObject

    $save = Read-Host "Save changes to $ConfigPath? (Y/n)"
    if ([string]::IsNullOrWhiteSpace($save) -or $save -match '^[Yy]') {
        try {
            $jsonOut = $configJson | ConvertTo-Json -Depth 10
            Set-Content -Path $ConfigPath -Value $jsonOut
            Write-Success "Configuration saved to $ConfigPath"
        } catch {
            Write-ErrorStyled "Failed to save configuration: $($_.Exception.Message)"
        }
    } else {
        Write-Warn "Changes discarded."
    }
}

function Get-AnfAuthToken {
    param([pscustomobject]$ConfigObject)

    if ($Script:AuthToken) {
        return $Script:AuthToken
    }

    $v = $ConfigObject.Variables
    $s = $ConfigObject.Secrets

    $tenantId     = $v.azure_tenant_id
    $clientId     = $v.azure_app_id
    $clientSecret = $s.azure_app_secret
    $authBase     = $v.azure_auth_base_url.TrimEnd('/')
    $resource     = $v.azure_api_base_url
    $apiVersion   = $v.azure_api_version

    if (-not $tenantId -or -not $clientId -or -not $clientSecret) {
        throw "Missing azure_tenant_id, azure_app_id, or azure_app_secret in config."
    }

    $tokenUri = "$authBase/$tenantId/oauth2/token?api-version=$apiVersion"

    $body = @{
        grant_type    = 'client_credentials'
        client_id     = $clientId
        client_secret = $clientSecret
        resource      = $resource
    }

    try {
        # Non-interactive: just get the token, minimal noise
        $resp = Invoke-RestMethod -Method Post -Uri $tokenUri -Body $body -ContentType 'application/x-www-form-urlencoded'
    }
    catch {
        Write-ErrorStyled "Token request failed: $($_.Exception.Message)"
        throw
    }

    if (-not $resp.access_token) {
        throw "Token response did not contain access_token."
    }

    $Script:AuthToken = $resp.access_token

    # Persist to .token for parity with old script
    $tokenFile = Join-Path $Script:ScriptRoot '.token'
    try {
        Set-Content -Path $tokenFile -Value $Script:AuthToken -NoNewline
    } catch { }

    return $Script:AuthToken
}

function Invoke-AnfAuthTokenStep {
    param([pscustomobject]$ConfigObject)

    # Refresh config from disk so latest values are used
    try {
        $ConfigObject = Get-AnfConfig -Path $Script:ConfigPath
    } catch {
        Write-ErrorStyled $_.Exception.Message
        return
    }

    $v = $ConfigObject.Variables
    $s = $ConfigObject.Secrets

    $tenantId     = $v.azure_tenant_id
    $clientId     = $v.azure_app_id
    $clientSecret = $s.azure_app_secret
    $authBase     = $v.azure_auth_base_url.TrimEnd('/')
    $resource     = $v.azure_api_base_url
    $apiVersion   = $v.azure_api_version

    if (-not $tenantId -or -not $clientId -or -not $clientSecret) {
        Write-ErrorStyled "Missing azure_tenant_id, azure_app_id, or azure_app_secret in config."
        return
    }

    $tokenUri = "$authBase/$tenantId/oauth2/token?api-version=$apiVersion"

    Write-Host "" 
    Write-Host "============================================" -ForegroundColor Magenta
    Write-Host " Step: get_authentication_token" -ForegroundColor Magenta
    Write-Host "============================================" -ForegroundColor Magenta
    Write-Host "" 

    Write-Info "Making OAuth2 token request..."
    Write-Host "Method: POST" -ForegroundColor Cyan
    Write-Host "URL:    $tokenUri" -ForegroundColor Cyan
    Write-Host ("Body:   grant_type=client_credentials&client_id={0}&client_secret=***HIDDEN***&resource={1}" -f $clientId, $resource) -ForegroundColor Cyan
    Write-Host "" 

    $body = @{
        grant_type    = 'client_credentials'
        client_id     = $clientId
        client_secret = $clientSecret
        resource      = $resource
    }

    Write-Log -Message "Token Request: POST $tokenUri" -Level 'AUTH'

    try {
        $resp = Invoke-WebRequest -Method Post -Uri $tokenUri -Body $body -ContentType 'application/x-www-form-urlencoded' -SkipHttpErrorCheck
    }
    catch {
        Write-ErrorStyled "Token request failed: $($_.Exception.Message)"
        return
    }

    $statusCode = [int]$resp.StatusCode
    Write-Host "" 
    Write-Host "═══ TOKEN RESPONSE ═══" -ForegroundColor DarkMagenta
    Write-Host "HTTP Status: $statusCode" -ForegroundColor Cyan

    if ($statusCode -eq 200) {
        Write-Success "Token request completed successfully (HTTP $statusCode)"
    } else {
        Write-Warn "Unexpected HTTP status: $statusCode (expected: 200)"
    }

    # Show a few key headers
    Write-Host "Key Response Headers:" -ForegroundColor Cyan
    $resp.Headers.GetEnumerator() |
        Where-Object { $_.Name -match 'content-type|cache-control|expires' } |
        Select-Object -First 5 |
        ForEach-Object { Write-Host ("  {0}: {1}" -f $_.Name, $_.Value) }

    $content = $resp.Content
    if ([string]::IsNullOrWhiteSpace($content)) {
        Write-Host "(Empty response body)" -ForegroundColor Yellow
        return
    }

    # Sanitize body like old script: show token_type, expires_in, resource, hide access_token
    Write-Host "Response Body (sanitized):" -ForegroundColor Cyan
    try {
        $parsed    = $content | ConvertFrom-Json
        $sanitized = [pscustomobject]@{
            token_type   = $parsed.token_type
            expires_in   = $parsed.expires_in
            resource     = $parsed.resource
            access_token = if ($parsed.access_token) { '***TOKEN_HIDDEN***' } else { 'NOT_FOUND' }
        }
        $sanitized | ConvertTo-Json -Depth 5 | Out-Host
    }
    catch {
        Write-Warn "Could not parse JSON token response; showing raw body."
        Write-Host $content
    }

    # Extract and store token
    try {
        $parsed = $content | ConvertFrom-Json
    } catch {
        Write-ErrorStyled "Failed to parse token JSON to extract access_token."
        return
    }

    if (-not $parsed.access_token) {
        Write-ErrorStyled "Token response did not contain access_token."
        return
    }

    $Script:AuthToken = $parsed.access_token
    $tokenFile        = Join-Path $Script:ScriptRoot '.token'
    try {
        Set-Content -Path $tokenFile -Value $Script:AuthToken -NoNewline
        Write-Log -Message "Token stored securely in $tokenFile" -Level 'AUTH'
    } catch {
        Write-Warn ("Failed to persist token to {0}: {1}" -f $tokenFile, $_.Exception.Message)
    }

    Write-Host "" 
    Write-Success "Authentication token obtained and stored"
}

function Invoke-AnfApi {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [pscustomobject]$ConfigObject,
        [Parameter(Mandatory)] [ValidateSet('GET','POST','PUT','PATCH','DELETE')] [string]$Method,
        [Parameter(Mandatory)] [string]$Endpoint,   # e.g. /subscriptions/.../providers/Microsoft.NetApp/...
        [Parameter()] [object]$Body,
        [Parameter()] [string]$Description = '',
        [Parameter()] [int[]]$ExpectedStatus = @(200,201,202,204)
    )

    $v = $ConfigObject.Variables

    $baseUrl    = $v.azure_api_base_url.TrimEnd('/')
    $apiVersion = $v.azure_api_version

    # Simple placeholder replacement for {{variables}} in endpoint
    $endpointExpanded = $Endpoint
    foreach ($prop in $v.PSObject.Properties) {
        $placeholder = '{{' + $prop.Name + '}}'
        if ($endpointExpanded -like "*$placeholder*") {
            $endpointExpanded = $endpointExpanded -replace [regex]::Escape($placeholder), [string]$prop.Value
        }
    }

    # Build a well-formed ARM URI using UriBuilder to avoid malformed host/query strings
    $uriBuilder = [System.UriBuilder]$baseUrl
    if ([string]::IsNullOrWhiteSpace($uriBuilder.Path) -or $uriBuilder.Path -eq '/') {
        $uriBuilder.Path = $endpointExpanded.TrimStart('/')
    } else {
        $uriBuilder.Path = ($uriBuilder.Path.TrimEnd('/') + '/' + $endpointExpanded.TrimStart('/'))
    }
    $uriBuilder.Query = "api-version=$apiVersion"
    $uri = $uriBuilder.Uri.AbsoluteUri

    $token = Get-AnfAuthToken -ConfigObject $ConfigObject
    $headers = @{ Authorization = "Bearer $token" }

    Write-Host "" 
    Write-Host "=== API Call: $Method $uri ===" -ForegroundColor DarkCyan
    if ($Description) {
        Write-Host "Description: $Description" -ForegroundColor Gray
    }

    $bodyJson = $null
    if ($PSBoundParameters.ContainsKey('Body') -and $null -ne $Body) {
        if ($Body -is [string]) {
            $bodyJson = $Body
        } else {
            $bodyJson = $Body | ConvertTo-Json -Depth 10
        }
        Write-Host "Request Body (truncated):" -ForegroundColor Gray
        $preview = ($bodyJson -split "`n" | Select-Object -First 20) -join "`n"
        Write-Host $preview
        if (($bodyJson -split "`n").Count -gt 20) {
            Write-Host "... (truncated)" -ForegroundColor DarkYellow
        }
    }

    Write-Log -Message "API $Method $uri" -Level 'API'

    try {
        if ($bodyJson) {
            $resp = Invoke-WebRequest -Method $Method -Uri $uri -Headers $headers -Body $bodyJson -ContentType 'application/json' -SkipHttpErrorCheck
        } else {
            $resp = Invoke-WebRequest -Method $Method -Uri $uri -Headers $headers -SkipHttpErrorCheck
        }

        $status = [int]$resp.StatusCode
        $responseContent = $resp.Content

        Write-Host "Status Code: $status" -ForegroundColor Gray

        if (-not ($ExpectedStatus -contains $status)) {
            Write-Warn "Unexpected HTTP status code: $status (expected: $($ExpectedStatus -join ', '))"
        } else {
            Write-Success "Request completed with status $status"
        }

        if ($responseContent) {
            try {
                $parsed = $responseContent | ConvertFrom-Json
                Write-Host "Response (JSON):" -ForegroundColor Gray
                ($parsed | ConvertTo-Json -Depth 10) | Out-Host
                return $parsed
            } catch {
                Write-Host "Response (raw):" -ForegroundColor Gray
                Write-Host $responseContent
                return $responseContent
            }
        } else {
            Write-Host "(Empty response body)" -ForegroundColor DarkYellow
            return $null
        }
    }
    catch {
        Write-ErrorStyled "API call failed: $($_.Exception.Message)"
        throw
    }
}

function Test-AnfExistingClusterPeering {
    param([pscustomobject]$ConfigObject)

    $v = $ConfigObject.Variables
    $sourceCluster = $v.source_cluster_name

    Write-Host "" 
    Write-Host "Checking for Existing Cluster Peering" -ForegroundColor Magenta

    if (-not $sourceCluster) {
        Write-Warn "Source cluster name not configured - proceeding with cluster peering setup."
        return $false
    }

    Write-Info "Checking for existing cluster peering relationships in this capacity pool..."

    $endpoint = "/subscriptions/{{azure_subscription_id}}/resourceGroups/{{target_resource_group}}/providers/Microsoft.NetApp/netAppAccounts/{{target_netapp_account}}/capacityPools/{{target_capacity_pool}}/volumes"

    try {
        $response = Invoke-AnfApi -ConfigObject $ConfigObject -Method 'GET' -Endpoint $endpoint -Description "Check capacity pool for existing volumes with replication relationships" -ExpectedStatus @(200,201,202)
    }
    catch {
        Write-Warn "Could not check capacity pool volumes - proceeding with cluster peering setup."
        return $false
    }

    if (-not $response) {
        Write-Warn "No response when listing pool volumes - proceeding with cluster peering setup."
        return $false
    }

    $foundPeer   = $false
    $detailLines = @()

    if ($response.value) {
        foreach ($vol in $response.value) {
            $props = $vol.properties
            if ($props -and $props.dataProtection -and $props.dataProtection.replication) {
                $repl       = $props.dataProtection.replication
                $remoteVolId = $repl.remoteVolumeResourceId

                if ($remoteVolId -and $remoteVolId.ToString().ToLower().Contains($sourceCluster.ToLower())) {
                    $foundPeer   = $true
                    $volumeName  = $vol.name
                    $replSchedule= $repl.replicationSchedule
                    $mirrorState = $repl.mirrorState

                    $detailLines += "Volume: $volumeName"
                    $detailLines += "Remote Volume: $remoteVolId"
                    $detailLines += "Schedule: $replSchedule"
                    $detailLines += "Mirror State: $mirrorState"
                    break
                }
            }
        }
    }

    if ($foundPeer) {
        Write-Success "Found existing cluster peering relationship to source cluster '$sourceCluster'!"
        if ($detailLines.Count -gt 0) {
            Write-Host "" 
            Write-Host "Existing Peering Details:" -ForegroundColor Green
            $detailLines | ForEach-Object { Write-Host "  $_" }
        }
        Write-Host "" 
        Write-Info "Since cluster peering already exists between this Azure NetApp capacity pool"
        Write-Info "and your source cluster '$sourceCluster', you can reuse this"
        Write-Info "relationship for the new volume without recreating the cluster peer."
        Write-Host "" 

        if (Read-AnfYesNo -Question "Skip cluster peering setup and reuse existing relationship?" -DefaultYes:$true) {
            Write-Success "Skipping cluster peering setup - reusing existing cluster relationship."
            return $true
        } else {
            Write-Warn "User chose to proceed with cluster peering setup anyway."
            Write-Info "Note: This may succeed or fail depending on Azure NetApp Files behavior."
            return $false
        }
    } else {
        Write-Info "No existing cluster peering found to source cluster '$sourceCluster'."
        Write-Info "Proceeding with cluster peering setup."
        return $false
    }
}

function Show-AnfPeeringInstructions {
    param(
        [pscustomobject]$ConfigObject,
        [object]$AsyncProperties
    )

    if (-not $AsyncProperties) { return }

    $v = $ConfigObject.Variables

    $clusterCommand    = $AsyncProperties.clusterPeeringCommand
    $clusterPassphrase = $AsyncProperties.passphrase
    $svmCommand        = $AsyncProperties.SvmPeeringCommand
    if (-not $svmCommand -and $AsyncProperties.svmPeeringCommand) {
        $svmCommand = $AsyncProperties.svmPeeringCommand
    }

    # Try to extract the remote ANF cluster name from the cluster command for better guidance
    $remoteClusterName = $null
    if ($clusterCommand) {
        # Typical command looks like: cluster peer create -ipspace Default -encryption-protocol-proposed tls-psk -peer-addrs ... -peer-cluster-name az-sn2-...
        $m = [regex]::Match($clusterCommand, '-peer-cluster-name\s+(?<name>\S+)')
        if ($m.Success) {
            $remoteClusterName = $m.Groups['name'].Value
        }
    }

    if ($clusterCommand -and $clusterPassphrase) {
        Write-Host "" 
        Write-Host "Cluster Peer Command Retrieved:" -ForegroundColor Green
        Write-Host "EXECUTE THIS COMMAND ON YOUR ON-PREMISES ONTAP SYSTEM:" -ForegroundColor Cyan
        Write-Host "" 
        Write-Host $clusterCommand -ForegroundColor Yellow
        Write-Host "" 
        Write-Host "Passphrase:" -ForegroundColor Green
        Write-Host $clusterPassphrase -ForegroundColor Yellow
        Write-Host "" 
        Write-Host "Configuration Reference Values:" -ForegroundColor Blue

        $peerAddresses = $v.source_peer_addresses
        if ($peerAddresses -is [System.Collections.IEnumerable]) {
            $peerAddresses = ($peerAddresses | ForEach-Object { $_ }) -join ', '
        }

        Write-Host "  peer-addresses-list: $peerAddresses" -ForegroundColor Cyan
        Write-Host "" 
        Write-Host "Instructions:" -ForegroundColor Cyan
        Write-Host "  1. Log into your on-premises ONTAP system as an administrator"
        Write-Host "  2. This command uses IP space 'Default' - if your intercluster LIFs use a different IP space," -ForegroundColor Cyan
        Write-Host "     replace 'Default' with your actual IP space name before running the command." -ForegroundColor Cyan
        Write-Host "  3. Replace any remaining placeholders in the command with your actual values:" 
        Write-Host "     - Replace <peer-addresses-list> with the peer addresses shown above (if present)." -ForegroundColor Cyan
        Write-Host "  4. Execute the modified command" -ForegroundColor Cyan
        Write-Host "  5. When prompted, enter the passphrase shown above" -ForegroundColor Cyan
        Write-Host "  6. Verify the command completes successfully" -ForegroundColor Cyan
        Write-Host "  7. Return here and confirm completion" -ForegroundColor Cyan
        Write-Host "" 
        $displayClusterName = if ($remoteClusterName) { $remoteClusterName } else { '<remote_cluster_name>' }
        $errorLine = "If you see ONTAP error 'Cannot peer with two clusters of the name `"$displayClusterName`"':"
        Write-Host $errorLine -ForegroundColor Yellow
        Write-Host "  • This means a cluster peer to the ANF backend already exists." -ForegroundColor Yellow
        Write-Host "  • On ONTAP, run: 'cluster peer show' and look for that remote cluster name." -ForegroundColor Yellow
        Write-Host "    - If Availability is 'Available': reuse the existing peer (do not run 'cluster peer create' again)." -ForegroundColor Yellow
        Write-Host "    - If Availability is 'Unavailable' and the peer is stale:" -ForegroundColor Yellow
        Write-Host "        1) Make sure no SnapMirror / migration relationships still depend on it." -ForegroundColor Yellow
        $deleteLine = "        2) Delete it with: 'cluster peer delete -cluster $displayClusterName'."
        Write-Host $deleteLine -ForegroundColor Yellow
        Write-Host "        3) Then rerun the 'cluster peer create' command shown above." -ForegroundColor Yellow
        Write-Host "" 

        while ($true) {
            if (Read-AnfYesNo -Question "Have you successfully executed the cluster peer command on your ONTAP system?" -DefaultYes:$false) {
                Write-Success "Cluster peer command execution confirmed."
                break
            } else {
                Write-Host "" 
                Write-Warn "Please execute this cluster peer command on your ONTAP system:"
                Write-Host $clusterCommand -ForegroundColor Yellow
                Write-Host ("Passphrase: {0}" -f $clusterPassphrase) -ForegroundColor Yellow
                Write-Host ("Reference - peer addresses: {0}" -f $peerAddresses) -ForegroundColor Cyan
                Write-Host "The migration cannot proceed until this command is executed successfully." 
                Write-Host "" 
                if (Read-AnfYesNo -Question "Do you want to skip this step? (NOT RECOMMENDED - may cause migration failure)" -DefaultYes:$false) {
                    Write-Warn "Cluster peer step skipped by user - migration may fail."
                    break
                }
            }
        }
    }

    if ($svmCommand) {
        Write-Host "" 
        Write-Host "SVM Peering Command Retrieved:" -ForegroundColor Green
        Write-Host "EXECUTE THIS COMMAND ON YOUR ON-PREMISES ONTAP SYSTEM:" -ForegroundColor Cyan
        Write-Host "" 
        Write-Host $svmCommand -ForegroundColor Yellow
        Write-Host "" 

        $sourceSvm = $v.source_svm_name
        $targetSvm = $v.target_svm_name
        $targetVol = $v.target_volume_name

        Write-Host "Configuration Reference Values:" -ForegroundColor Blue
        Write-Host ("  source-svm-name: {0}" -f $sourceSvm) -ForegroundColor Cyan
        Write-Host "" 
        Write-Host "Instructions:" -ForegroundColor Cyan
        Write-Host "  1. Log into your on-premises ONTAP system as an administrator"
        Write-Host "  2. Execute the command as shown (no placeholders to replace)"
        Write-Host "  3. Verify the command completes successfully"
        Write-Host "  4. Confirm the snapmirror relationship is healthy using:" 
        Write-Host ("     snapmirror show -fields healthy -destination-path <dst_svm>:{0}" -f $targetVol) -ForegroundColor Yellow
        Write-Host "     (Should show 'healthy: true' in the output)"
        Write-Host "  5. Return here and confirm completion" 
        Write-Host "" 

        while ($true) {
            if (Read-AnfYesNo -Question "Have you successfully executed the SVM peering command on your ONTAP system?" -DefaultYes:$false) {
                Write-Success "SVM peering command execution confirmed."

                Write-Host "" 
                Write-Host "Data Synchronization Phase Started!" -ForegroundColor Green
                Write-Host "MIGRATION SETUP COMPLETE - DATA SYNC IN PROGRESS" -ForegroundColor Cyan
                Write-Host "" 
                Write-Host "What's happening now:" -ForegroundColor Blue
                Write-Host "  • Data is now synchronizing from your on-premises ONTAP system to Azure NetApp Files"
                Write-Host "  • This initial sync can take several hours or days depending on data size"
                Write-Host "  • The sync will continue automatically in the background"
                Write-Host "" 
                Write-Host "How to monitor sync progress:" -ForegroundColor Yellow
                Write-Host "  1. Go to the Azure Portal"
                Write-Host "  2. Navigate to your Azure NetApp Files volume"
                Write-Host "  3. Check the 'Metrics' section for replication progress"
                Write-Host "  4. Look for metrics like 'is Volume Replication Transferring' and 'Volume Replication Total Transfer'"
                Write-Host "" 
                Write-Host "Next steps:" -ForegroundColor Magenta
                Write-Host "  1. Wait for the initial data sync to complete (this can take hours/days)"
                Write-Host "  2. Monitor progress using Azure Portal metrics"
                Write-Host "  3. When ready to finalize the migration (break replication and make volume writable):"
                Write-Host "     Run this script again and select the 'break' workflow (Phase 3)"
                Write-Host "" 
                Write-Host "Important notes:" -ForegroundColor Cyan
                Write-Host "  • Do NOT break replication until you're ready to switch to the Azure volume"
                Write-Host "  • Breaking replication makes the Azure volume writable but stops sync from on-premises"
                Write-Host "  • Plan your cutover carefully to minimize downtime"
                Write-Host "" 

                $Script:MigrationSyncStarted = $true
                break
            } else {
                Write-Host "" 
                Write-Warn "Please execute this SVM peering command on your ONTAP system:"
                Write-Host $svmCommand -ForegroundColor Yellow
                Write-Host ("Reference - Source SVM: {0}, Target SVM: {1}" -f $sourceSvm, $targetSvm) -ForegroundColor Cyan
                Write-Host "The migration cannot proceed until this command is executed successfully." 
                Write-Host "" 
                if (Read-AnfYesNo -Question "Do you want to skip this step? (NOT RECOMMENDED - may cause migration failure)" -DefaultYes:$false) {
                    Write-Warn "SVM peering step skipped by user - migration may fail."
                    break
                }
            }
        }
    }
}

function Monitor-AnfAsyncOperation {
    param(
        [pscustomobject]$ConfigObject,
        [Parameter(Mandatory)][string]$AsyncUrl,
        [string]$StepName = ''
    )

    $maxAttempts = 120
    $attempt     = 1

    Write-Info "Monitoring asynchronous operation..."
    Write-Info "Will check every 60 seconds (max 2 hours)."

    $finalObject = $null

    while ($attempt -le $maxAttempts) {
        Write-Host "" 
        Write-Host ("Check {0}/{1} - {2}" -f $attempt, $maxAttempts, (Get-Date -Format 'HH:mm:ss')) -ForegroundColor Cyan

        $token   = Get-AnfAuthToken -ConfigObject $ConfigObject
        $headers = @{ Authorization = "Bearer $token" }

        try {
            $resp = Invoke-WebRequest -Method 'GET' -Uri $AsyncUrl -Headers $headers -SkipHttpErrorCheck
        }
        catch {
            Write-Warn "Failed to check status (attempt $attempt): $($_.Exception.Message)"
            $resp = $null
        }

        if ($resp) {
            $content = $resp.Content
            $obj     = $null
            if (-not [string]::IsNullOrWhiteSpace($content)) {
                try { $obj = $content | ConvertFrom-Json } catch { $obj = $null }
            }

            if ($obj) {
                $status  = $obj.status
                $percent = $obj.percentComplete
                $start   = $obj.startTime
                $end     = $obj.endTime

                Write-Host ("Status: {0}" -f ($status ?? 'Unknown'))
                if ($percent) { Write-Host ("Progress: {0}%" -f $percent) }
                if ($start)   { Write-Host ("Started: {0}" -f $start) }
                if ($end)     { Write-Host ("Ended:   {0}" -f $end) }

                if ($obj.error) {
                    if ($obj.error.code -or $obj.error.message) {
                        Write-Host ("Error Code: {0}" -f $obj.error.code)
                        Write-Host ("Error Message: {0}" -f $obj.error.message)
                    } else {
                        Write-Host ("Error: {0}" -f $obj.error)
                    }
                }

                if ($status -in @('Succeeded','Completed')) {
                    Write-Success "Operation completed successfully!"
                    $finalObject = $obj
                    break
                } elseif ($status -in @('Failed','Canceled','Cancelled')) {
                    Write-ErrorStyled "Async operation failed or was canceled (status: $status)."
                    return $null
                }
            } else {
                Write-Warn "Could not parse async status response."
            }
        }

        if ($attempt -lt $maxAttempts) {
            Write-Host "Waiting 60 seconds before next check... (Press Ctrl+C to stop monitoring)" -ForegroundColor Yellow
            Start-Sleep -Seconds 60
        }
        $attempt++
    }

    if (-not $finalObject) {
        Write-Warn "Monitoring timeout reached (2 hours). Operation may still be running."
        Write-Info ("You can manually check status with: curl -H 'Authorization: Bearer <token>' '{0}'" -f $AsyncUrl)
        return $null
    }

    Write-Host "" 
    Write-Host "Final Async Response Data:" -ForegroundColor Cyan
    $finalObject | ConvertTo-Json -Depth 20 | Out-Host

    Show-AnfPeeringInstructions -ConfigObject $ConfigObject -AsyncProperties $finalObject.properties

    return $finalObject
}

function Invoke-AnfAsyncApi {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [pscustomobject]$ConfigObject,
        [Parameter(Mandatory)] [ValidateSet('GET','POST','PUT','PATCH','DELETE')] [string]$Method,
        [Parameter(Mandatory)] [string]$Endpoint,
        [Parameter()] [object]$Body,
        [Parameter()] [string]$Description = '',
        [Parameter()] [string]$StepName = ''
    )

    $v = $ConfigObject.Variables

    $baseUrl    = $v.azure_api_base_url.TrimEnd('/')
    $apiVersion = $v.azure_api_version

    $endpointExpanded = $Endpoint
    foreach ($prop in $v.PSObject.Properties) {
        $placeholder = '{{' + $prop.Name + '}}'
        if ($endpointExpanded -like "*$placeholder*") {
            $endpointExpanded = $endpointExpanded -replace [regex]::Escape($placeholder), [string]$prop.Value
        }
    }

    # Build a well-formed ARM URI using UriBuilder to avoid malformed host/query strings
    $uriBuilder = [System.UriBuilder]$baseUrl
    if ([string]::IsNullOrWhiteSpace($uriBuilder.Path) -or $uriBuilder.Path -eq '/') {
        $uriBuilder.Path = $endpointExpanded.TrimStart('/')
    } else {
        $uriBuilder.Path = ($uriBuilder.Path.TrimEnd('/') + '/' + $endpointExpanded.TrimStart('/'))
    }
    $uriBuilder.Query = "api-version=$apiVersion"
    $uri    = $uriBuilder.Uri.AbsoluteUri

    $token  = Get-AnfAuthToken -ConfigObject $ConfigObject
    $headers= @{ Authorization = "Bearer $token" }

    Write-Host "" 
    if ($StepName) {
        Write-Host ("=== Step: {0} ===" -f $StepName) -ForegroundColor Magenta
    }
    Write-Host "=== API Call: $Method $uri ===" -ForegroundColor DarkCyan
    if ($Description) {
        Write-Host "Description: $Description" -ForegroundColor Gray
    }

    $bodyJson = $null
    if ($PSBoundParameters.ContainsKey('Body') -and $null -ne $Body) {
        if ($Body -is [string]) {
            $bodyJson = $Body
        } else {
            $bodyJson = $Body | ConvertTo-Json -Depth 10
        }
        Write-Host "Request Body (truncated):" -ForegroundColor Gray
        $preview = ($bodyJson -split "`n" | Select-Object -First 20) -join "`n"
        Write-Host $preview
        if (($bodyJson -split "`n").Count -gt 20) {
            Write-Host "... (truncated)" -ForegroundColor DarkYellow
        }
    }

    Write-Log -Message "API $Method $uri" -Level 'API'

    try {
        if ($bodyJson) {
            $resp = Invoke-WebRequest -Method $Method -Uri $uri -Headers $headers -Body $bodyJson -ContentType 'application/json' -SkipHttpErrorCheck
        } else {
            $resp = Invoke-WebRequest -Method $Method -Uri $uri -Headers $headers -SkipHttpErrorCheck
        }
    }
    catch {
        Write-ErrorStyled "API call failed: $($_.Exception.Message)"
        throw
    }

    $status = [int]$resp.StatusCode
    Write-Host ("Status Code: {0}" -f $status) -ForegroundColor Gray

    if ($status -ge 200 -and $status -lt 300) {
        Write-Success "Request accepted with status $status"
    } else {
        Write-Warn "Unexpected HTTP status code: $status"
    }

    $asyncUrl    = $resp.Headers['Azure-AsyncOperation']
    if (-not $asyncUrl) { $asyncUrl = $resp.Headers['azure-asyncoperation'] }
    $locationUrl = $resp.Headers['Location']

    if ($asyncUrl) {
        # Flatten potential header collection to a single string URL
        if ($asyncUrl -is [System.Collections.IEnumerable] -and -not ($asyncUrl -is [string])) {
            $asyncUrl = ($asyncUrl | Select-Object -First 1)
        }
        $asyncUrl = [string]$asyncUrl

        Write-Host "" 
        Write-Host ("This is an asynchronous operation. Async Status URL: {0}" -f $asyncUrl) -ForegroundColor Yellow
        $final = Monitor-AnfAsyncOperation -ConfigObject $ConfigObject -AsyncUrl $asyncUrl -StepName $StepName
        if (-not $final) {
            Write-ErrorStyled ("Async operation for step '{0}' did not complete successfully." -f $StepName)
        }
        return $final
    } elseif ($locationUrl) {
        Write-Host "" 
        Write-Host ("Location header present: {0}" -f $locationUrl) -ForegroundColor Yellow
    }

    if ($resp.Content) {
        try {
            $parsed = $resp.Content | ConvertFrom-Json
            Write-Host "Response (JSON):" -ForegroundColor Gray
            $parsed | ConvertTo-Json -Depth 10 | Out-Host
            return $parsed
        } catch {
            Write-Host "Response (raw):" -ForegroundColor Gray
            Write-Host $resp.Content
            return $resp.Content
        }
    }

    Write-Host "(Empty response body)" -ForegroundColor DarkYellow
    return $null
}

function Show-MainMenu {
    param([pscustomobject]$ConfigObject)

    while ($true) {
        Write-Host "" 
        Write-Host "==============================================" -ForegroundColor Green
        Write-Host " Azure NetApp Files Migration Assistant" -ForegroundColor Green
        Write-Host " PowerShell Interactive Menu" -ForegroundColor Green
        Write-Host "==============================================" -ForegroundColor Green
        Write-Host "Config file: $($ConfigObject.Path)" -ForegroundColor Gray
        Write-Host "" 
        Write-Host " 1) Show / Edit current configuration"
        Write-Host " 2) Get authentication token"
        Write-Host " 3) Peering workflow (Phase 2)" 
        Write-Host " 4) Break replication & finalize (Phase 3)" 
        Write-Host " 5) Monitor replication status" 
        Write-Host " 6) Diagnose config (basic JSON sanity check)" 
        Write-Host " 7) Help / usage" 
        Write-Host " 0) Exit" 
        Write-Host "" 
        $choice = Read-Host "Select an option"

        switch ($choice) {
            '1' { Invoke-AnfShowEditConfig -ConfigObject $ConfigObject }
            '2' { Invoke-AnfAuthTokenStep -ConfigObject $ConfigObject }
            '3' { Invoke-AnfPeeringWorkflow -ConfigObject $ConfigObject }
            '4' { Invoke-AnfBreakWorkflow  -ConfigObject $ConfigObject }
            '5' { Invoke-AnfMonitorWorkflow -ConfigObject $ConfigObject }
            '6' { Invoke-AnfDiagnoseConfig -ConfigPath $ConfigObject.Path }
            '7' { Show-Help }
            '0' { break }
            default { Write-Warn "Invalid choice. Please select a valid option." }
        }
    }
}

function Invoke-AnfDiagnoseConfig {
    param([string]$ConfigPath)

    Write-Info "Diagnosing JSON config at '$ConfigPath'"
    try {
        $raw = Get-Content -Path $ConfigPath -Raw -ErrorAction Stop
        $null = $raw | ConvertFrom-Json -ErrorAction Stop
        Write-Success "Config JSON parsed successfully."
    }
    catch {
        Write-ErrorStyled "Config JSON is invalid: $($_.Exception.Message)"
    }
}

function Show-Help {
    Write-Host "" 
    Write-Host "Usage: .\anf_interactive.ps1 [command] [configPath]" -ForegroundColor Cyan
    Write-Host "" 
    Write-Host "Commands:" -ForegroundColor White
    Write-Host "  menu     - Show interactive menu (default)"
    Write-Host "  setup    - Run interactive PowerShell setup wizard for config.json"
    Write-Host "  peering  - Run peering workflow (Phase 2)"
    Write-Host "  break    - Run break replication workflow (Phase 3)"
    Write-Host "  monitor  - Monitor replication status for an existing migration volume"
    Write-Host "  config   - Show current configuration"
    Write-Host "  diagnose - Basic JSON syntax validation for config file"
    Write-Host "  token    - Get authentication token only"
    Write-Host "  help     - Show this help message"
    Write-Host "" 
    Write-Host "Examples:" -ForegroundColor White
    Write-Host "  .\anf_interactive.ps1" 
    Write-Host "  .\anf_interactive.ps1 menu" 
    Write-Host "  .\anf_interactive.ps1 peering .\config.json" 
    Write-Host "  .\anf_interactive.ps1 monitor" 
    Write-Host "" 
}

function Get-AnfProtocol {
    param([pscustomobject]$ConfigObject)

    $t = $ConfigObject.Variables.target_protocol_types
    if ($t -and ($t -match 'SMB' -or $t -match 'CIFS')) {
        'SMB'
    } else {
        'NFSv3'
    }
}

function Get-AnfQosMode {
    param([pscustomobject]$ConfigObject)

    $t = $ConfigObject.Variables.target_throughput_mibps
    if ($t -and $t.ToString().Trim()) {
        'Manual'
    } else {
        'Auto'
    }
}

function New-AnfVolumePayload {
    param([pscustomobject]$ConfigObject)

    $v        = $ConfigObject.Variables
    $protocol = Get-AnfProtocol -ConfigObject $ConfigObject
    $qosMode  = Get-AnfQosMode  -ConfigObject $ConfigObject

    # Zones as array (can be empty for regional volumes)
    $zones = @()
    if ($v.target_zones) {
        if ($v.target_zones -is [System.Collections.IEnumerable]) {
            $zones = @($v.target_zones)
        } else {
            $zones = @($v.target_zones)
        }
    }

    $props = @{
        volumeType = 'Migration'
        dataProtection = @{
            replication = @{
                endpointType        = 'Dst'
                replicationSchedule = $v.replication_schedule
                remotePath          = @{
                    externalHostName = $v.source_cluster_name
                    serverName       = $v.source_svm_name
                    volumeName       = $v.source_volume_name
                }
            }
        }
        serviceLevel   = $v.target_service_level
        creationToken  = $v.target_volume_name
        usageThreshold = [int64]$v.target_usage_threshold
        subnetId       = $v.target_subnet_id
        networkFeatures= $v.target_network_features
        isLargeVolume  = [bool]$v.target_is_large_volume
    }

    if ($protocol -eq 'SMB') {
        $props.protocolTypes = @('CIFS')
        $props.exportPolicy  = @{ rules = @() }
    } else {
        $props.protocolTypes = @('NFSv3')
        $props.exportPolicy  = @{
            rules = @(
                @{
                    ruleIndex          = 1
                    unixReadOnly       = $false
                    unixReadWrite      = $true
                    cifs               = $false
                    nfsv3              = $true
                    nfsv41             = $false
                    allowedClients     = '0.0.0.0/0'
                    kerberos5ReadOnly  = $false
                    kerberos5ReadWrite = $false
                    kerberos5iReadOnly = $false
                    kerberos5iReadWrite= $false
                    kerberos5pReadOnly = $false
                    kerberos5pReadWrite= $false
                    hasRootAccess      = $true
                }
            )
        }
    }

    if ($qosMode -eq 'Manual' -and $v.target_throughput_mibps -and $v.target_throughput_mibps.ToString().Trim()) {
        $props.throughputMibps = [double]$v.target_throughput_mibps
    }

    $payload = @{
        type       = 'Microsoft.NetApp/netAppAccounts/capacityPools/volumes'
        location   = $v.target_location
        zones      = $zones
        properties = $props
    }

    return $payload
}

function Wait-AnfVolumeReady {
    param(
        [pscustomobject]$ConfigObject,
        [int]$MaxAttempts = 40,
        [int]$DelaySeconds = 30
    )

    $v = $ConfigObject.Variables

    Write-Info "Checking volume status..."
    Write-Info "Volume creation can take up to 10 minutes. Will check every $DelaySeconds seconds for up to 20 minutes."

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        Write-Host "" 
        Write-Host ("Status Check {0}/{1} - {2}" -f $attempt, $MaxAttempts, (Get-Date -Format 'HH:mm:ss')) -ForegroundColor Cyan

        $token = Get-AnfAuthToken -ConfigObject $ConfigObject

        $baseUrl    = $v.azure_api_base_url.TrimEnd('/')
        $apiVersion = $v.azure_api_version

        $volPath = "/subscriptions/$($v.azure_subscription_id)/resourceGroups/$($v.target_resource_group)/providers/Microsoft.NetApp/netAppAccounts/$($v.target_netapp_account)/capacityPools/$($v.target_capacity_pool)/volumes/$($v.target_volume_name)"
        $uriBuilder = [System.UriBuilder]$baseUrl
        if ([string]::IsNullOrWhiteSpace($uriBuilder.Path) -or $uriBuilder.Path -eq '/') {
            $uriBuilder.Path = $volPath.TrimStart('/')
        } else {
            $uriBuilder.Path = ($uriBuilder.Path.TrimEnd('/') + '/' + $volPath.TrimStart('/'))
        }
        $uriBuilder.Query = "api-version=$apiVersion"
        $uri = $uriBuilder.Uri.AbsoluteUri

        $headers = @{ Authorization = "Bearer $token" }

        $resp = $null
        try {
            $resp = Invoke-WebRequest -Method 'GET' -Uri $uri -Headers $headers -SkipHttpErrorCheck
        }
        catch {
            Write-Warn "Failed to check volume status (attempt $attempt): $($_.Exception.Message)"
        }

        if ($resp -and $resp.Content) {
            $obj = $null
            try { $obj = $resp.Content | ConvertFrom-Json } catch { $obj = $null }

            if ($obj) {
                # provisioningState may be under properties, but be defensive
                $stateRaw = $null
                if ($obj.properties -and $obj.properties.provisioningState) {
                    $stateRaw = $obj.properties.provisioningState
                } elseif ($obj.provisioningState) {
                    $stateRaw = $obj.provisioningState
                }

                $state = if ($stateRaw) { $stateRaw.ToString().Trim() } else { '' }
                $stateLower = $state.ToLowerInvariant()

                $fileSystemId = $null
                $mountTargets = $null
                if ($obj.properties) {
                    $fileSystemId = $obj.properties.fileSystemId
                    $mountTargets = $obj.properties.mountTargets
                }

                Write-Host ("Provisioning State: {0}" -f ($(if ($state) { $state } else { 'Unknown' })))
                if ($fileSystemId) {
                    Write-Host ("File System ID: {0}" -f $fileSystemId)
                }
                if ($mountTargets) {
                    $i = 1
                    foreach ($mt in $mountTargets) {
                        $ip   = $mt.ipAddress
                        $fqdn = $mt.smbServerFqdn
                        if (-not $fqdn) { $fqdn = $mt.serverFqdn }
                        Write-Host ("Mount Target {0}: {1} ({2})" -f $i, $ip, $fqdn)
                        $i++
                    }
                }

                # Treat "Succeeded", "Available", and variants like "SucceededWithWarning" as ready
                if ($stateLower -eq 'succeeded' -or $stateLower -eq 'available' -or $stateLower.StartsWith('succeeded')) {
                    Write-Success "Volume is ready and available!"
                    return $true
                }

                # Treat any state containing "failed" or "error" as failure
                if ($stateLower -like '*failed*' -or $stateLower -like '*error*') {
                    Write-ErrorStyled "Volume creation failed or in error state: $state"
                    return $false
                }

                Write-Info ("Volume is still being created... ({0})" -f ($(if ($state) { $state } else { 'Unknown' })))
            } else {
                Write-Warn "Could not parse volume status response JSON."
                Write-Host ($resp.Content.Substring(0, [Math]::Min(200, $resp.Content.Length)))
            }
        }

        if ($attempt -lt $MaxAttempts) {
            Write-Host ("Waiting {0} seconds before next check..." -f $DelaySeconds) -ForegroundColor Yellow
            Start-Sleep -Seconds $DelaySeconds
        }
    }

    Write-Warn "Volume status check timeout after 20 minutes. Volume may still be provisioning."
    Write-Info "You can manually check volume status in the Azure portal or wait longer if needed."
    return $true
}

function Invoke-AnfPeeringWorkflow {
    param([pscustomobject]$ConfigObject)

    # Refresh config from disk at the start of the workflow so edits are honored
    try {
        $ConfigObject = Get-AnfConfig -Path $Script:ConfigPath
    } catch {
        Write-ErrorStyled $_.Exception.Message
        return
    }

    $protocol = Get-AnfProtocol -ConfigObject $ConfigObject
    $qosMode  = Get-AnfQosMode  -ConfigObject $ConfigObject

    Write-Host "" 
    Write-Host "============================================" -ForegroundColor Magenta
    Write-Host " Peering Setup Workflow" -ForegroundColor Magenta
    Write-Host "============================================" -ForegroundColor Magenta
    Write-Host "" 

    Write-Info  ("Starting peering setup workflow for {0} with {1} QoS" -f $protocol, $qosMode)
    Write-Host  "" 
    Write-Host  "This workflow will:" -ForegroundColor Blue
    Write-Host  "  1. Authenticate with Azure"
    Write-Host  "  2. Create the target volume"
    Write-Host  "  3. Set up cluster peering (with ONTAP command execution)"
    Write-Host  "  4. Set up SVM peering (with ONTAP command execution)"
    Write-Host  "  5. Begin data synchronization"
    Write-Host  "" 
    Write-Host  "After completion, you'll need to:" -ForegroundColor Yellow
    Write-Host  "  • Monitor sync progress in Azure Portal"
    Write-Host  "  • Wait for data synchronization to complete"
    Write-Host  "  • Run workflow #3 when ready to finalize migration"
    Write-Host  "" 

    $proceed = Read-Host "Do you want to proceed with the peering setup workflow? (Y/n)"
    if (-not [string]::IsNullOrWhiteSpace($proceed) -and $proceed -notmatch '^[Yy]') {
        Write-Info "Workflow cancelled by user."
        return
    }

    # Set interaction mode defaults without prompting
    $Script:InteractionMode      = 'full'
    $Script:MonitoringMode       = 'full'
    $Script:MigrationSyncStarted = $false

    # Step 1: Authentication (interactive for parity with Bash)
    Invoke-AnfAuthTokenStep -ConfigObject $ConfigObject

    # Step 2: Create target volume (mirrors example script: PUT + Azure-AsyncOperation polling)
    Write-Host "" 
    Write-Host "Step 2: Create target volume" -ForegroundColor Magenta
    $payload  = New-AnfVolumePayload -ConfigObject $ConfigObject
    $v        = $ConfigObject.Variables

    # Build full volume ID like the example
    $subscriptionId = $v.azure_subscription_id
    $resourceGroup  = $v.target_resource_group
    $accountName    = $v.target_netapp_account
    $poolName       = $v.target_capacity_pool
    $volumeName     = $v.target_volume_name
    $apiVersion     = $v.azure_api_version
    $baseUrl        = $v.azure_api_base_url.TrimEnd('/')

    $volumeId = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.NetApp/netAppAccounts/$accountName/capacityPools/$poolName/volumes/$volumeName"

    $uriBuilder = [System.UriBuilder]$baseUrl
    if ([string]::IsNullOrWhiteSpace($uriBuilder.Path) -or $uriBuilder.Path -eq '/') {
        $uriBuilder.Path = $volumeId.TrimStart('/')
    } else {
        $uriBuilder.Path = ($uriBuilder.Path.TrimEnd('/') + '/' + $volumeId.TrimStart('/'))
    }
    $uriBuilder.Query = "api-version=$apiVersion"
    $volumeUri = $uriBuilder.Uri.AbsoluteUri

    Write-Host "Volume create URI: $volumeUri" -ForegroundColor DarkGray

    $token   = Get-AnfAuthToken -ConfigObject $ConfigObject
    $headers = @{ Authorization = "Bearer $token" }

    # Convert payload to JSON explicitly for this low-level call
    $payloadJson = $payload | ConvertTo-Json -Depth 20

    Write-Host "Sending new ANF migration volume creation request" -ForegroundColor Cyan
    Write-Log -Message "PUT $volumeUri (migration volume create)" -Level 'API'

    try {
        $resp = Invoke-WebRequest -Method 'PUT' -Uri $volumeUri -Headers $headers -Body $payloadJson -ContentType 'application/json' -SkipHttpErrorCheck
    }
    catch {
        Write-ErrorStyled "Volume create PUT failed: $($_.Exception.Message)"
        return
    }

    $statusCode = [int]$resp.StatusCode
    Write-Host ("Volume create HTTP status: {0}" -f $statusCode) -ForegroundColor Gray

    if ($statusCode -lt 200 -or $statusCode -ge 300) {
        Write-ErrorStyled ("Volume create request returned unexpected status code: {0}" -f $statusCode)
        if ($resp.Content) {
            Write-Host "Response body:" -ForegroundColor Gray
            Write-Host $resp.Content
        }
        return
    }

    $asyncUrl = $resp.Headers['Azure-AsyncOperation']
    if (-not $asyncUrl) { $asyncUrl = $resp.Headers['azure-asyncoperation'] }

    if (-not $asyncUrl) {
        Write-Warn "No Azure-AsyncOperation header returned for volume create; falling back to status polling on the volume resource."
        Wait-AnfVolumeReady -ConfigObject $ConfigObject | Out-Null
    } else {
        # Flatten potential header collection to a single URL string
        if ($asyncUrl -is [System.Collections.IEnumerable] -and -not ($asyncUrl -is [string])) {
            $asyncUrl = ($asyncUrl | Select-Object -First 1)
        }
        $asyncUrl = [string]$asyncUrl

        Write-Host "Async URL for volume create: $asyncUrl" -ForegroundColor DarkGray

        # Poll async status until Succeeded/Failed, like the reference script
        $volumeStatus = $null
        do {
            try {
                $asyncResp = Invoke-WebRequest -Uri $asyncUrl -Headers $headers -Method 'GET' -SkipHttpErrorCheck
            }
            catch {
                Write-Warn "Failed to check volume async status: $($_.Exception.Message)"
                break
            }

            $asyncObj = $null
            if ($asyncResp.Content) {
                try { $asyncObj = $asyncResp.Content | ConvertFrom-Json } catch { $asyncObj = $null }
            }

            if ($asyncObj) {
                $volumeStatus = $asyncObj.status
                Write-Host ("Volume async status: {0}" -f $volumeStatus) -ForegroundColor Gray

                if ($volumeStatus -eq 'Failed') {
                    Write-ErrorStyled "Error creating volume (async status = Failed)."
                    $asyncObj | ConvertTo-Json -Depth 10 | Out-Host
                    return
                }
            } else {
                Write-Warn "Could not parse volume async status response JSON."
                if ($asyncResp.Content) {
                    Write-Host ($asyncResp.Content.Substring(0, [Math]::Min(200, $asyncResp.Content.Length)))
                }
            }

            if ($volumeStatus -ne 'Succeeded') {
                Write-Host "Waiting 30 seconds for ANF migration volume creation to complete..." -ForegroundColor Yellow
                Start-Sleep -Seconds 30
            }
        } while ($volumeStatus -ne 'Succeeded')

        Write-Host "ANF volume creation succeeded. Continuing with cluster peering." -ForegroundColor Green
    }

    # Step 3: Check for existing cluster peering before creating new one
    $skipClusterPeering = $false
    if (Test-AnfExistingClusterPeering -ConfigObject $ConfigObject) {
        $skipClusterPeering = $true
        Write-Info "Skipping cluster peering setup - using existing relationship."
    }

    # Step 3a: Issue cluster peer request (only if no existing peering found)
    if (-not $skipClusterPeering) {
        if ($Script:InteractionMode -eq 'minimal') {
            Write-Host "" 
            Write-Host "Critical Step: Cluster Peering Setup" -ForegroundColor Magenta
            Write-Info "This step requires ONTAP command execution - prompting regardless of interaction mode."
            Write-Host "" 
        }

        $v = $ConfigObject.Variables
        $clusterBody = @{
            PeerClusterName = $v.source_cluster_name
            PeerAddresses   = @($v.source_peer_addresses)
        }

        $peerResult = Invoke-AnfAsyncApi -ConfigObject $ConfigObject -Method 'POST' `
            -Endpoint "/subscriptions/{{azure_subscription_id}}/resourceGroups/{{target_resource_group}}/providers/Microsoft.NetApp/netAppAccounts/{{target_netapp_account}}/capacityPools/{{target_capacity_pool}}/volumes/{{target_volume_name}}/peerExternalCluster" `
            -Body $clusterBody `
            -Description "Initiate cluster peering with source ONTAP system (ONTAP commands required)" `
            -StepName "peer_request"

        if (-not $peerResult) {
            Write-ErrorStyled "Cluster peering async operation did not complete successfully. Aborting peering workflow."
            return
        }
    }

    # Step 4: Authorize external replication (always prompt - SVM peering commands required)
    if ($Script:InteractionMode -eq 'minimal') {
        Write-Host "" 
        Write-Host "Critical Step: SVM Peering Authorization" -ForegroundColor Magenta
        Write-Info "This step requires SVM peering command execution - prompting regardless of interaction mode."
        Write-Host "" 
    }

    $authResult = Invoke-AnfAsyncApi -ConfigObject $ConfigObject -Method 'POST' `
        -Endpoint "/subscriptions/{{azure_subscription_id}}/resourceGroups/{{target_resource_group}}/providers/Microsoft.NetApp/netAppAccounts/{{target_netapp_account}}/capacityPools/{{target_capacity_pool}}/volumes/{{target_volume_name}}/authorizeExternalReplication" `
        -Description "Authorize the external replication relationship (SVM peering commands required)" `
        -StepName "authorize_replication"

    if (-not $authResult) {
        Write-ErrorStyled "SVM peering / authorization async operation did not complete successfully."
    }

    if ($Script:MigrationSyncStarted) {
        Write-Host "" 
        Write-Host "Peering setup completed - data synchronization in progress" -ForegroundColor Green
        Write-Host "" 
        Write-Host "Next Steps:" -ForegroundColor Blue
        Write-Host "  1. Monitor sync progress in Azure Portal" 
        Write-Host "  2. Wait for data synchronization to complete" 
        Write-Host "  3. When ready to cut over, run this script again and select the 'break' workflow (Phase 3)" 
    } else {
        Write-Warn "Peering setup completed but sync flag not set - this may indicate an issue."
        Write-Info "Please check the Azure Portal for volume status and replication progress."
    }
}

# Helper function to check replication status and wait for transfers to complete
function Wait-AnfReplicationIdle {
    param(
        [pscustomobject]$ConfigObject,
        [int]$MaxWaitMinutes = 30
    )

    $v = $ConfigObject.Variables
    $subscriptionId = $v.azure_subscription_id
    $resourceGroup  = $v.target_resource_group
    $accountName    = $v.target_netapp_account
    $poolName       = $v.target_capacity_pool
    $volumeName     = $v.target_volume_name
    $apiVersion     = $v.azure_api_version
    $baseUrl        = $v.azure_api_base_url.TrimEnd('/')

    $volumeId = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.NetApp/netAppAccounts/$accountName/capacityPools/$poolName/volumes/$volumeName"
    
    $uriBuilder = [System.UriBuilder]$baseUrl
    if ([string]::IsNullOrWhiteSpace($uriBuilder.Path) -or $uriBuilder.Path -eq '/') {
        $uriBuilder.Path = $volumeId.TrimStart('/')
    } else {
        $uriBuilder.Path = ($uriBuilder.Path.TrimEnd('/') + '/' + $volumeId.TrimStart('/'))
    }
    $uriBuilder.Query = "api-version=$apiVersion"
    $volumeUri = $uriBuilder.Uri.AbsoluteUri

    $maxAttempts = $MaxWaitMinutes * 2  # Check every 30 seconds
    $attempt = 1

    Write-Info "Checking replication status before proceeding..."

    while ($attempt -le $maxAttempts) {
        $token   = Get-AnfAuthToken -ConfigObject $ConfigObject
        $headers = @{ Authorization = "Bearer $token" }

        try {
            $resp = Invoke-WebRequest -Method 'GET' -Uri $volumeUri -Headers $headers -SkipHttpErrorCheck
        }
        catch {
            Write-Warn "Failed to check volume status: $($_.Exception.Message)"
            Start-Sleep -Seconds 30
            $attempt++
            continue
        }

        if ($resp.StatusCode -eq 200 -and $resp.Content) {
            try {
                $vol = $resp.Content | ConvertFrom-Json
                $replProps = $vol.properties.dataProtection.replication
                
                if ($replProps) {
                    $mirrorState = $replProps.mirrorState
                    $transferring = $vol.properties.isRestoring
                    
                    Write-Host "  Mirror State: $mirrorState" -ForegroundColor Gray
                    
                    # Check if a transfer is in progress
                    if ($transferring -or $mirrorState -eq 'Transferring') {
                        Write-Host "  Transfer in progress - waiting... (attempt $attempt/$maxAttempts)" -ForegroundColor Yellow
                        Start-Sleep -Seconds 30
                        $attempt++
                        continue
                    } else {
                        Write-Success "Replication is idle and ready for final transfer."
                        return $true
                    }
                } else {
                    Write-Warn "No replication properties found on volume."
                    return $true
                }
            }
            catch {
                Write-Warn "Failed to parse volume response: $($_.Exception.Message)"
                return $true
            }
        } else {
            Write-Warn "Failed to get volume status (HTTP $($resp.StatusCode))"
            return $true
        }
    }

    Write-Warn "Timeout waiting for ongoing transfer to complete after $MaxWaitMinutes minutes."
    $continueAnyway = Read-Host "Do you want to proceed anyway? (y/N)"
    return ($continueAnyway -match '^[Yy]')
}

# Phase 3: Break replication and finalize migration
function Invoke-AnfBreakWorkflow {
    param([pscustomobject]$ConfigObject)

    # Refresh config from disk at the start of the workflow
    try {
        $ConfigObject = Get-AnfConfig -Path $Script:ConfigPath
    } catch {
        Write-ErrorStyled $_.Exception.Message
        return
    }

    Write-Host "" 
    Write-Host "============================================" -ForegroundColor Magenta
    Write-Host " Break Replication & Finalize Migration" -ForegroundColor Magenta
    Write-Host "============================================" -ForegroundColor Magenta
    Write-Host "" 

    Write-Info "This workflow will complete your migration by:"
    Write-Host "  1. Performing final replication transfer"
    Write-Host "  2. Breaking the replication relationship"
    Write-Host "  3. Finalizing the migration (cleanup)"
    Write-Host "" 
    Write-Host "⚠️  IMPORTANT WARNING:" -ForegroundColor Red
    Write-Host "Breaking replication will:" -ForegroundColor Yellow
    Write-Host "  • Stop data synchronization from on-premises"
    Write-Host "  • Make the Azure volume writable"
    Write-Host "  • This action cannot be easily undone"
    Write-Host "" 
    Write-Host "Before proceeding, ensure:" -ForegroundColor Cyan
    Write-Host "  • Data synchronization is complete (check Azure Portal metrics)"
    Write-Host "  • You're ready to switch users to the Azure volume"
    Write-Host "  • You have a rollback plan if needed"
    Write-Host "" 

    $proceed = Read-Host "Are you sure you want to break replication and finalize the migration? (y/N)"
    if ([string]::IsNullOrWhiteSpace($proceed) -or $proceed -notmatch '^[Yy]') {
        Write-Info "Break replication workflow cancelled by user"
        return
    }

    # Set interaction mode defaults without prompting
    $Script:InteractionMode      = 'full'
    $Script:MonitoringMode       = 'full'

    # Always refresh authentication token for break replication
    # (tokens likely expired since initial setup)
    Write-Info "Refreshing authentication token for break replication workflow..."
    Invoke-AnfAuthTokenStep -ConfigObject $ConfigObject

    # Check if any transfer is currently in progress and wait for it to complete
    Write-Host "" 
    Write-Host "Pre-flight Check: Replication Status" -ForegroundColor Magenta
    if (-not (Wait-AnfReplicationIdle -ConfigObject $ConfigObject -MaxWaitMinutes 30)) {
        Write-ErrorStyled "Cannot proceed - replication is not ready or user cancelled."
        return
    }

    # Step 1: Perform replication transfer (final data sync)
    Write-Host "" 
    Write-Host "Step 1: Performing final replication transfer" -ForegroundColor Magenta
    Write-Info "This will synchronize any remaining data from on-premises to Azure."
    Write-Info "This operation can take a long time depending on data size."
    Write-Host "" 

    $transferResult = Invoke-AnfAsyncApi -ConfigObject $ConfigObject -Method 'POST' `
        -Endpoint "/subscriptions/{{azure_subscription_id}}/resourceGroups/{{target_resource_group}}/providers/Microsoft.NetApp/netAppAccounts/{{target_netapp_account}}/capacityPools/{{target_capacity_pool}}/volumes/{{target_volume_name}}/performReplicationTransfer" `
        -Description "Start the final data replication transfer" `
        -StepName "replication_transfer"

    if (-not $transferResult) {
        Write-ErrorStyled "Replication transfer did not complete successfully."
        Write-Warn "You may need to retry this operation or check the Azure Portal for details."
        return
    }

    Write-Success "Final replication transfer completed successfully!"

    # Step 2: Break replication relationship
    Write-Host "" 
    Write-Host "Step 2: Breaking replication relationship" -ForegroundColor Magenta
    Write-Info "This will stop synchronization and make the Azure volume writable."
    Write-Host "" 

    $breakResult = Invoke-AnfAsyncApi -ConfigObject $ConfigObject -Method 'POST' `
        -Endpoint "/subscriptions/{{azure_subscription_id}}/resourceGroups/{{target_resource_group}}/providers/Microsoft.NetApp/netAppAccounts/{{target_netapp_account}}/capacityPools/{{target_capacity_pool}}/volumes/{{target_volume_name}}/breakReplication" `
        -Description "Break the replication relationship (makes target writable)" `
        -StepName "break_replication"

    if (-not $breakResult) {
        Write-ErrorStyled "Break replication did not complete successfully."
        Write-Warn "You may need to retry this operation or check the Azure Portal for details."
        return
    }

    Write-Success "Replication relationship broken successfully!"

    # Step 3: Finalize external replication
    Write-Host "" 
    Write-Host "Step 3: Finalizing migration" -ForegroundColor Magenta
    Write-Info "Cleaning up the external replication configuration."
    Write-Host "" 

    $finalizeResult = Invoke-AnfAsyncApi -ConfigObject $ConfigObject -Method 'POST' `
        -Endpoint "/subscriptions/{{azure_subscription_id}}/resourceGroups/{{target_resource_group}}/providers/Microsoft.NetApp/netAppAccounts/{{target_netapp_account}}/capacityPools/{{target_capacity_pool}}/volumes/{{target_volume_name}}/finalizeExternalReplication" `
        -Description "Finalize and clean up the external replication configuration" `
        -StepName "finalize_replication"

    if (-not $finalizeResult) {
        Write-ErrorStyled "Finalize replication did not complete successfully."
        Write-Warn "You may need to retry this operation or check the Azure Portal for details."
        return
    }

    Write-Success "Migration finalization completed successfully!"

    # Success message
    Write-Host "" 
    Write-Host "============================================" -ForegroundColor Green
    Write-Host "🎉 Migration Completed Successfully!" -ForegroundColor Green
    Write-Host "============================================" -ForegroundColor Green
    Write-Host "" 
    Write-Host "✅ Your Azure NetApp Files volume is now ready for production use!" -ForegroundColor Green
    Write-Host "" 
    Write-Host "Post-Migration Steps:" -ForegroundColor Blue
    Write-Host "  1. Update DNS records to point to the new Azure volume"
    Write-Host "  2. Update client mount configurations if needed"
    Write-Host "  3. Test application connectivity and functionality"
    Write-Host "  4. Monitor performance and adjust as needed"
    Write-Host "" 
    Write-Host "Volume Information:" -ForegroundColor Cyan
    $v = $ConfigObject.Variables
    Write-Host "  • Volume Name: $($v.target_volume_name)"
    Write-Host "  • Resource Group: $($v.target_resource_group)"
    Write-Host "  • Check Azure Portal for mount targets and connection details"
    Write-Host "" 
    Write-Info "Detailed logs are available in: $Script:LogFile"
}

# Placeholder: monitoring workflow
function Invoke-AnfMonitorWorkflow {
    param([pscustomobject]$ConfigObject)

    # Refresh config from disk at the start of the workflow
    try {
        $ConfigObject = Get-AnfConfig -Path $Script:ConfigPath
    } catch {
        Write-ErrorStyled $_.Exception.Message
        return
    }

    Write-Host "" 
    Write-Host "=== Replication Monitoring ===" -ForegroundColor Magenta
    Write-Info "This is a placeholder for a PowerShell implementation of Azure Monitor polling."
}

# --- Script entry point ---

try {
    $configObject = Get-AnfConfig -Path $Script:ConfigPath
}
catch {
    Write-ErrorStyled $_.Exception.Message
    exit 1
}

switch ($Command) {
    'menu'    { Show-MainMenu -ConfigObject $configObject }
    'setup'   { Invoke-AnfSetupWizard -ConfigPath $Script:ConfigPath }
    'peering' { Invoke-AnfPeeringWorkflow  -ConfigObject $configObject }
    'break'   { Invoke-AnfBreakWorkflow   -ConfigObject $configObject }
'monitor' { Invoke-AnfMonitorWorkflow -ConfigObject $configObject }
    'config'  { Invoke-AnfShowEditConfig -ConfigObject $configObject }
    'diagnose'{ Invoke-AnfDiagnoseConfig -ConfigPath $configObject.Path }
    'token'   { Invoke-AnfAuthTokenStep -ConfigObject $configObject }
    'help'    { Show-Help }
}
