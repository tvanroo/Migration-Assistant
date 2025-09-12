#!/bin/bash
# Azure NetApp Files Migration Assistant - Dynamic Workflow
# Reads configuration from config.yaml at runtime

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.yaml"
TOKEN_FILE="${SCRIPT_DIR}/.token"
LOG_FILE="${SCRIPT_DIR}/anf_migration.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Error handling
error_exit() {
    echo -e "${RED}❌ Error: $1${NC}" >&2
    log "ERROR: $1"
    exit 1
}

# Success message
success() {
    echo -e "${GREEN}✅ $1${NC}"
    log "SUCCESS: $1"
}

# Info message
info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
    log "INFO: $1"
}

# Read config value using Python
get_config_value() {
    local key="$1"
    python3 -c "
import yaml
with open('$CONFIG_FILE') as f:
    config = yaml.safe_load(f)
    all_vars = {**config.get('variables', {}), **config.get('secrets', {})}
    print(all_vars.get('$key', ''))
"
}

# Get protocol and QoS from config
get_protocol() {
    local protocol_types=$(get_config_value 'target_protocol_types')
    if [[ "$protocol_types" == *"SMB"* || "$protocol_types" == *"CIFS"* ]]; then
        echo "SMB"
    else
        echo "NFSv3"
    fi
}

get_qos() {
    local throughput=$(get_config_value 'target_throughput_mibps')
    if [[ -n "$throughput" && "$throughput" != "" ]]; then
        echo "Manual"
    else
        echo "Auto"
    fi
}

# Get Azure AD token
get_token() {
    info "Requesting Azure AD token..."
    
    local tenant=$(get_config_value 'azure_tenant_id')
    local app_id=$(get_config_value 'azure_app_id')
    local app_secret=$(get_config_value 'azure_app_secret')
    local auth_url=$(get_config_value 'azure_auth_base_url')
    local api_url=$(get_config_value 'azure_api_base_url')
    local api_version=$(get_config_value 'azure_api_version')
    
    if [[ -z "$tenant" || -z "$app_id" || -z "$app_secret" ]]; then
        error_exit "Missing required authentication parameters in config"
    fi
    
    local response
    response=$(curl -s -X POST \
        --data "grant_type=client_credentials&client_id=${app_id}&client_secret=${app_secret}&resource=${api_url}" \
        "${auth_url}/${tenant}/oauth2/token?api-version=${api_version}")
    
    if [[ $? -ne 0 ]]; then
        error_exit "Failed to make token request"
    fi
    
    # Extract token using Python
    local token
    token=$(python3 -c "
import json
try:
    data = json.loads('$response')
    print(data.get('access_token', ''))
except:
    pass
")
    
    if [[ -z "$token" ]]; then
        error_exit "Failed to extract access token from response"
    fi
    
    # Store token securely
    echo "$token" > "$TOKEN_FILE"
    chmod 600 "$TOKEN_FILE"
    
    success "Token obtained and stored"
}

# Execute a CURL command with current config values
run_api_call() {
    local step_name="$1"
    local method="$2" 
    local endpoint="$3"
    local data="$4"
    local description="$5"
    
    info "Step: $step_name - $description"
    
    # Ensure we have a valid token
    if [[ ! -f "$TOKEN_FILE" ]]; then
        get_token
    fi
    
    local token=$(cat "$TOKEN_FILE")
    local api_url=$(get_config_value 'azure_api_base_url')
    local api_version=$(get_config_value 'azure_api_version')
    
    # Build the full URL
    local full_url="${api_url}${endpoint}?api-version=${api_version}"
    
    # Replace variables in URL and data
    full_url=$(echo "$full_url" | python3 -c "
import sys, yaml
with open('$CONFIG_FILE') as f:
    config = yaml.safe_load(f)
    all_vars = {**config.get('variables', {}), **config.get('secrets', {})}
    
url = sys.stdin.read().strip()
for key, value in all_vars.items():
    url = url.replace('{{' + key + '}}', str(value))
print(url)
")
    
    # Replace variables in data if provided
    if [[ -n "$data" ]]; then
        data=$(echo "$data" | python3 -c "
import sys, yaml
with open('$CONFIG_FILE') as f:
    config = yaml.safe_load(f)
    all_vars = {**config.get('variables', {}), **config.get('secrets', {})}
    
data = sys.stdin.read()
for key, value in all_vars.items():
    data = data.replace('{{' + key + '}}', str(value))
print(data, end='')
")
        
        curl -s -X "$method" \
            -H "Authorization: Bearer $token" \
            -H "Content-Type: application/json" \
            --data "$data" \
            "$full_url" || error_exit "API call failed: $step_name"
    else
        curl -s -X "$method" \
            -H "Authorization: Bearer $token" \
            "$full_url" || error_exit "API call failed: $step_name"
    fi
    
    success "Completed: $step_name"
}

# Generate volume creation payload based on protocol/QoS
get_volume_payload() {
    local protocol=$(get_protocol)
    local qos=$(get_qos)
    
    if [[ "$protocol" == "SMB" ]]; then
        if [[ "$qos" == "Manual" ]]; then
            echo '{
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
                }
            }
        },
        "serviceLevel": "{{target_service_level}}",
        "throughputMibps": "{{target_throughput_mibps}}",
        "creationToken": "{{target_volume_name}}",
        "usageThreshold": "{{target_usage_threshold}}",
        "exportPolicy": {
            "rules": []
        },
        "protocolTypes": [
            "CIFS"
        ],
        "subnetId": "{{target_subnet_id}}",
        "networkFeatures": "Standard",
        "isLargeVolume": "{{target_is_large_volume}}"
    }
}'
        else
            echo '{
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
                }
            }
        },
        "serviceLevel": "{{target_service_level}}",
        "creationToken": "{{target_volume_name}}",
        "usageThreshold": "{{target_usage_threshold}}",
        "exportPolicy": {
            "rules": []
        },
        "protocolTypes": [
            "CIFS"
        ],
        "subnetId": "{{target_subnet_id}}",
        "networkFeatures": "Standard",
        "isLargeVolume": "{{target_is_large_volume}}"
    }
}'
        fi
    else
        # NFSv3
        if [[ "$qos" == "Manual" ]]; then
            echo '{
   "type":"Microsoft.NetApp/netAppAccounts/capacityPools/volumes",
   "location":"{{target_location}}",
   "properties":{
      "volumeType":"Migration",
      "dataProtection":{
         "replication":{
            "endpointType":"Dst",
            "replicationSchedule":"{{replication_schedule}}",
            "remotePath":{
               "externalHostName":"{{source_hostname}}",
               "serverName":"{{source_server_name}}",
               "volumeName":"{{source_volume_name}}"
            }
         }
      },
      "serviceLevel":"{{target_service_level}}",
      "throughputMibps": "{{target_throughput_mibps}}",
      "creationToken":"{{target_volume_name}}",
      "usageThreshold":{{target_usage_threshold}},
      "exportPolicy":{
         "rules":[
            {
               "ruleIndex":1,
               "unixReadOnly":false,
               "unixReadWrite":true,
               "cifs":false,
               "nfsv3":true,
               "nfsv41":false,
               "allowedClients":"0.0.0.0/0",
               "kerberos5ReadOnly":false,
               "kerberos5ReadWrite":false,
               "kerberos5iReadOnly":false,
               "kerberos5iReadWrite":false,
               "kerberos5pReadOnly":false,
               "kerberos5pReadWrite":false,
               "hasRootAccess":true
            }
         ]
      },
      "protocolTypes":[
         "NFSv3"
      ],
      "subnetId":"{{target_subnet_id}}",
      "networkFeatures":"Standard",
      "isLargeVolume":"{{target_is_large_volume}}"
   }
}'
        else
            echo '{
   "type":"Microsoft.NetApp/netAppAccounts/capacityPools/volumes",
   "location":"{{target_location}}",
   "properties":{
      "volumeType":"Migration",
      "dataProtection":{
         "replication":{
            "endpointType":"Dst",
            "replicationSchedule":"{{replication_schedule}}",
            "remotePath":{
               "externalHostName":"{{source_hostname}}",
               "serverName":"{{source_server_name}}",
               "volumeName":"{{source_volume_name}}"
            }
         }
      },
      "serviceLevel":"{{target_service_level}}",
      "creationToken":"{{target_volume_name}}",
      "usageThreshold":{{target_usage_threshold}},
      "exportPolicy":{
         "rules":[
            {
               "ruleIndex":1,
               "unixReadOnly":false,
               "unixReadWrite":true,
               "cifs":false,
               "nfsv3":true,
               "nfsv41":false,
               "allowedClients":"0.0.0.0/0",
               "kerberos5ReadOnly":false,
               "kerberos5ReadWrite":false,
               "kerberos5iReadOnly":false,
               "kerberos5iReadWrite":false,
               "kerberos5pReadOnly":false,
               "kerberos5pReadWrite":false,
               "hasRootAccess":true
            }
         ]
      },
      "protocolTypes":[
         "NFSv3"
      ],
      "subnetId":"{{target_subnet_id}}",
      "networkFeatures":"Standard",
      "isLargeVolume":"{{target_is_large_volume}}"
   }
}'
        fi
    fi
}

# Main workflow execution
run_workflow() {
    local protocol=$(get_protocol)
    local qos=$(get_qos)
    
    info "Starting ANF Migration Assistant workflow for $protocol with $qos QoS..."
    
    # Step 1: Get authentication token
    get_token
    
    # Step 2: Create target volume
    local volume_payload=$(get_volume_payload)
    run_api_call "create_volume" "PUT" \
        "/subscriptions/{{azure_subscription_id}}/resourceGroups/{{target_resource_group}}/providers/Microsoft.NetApp/netAppAccounts/{{target_netapp_account}}/capacityPools/{{target_capacity_pool}}/volumes/{{target_volume_name}}" \
        "$volume_payload" \
        "Create Target Volume ($protocol with $qos QoS)"
    
    # Step 3: Issue cluster peer request
    run_api_call "peer_request" "POST" \
        "/subscriptions/{{azure_subscription_id}}/resourceGroups/{{target_resource_group}}/providers/Microsoft.NetApp/netAppAccounts/{{target_netapp_account}}/capacityPools/{{target_capacity_pool}}/volumes/{{target_volume_name}}/peerExternalCluster" \
        '{"PeerClusterName":"{{source_cluster_name}}","PeerAddresses":["{{source_peer_addresses}}"]}' \
        "Issue Cluster Peer Request"
    
    # Step 4: Authorize external replication
    run_api_call "authorize_replication" "POST" \
        "/subscriptions/{{azure_subscription_id}}/resourceGroups/{{target_resource_group}}/providers/Microsoft.NetApp/netAppAccounts/{{target_netapp_account}}/capacityPools/{{target_capacity_pool}}/volumes/{{target_volume_name}}/authorizeExternalReplication" \
        "" \
        "Authorize External Replication"
    
    # Step 5: Perform replication transfer
    run_api_call "replication_transfer" "POST" \
        "/subscriptions/{{azure_subscription_id}}/resourceGroups/{{target_resource_group}}/providers/Microsoft.NetApp/netAppAccounts/{{target_netapp_account}}/capacityPools/{{target_capacity_pool}}/volumes/{{target_volume_name}}/performReplicationTransfer" \
        "" \
        "Perform Replication Transfer"
    
    # Step 6: Break replication relationship
    run_api_call "break_replication" "POST" \
        "/subscriptions/{{azure_subscription_id}}/resourceGroups/{{target_resource_group}}/providers/Microsoft.NetApp/netAppAccounts/{{target_netapp_account}}/capacityPools/{{target_capacity_pool}}/volumes/{{target_volume_name}}/breakReplication" \
        "" \
        "Break Replication Relationship"
    
    # Step 7: Finalize external replication
    run_api_call "finalize_replication" "POST" \
        "/subscriptions/{{azure_subscription_id}}/resourceGroups/{{target_resource_group}}/providers/Microsoft.NetApp/netAppAccounts/{{target_netapp_account}}/capacityPools/{{target_capacity_pool}}/volumes/{{target_volume_name}}/finalizeExternalReplication" \
        "" \
        "Finalize External Replication"
    
    success "ANF Migration workflow completed successfully!"
}

# Show configuration summary
show_config() {
    local protocol=$(get_protocol)
    local qos=$(get_qos)
    
    echo "📋 Current Configuration:"
    echo "🌐 Azure Region: $(get_config_value 'target_location')"
    echo "📁 Resource Group: $(get_config_value 'target_resource_group')" 
    echo "🗄️  NetApp Account: $(get_config_value 'target_netapp_account')"
    echo "📊 Capacity Pool: $(get_config_value 'target_capacity_pool')"
    echo "💾 Volume: $(get_config_value 'target_volume_name')"
    echo "🔌 Protocol: $protocol"
    echo "⚡ QoS: $qos"
    echo "🔄 Replication: $(get_config_value 'replication_schedule')"
    echo "🖥️  Source Cluster: $(get_config_value 'source_cluster_name')"
}

# Main execution
case "${1:-run}" in
    "run")
        run_workflow
        ;;
    "config")
        show_config
        ;;
    "token")
        get_token
        ;;
    *)
        echo "Usage: $0 [run|config|token]"
        echo ""
        echo "  run    - Execute the complete migration workflow"
        echo "  config - Show current configuration"
        echo "  token  - Get fresh authentication token"
        ;;
esac
