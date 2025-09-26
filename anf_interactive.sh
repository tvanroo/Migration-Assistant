#!/bin/bash
# Azure NetApp Files Migration Assistant - Interactive Step-by-Step Mode
# Execute each REST API call individually with result inspection
#
# ASYNC RESPONSE DATA HANDLING:
# - When async operations complete, their final response data is stored automatically
# - Access via: get_last_async_response_data (full JSON)
# - Access via: get_async_response_field "field.path" (specific field)
# - Persistent storage: .last_async_response file
# - Clear with: clear_async_response_data

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Parse command line arguments for custom config file
CONFIG_FILENAME="config.yaml"  # default
while [[ $# -gt 0 ]]; do
    case $1 in
        --config)
            CONFIG_FILENAME="$2"
            shift 2
            ;;
        -c)
            CONFIG_FILENAME="$2"  
            shift 2
            ;;
        --config=*)
            CONFIG_FILENAME="${1#*=}"
            shift
            ;;
        *)
            # Keep other arguments for later processing
            break
            ;;
    esac
done

CONFIG_FILE="${SCRIPT_DIR}/${CONFIG_FILENAME}"
TOKEN_FILE="${SCRIPT_DIR}/.token"
LOG_FILE="${SCRIPT_DIR}/anf_migration_interactive.log"

# Detect Python command early and store globally
# Test actual Python functionality, not just command existence
if python3 --version >/dev/null 2>&1; then
    PYTHON_CMD="python3"
    echo "Using Python command: python3 ($(python3 --version 2>&1))"
elif python --version >/dev/null 2>&1; then
    PYTHON_CMD="python"
    echo "Using Python command: python ($(python --version 2>&1))"
elif py --version >/dev/null 2>&1; then
    PYTHON_CMD="py"
    echo "Using Python command: py ($(py --version 2>&1))"
else
    PYTHON_CMD="python"  # fallback
    echo "Using Python command: python (fallback - may not work)"
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Enhanced messaging
error_exit() {
    echo -e "${RED}❌ Error: $1${NC}" >&2
    log "ERROR: $1"
    exit 1
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
    log "SUCCESS: $1"
}

info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
    log "INFO: $1"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
    log "WARNING: $1"
}

step_header() {
    echo ""
    echo -e "${PURPLE}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║ $1${NC}"
    echo -e "${PURPLE}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Read config value using Python
get_config_value() {
    local key="$1"
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo ""
        return 1
    fi
    
    $PYTHON_CMD -c "
import yaml
try:
    with open('$CONFIG_FILE') as f:
        config = yaml.safe_load(f)
        all_vars = {**config.get('variables', {}), **config.get('secrets', {})}
        print(all_vars.get('$key', ''))
except Exception:
    print('')
" 2>/dev/null
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

# Enhanced user confirmation with options
confirm_step() {
    local step_name="$1"
    local description="$2"
    local force_prompt="${3:-false}"  # Optional third parameter to force prompting even in minimal mode
    
    # Check interaction mode - skip prompting in minimal mode unless forced
    if [[ "${ANF_INTERACTION_MODE:-full}" == "minimal" && "$force_prompt" != "true" ]]; then
        info "Auto-continuing: $step_name ($description)"
        return 0
    fi
    
    # Skip prompts in monitoring mode
    if [[ "$ANF_MONITORING_MODE" == "true" ]]; then
        return 0  # Auto-continue
    fi
    
    echo -e "${CYAN}📋 Next: $step_name${NC}"
    echo -e "${CYAN}$description${NC}"
    echo ""
    echo "Options:"
    echo "  [C] Continue (default)"
    echo "  [w] Wait here"
    echo "  [r] Re-run / Review config"
    echo "  [q] Quit workflow"
    echo ""
    
    while true; do
        read -p "Choose an option [C/w/r/q]: " -n 1 -r
        echo ""
        case $REPLY in
            [Cc]|"")  # Default to continue if just ENTER is pressed
                return 0  # Continue
                ;;
            [Ww])
                echo -e "${CYAN}⏸️  Workflow paused. Press ENTER when ready to continue...${NC}"
                read
                echo -e "${CYAN}📋 Next: $step_name${NC}"
                echo -e "${CYAN}$description${NC}"
                echo ""
                ;;
            [Rr])
                show_config
                echo ""
                echo -e "${CYAN}📋 Next: $step_name${NC}"
                echo -e "${CYAN}$description${NC}"
                echo ""
                echo "Options:"
                echo "  [C] Continue (default)"
                echo "  [w] Wait here"
                echo "  [r] Re-run / Review config"
                echo "  [q] Quit workflow"
                echo ""
                ;;
            [Qq])
                info "Workflow terminated by user"
                exit 0
                ;;
            *)
                echo "Invalid option. Please choose C (continue), w (wait), r (re-run), or q (quit). Press ENTER for continue."
                ;;
        esac
    done
}

# Show configuration summary
show_config() {
    local protocol=$(get_protocol)
    local qos=$(get_qos)
    
    echo "📋 Current Configuration:"
    echo "📄 Config File: $CONFIG_FILE"
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

# Enhanced API call with detailed response handling
execute_api_call() {
    local step_name="$1"
    local method="$2"
    local endpoint="$3"
    local data="$4"
    local description="$5"
    local expected_status="${6:-200,201,202,204}"
    
    step_header "Step: $step_name"
    
    if ! confirm_step "$step_name" "$description"; then
        return 0  # Step was skipped
    fi
    
    # Ensure we have a valid token
    if [[ ! -f "$TOKEN_FILE" ]]; then
        info "Getting authentication token first..."
        get_token
    fi
    
    local token=$(cat "$TOKEN_FILE")
    local api_url=$(get_config_value 'azure_api_base_url')
    local api_version=$(get_config_value 'azure_api_version')
    
    # Build the full URL
    local full_url="${api_url}${endpoint}?api-version=${api_version}"
    
    # Replace variables in URL
    full_url=$(echo "$full_url" | $PYTHON_CMD -c "
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
        data=$(echo "$data" | $PYTHON_CMD -c "
import sys, yaml, json
with open('$CONFIG_FILE') as f:
    config = yaml.safe_load(f)
    all_vars = {**config.get('variables', {}), **config.get('secrets', {})}
    
data = sys.stdin.read()

for key, value in all_vars.items():
    # Special handling for peer addresses to support multiple IPs
    if key == 'source_peer_addresses' and '{{source_peer_addresses}}' in data:
        # Check if value is already a JSON array
        try:
            parsed_addrs = json.loads(str(value))
            if isinstance(parsed_addrs, list):
                # It's already a JSON array, insert it directly
                json_array = json.dumps(parsed_addrs)
                data = data.replace('[\"{{' + key + '}}\"]', json_array)
            else:
                # Single IP, keep as is
                data = data.replace('{{' + key + '}}', str(value))
        except (json.JSONDecodeError, TypeError):
            # Not JSON, treat as single IP
            data = data.replace('{{' + key + '}}', str(value))
    else:
        # Normal variable substitution
        data = data.replace('{{' + key + '}}', str(value))

# Pretty print JSON if it's valid JSON
try:
    parsed = json.loads(data)
    print(json.dumps(parsed, indent=2))
except:
    print(data, end='')
")
    fi
    
    info "Making API call..."
    echo -e "${CYAN}Method: $method${NC}"
    echo -e "${CYAN}URL: $full_url${NC}"
    
    if [[ -n "$data" ]]; then
        echo -e "${CYAN}Request Body:${NC}"
        echo "$data" | head -20
        if [[ $(echo "$data" | wc -l) -gt 20 ]]; then
            echo -e "${YELLOW}... (truncated, see logs for full payload)${NC}"
        fi
    fi
    
    echo ""
    info "Executing request..."
    
    # Create temporary files for response and headers
    local response_file=$(mktemp)
    local headers_file=$(mktemp)
    
    # Execute the API call
    local http_status
    if [[ -n "$data" ]]; then
        http_status=$(curl -s -w "%{http_code}" -o "$response_file" -D "$headers_file" \
            -X "$method" \
            -H "Authorization: Bearer $token" \
            -H "Content-Type: application/json" \
            --data "$data" \
            "$full_url")
    else
        # For POST requests without data, we still need to include Content-Type and Content-Length headers
        if [[ "$method" == "POST" || "$method" == "PUT" || "$method" == "PATCH" ]]; then
            http_status=$(curl -s -w "%{http_code}" -o "$response_file" -D "$headers_file" \
                -X "$method" \
                -H "Authorization: Bearer $token" \
                -H "Content-Type: application/json" \
                -H "Content-Length: 0" \
                --data "" \
                "$full_url")
        else
            http_status=$(curl -s -w "%{http_code}" -o "$response_file" -D "$headers_file" \
                -X "$method" \
                -H "Authorization: Bearer $token" \
                "$full_url")
        fi
    fi
    
    # Log full request/response
    log "API Call: $method $full_url"
    log "HTTP Status: $http_status"
    log "Response Headers: $(cat "$headers_file")"
    log "Response Body: $(cat "$response_file")"
    
    # Display results
    echo ""
    echo -e "${PURPLE}═══ API RESPONSE ═══${NC}"
    echo -e "${CYAN}HTTP Status: $http_status${NC}"
    
    # Check if status is expected
    if [[ ",$expected_status," == *",$http_status,"* ]]; then
        success "Request completed successfully (HTTP $http_status)"
    else
        warning "Unexpected HTTP status: $http_status (expected: $expected_status)"
    fi
    
    # Show response headers (filtered)
    echo -e "${CYAN}Key Response Headers:${NC}"
    grep -i -E "(azure-asyncoperation|location|retry-after|x-ms-correlation-request-id)" "$headers_file" | head -5 || true
    
    # Show response body (pretty printed if JSON)
    echo -e "${CYAN}Response Body:${NC}"
    local response_content=$(cat "$response_file")
    
    if [[ -n "$response_content" ]]; then
        # Try to pretty print as JSON
        if echo "$response_content" | $PYTHON_CMD -c "import json, sys; json.load(sys.stdin)" 2>/dev/null; then
            echo "$response_content" | $PYTHON_CMD -c "import json, sys; print(json.dumps(json.load(sys.stdin), indent=2))"
        else
            echo "$response_content"
        fi
    else
        echo -e "${YELLOW}(Empty response body)${NC}"
    fi
    
    # Extract async operation info if present
    local async_url=$(grep -i "azure-asyncoperation:" "$headers_file" | cut -d' ' -f2- | tr -d '\r' || true)
    local location_url=$(grep -i "location:" "$headers_file" | cut -d' ' -f2- | tr -d '\r' || true)
    
    # Handle monitoring based on user's preference
    local should_monitor="false"
    local monitoring_mode="${ANF_MONITORING_MODE:-custom}"
    
    # Special handling for volume creation - use direct status check instead of async monitoring
    if [[ "$step_name" == "create_volume" && -n "$async_url" ]]; then
        echo ""
        echo -e "${YELLOW}🔄 This is a volume creation operation${NC}"
        echo -e "${YELLOW}Using direct volume status check instead of async monitoring${NC}"
        
        # Determine if we should check volume status
        case $monitoring_mode in
            "full")
                should_monitor="true"
                ;;
            "quick")
                should_monitor="false"
                info "Quick mode: Skipping volume status check"
                ;;
            "custom")
                if ask_user_choice "Do you want to verify the volume is ready?" "y"; then
                    should_monitor="true"
                fi
                ;;
        esac
        
        if [[ "$should_monitor" == "true" ]]; then
            local volume_name=$(get_config_value 'target_volume_name')
            check_volume_status "$volume_name"  # Use default 40 attempts (20 minutes)
        else
            info "Skipping volume status check. You can verify in Azure portal."
        fi
        
    elif [[ -n "$async_url" ]]; then
        echo ""
        echo -e "${YELLOW}🔄 This is an asynchronous operation${NC}"
        echo -e "${YELLOW}Async Status URL: $async_url${NC}"
        
        # Determine if we should monitor async operation
        case $monitoring_mode in
            "full")
                should_monitor="true"
                ;;
            "quick")
                # Only monitor critical long-running operations in quick mode
                if [[ "$step_name" == "replication_transfer" ]]; then
                    should_monitor="true"
                    info "Quick mode: Monitoring critical replication transfer operation"
                else
                    should_monitor="false"
                    info "Quick mode: Skipping monitoring for $step_name"
                fi
                ;;
            "custom")
                echo ""
                echo -e "${CYAN}⚠️  Async operation detected - monitoring decision required${NC}"
                if ask_user_choice "Do you want to monitor this operation?" "y"; then
                    should_monitor="true"
                fi
                ;;
        esac
        
        if [[ "$should_monitor" == "true" ]]; then
            # Monitor the async operation (response file path will be stored in global variable)
            monitor_async_operation "$async_url"
            local monitor_result=$?
            
            if [[ $monitor_result -eq 0 && -n "$ASYNC_RESPONSE_FILE" && -f "$ASYNC_RESPONSE_FILE" ]]; then
                # Store the final async response in a global variable for use in next steps
                export LAST_ASYNC_RESPONSE_FILE="$ASYNC_RESPONSE_FILE"
                export LAST_ASYNC_RESPONSE_DATA=$(cat "$ASYNC_RESPONSE_FILE")
                info "Final async response data stored for use in subsequent steps"
                
                # Optional: Save to a persistent file for debugging
                local persistent_file="${SCRIPT_DIR}/.last_async_response"
                cp "$ASYNC_RESPONSE_FILE" "$persistent_file"
                info "Async response also saved to: $persistent_file"
            fi
        else
            info "You can manually check status later with: curl -H \"Authorization: Bearer \$(cat .token)\" \"$async_url\""
        fi
        
    elif [[ -n "$location_url" ]]; then
        echo ""
        echo -e "${YELLOW}📍 Location header present: $location_url${NC}"
    fi
    
    echo ""
    echo -e "${PURPLE}═══ END RESPONSE ═══${NC}"
    
    # Clean up temp files
    rm -f "$response_file" "$headers_file"
    
    # Auto-continue to next step (no more post-step prompts)
    success "Step completed - proceeding to next step"
    return 0
}

# Check volume status directly
check_volume_status() {
    local volume_name="$1"
    local max_attempts=${2:-40}  # Default 40 attempts (20 minutes total)
    local attempt=1
    
    info "Checking volume status..."
    info "Volume creation can take up to 10 minutes. Will check every 30 seconds for up to 20 minutes."
    
    while [[ $attempt -le $max_attempts ]]; do
        echo ""
        echo -e "${CYAN}🔍 Status Check $attempt/$max_attempts - $(date '+%H:%M:%S')${NC}"
        
        local token=$(cat "$TOKEN_FILE" 2>/dev/null || echo "")
        if [[ -z "$token" ]]; then
            warning "Token expired, getting new one..."
            get_token
            token=$(cat "$TOKEN_FILE")
        fi
        
        local api_url=$(get_config_value 'azure_api_base_url')
        local api_version=$(get_config_value 'azure_api_version')
        local subscription_id=$(get_config_value 'azure_subscription_id')
        local resource_group=$(get_config_value 'target_resource_group')
        local account_name=$(get_config_value 'target_netapp_account')
        local pool_name=$(get_config_value 'target_capacity_pool')
        
        # Build volume status URL
        local volume_url="${api_url}/subscriptions/${subscription_id}/resourceGroups/${resource_group}/providers/Microsoft.NetApp/netAppAccounts/${account_name}/capacityPools/${pool_name}/volumes/${volume_name}?api-version=${api_version}"
        
        # Check volume status
        local volume_response=$(curl -s -H "Authorization: Bearer $token" "$volume_url")
        
        if [[ $? -ne 0 ]]; then
            warning "Failed to check volume status (attempt $attempt)"
        else
            # Parse the response
            # Temporarily disable set -e to prevent script exit on non-zero Python exit codes
            set +e
            echo "$volume_response" | $PYTHON_CMD -c "
import json, sys
try:
    data = json.load(sys.stdin)
    state = data.get('properties', {}).get('provisioningState', 'Unknown')
    file_system_id = data.get('properties', {}).get('fileSystemId', 'N/A')
    mount_targets = data.get('properties', {}).get('mountTargets', [])
    
    print(f'Provisioning State: {state}')
    print(f'File System ID: {file_system_id}')
    
    if mount_targets:
        for i, target in enumerate(mount_targets):
            ip = target.get('ipAddress', 'N/A')
            fqdn = target.get('smbServerFqdn', target.get('serverFqdn', 'N/A'))
            print(f'Mount Target {i+1}: {ip} ({fqdn})')
    
    # Check if volume is ready
    if state in ['Succeeded', 'Available']:
        print('✅ Volume is ready!')
        sys.exit(0)
    elif state in ['Failed', 'Error']:
        print('❌ Volume creation failed!')
        sys.exit(1)
    else:
        print(f'⏳ Volume is still being created... ({state})')
        sys.exit(2)
except Exception as e:
    print(f'Error parsing volume status: {str(e)}')
    print('Raw response (first 200 chars):')
    raw = sys.stdin.read()
    print(raw[:200])
    sys.exit(2)
" 2>/dev/null
            
            local parse_result=$?
            # Re-enable set -e
            set -e
            case $parse_result in
                0)
                    success "Volume is ready and available!"
                    return 0
                    ;;
                1)
                    error_exit "Volume creation failed"
                    ;;
                2)
                    info "Volume still being created..."
                    ;;
            esac
        fi
        
        if [[ $attempt -lt $max_attempts ]]; then
            echo -e "${YELLOW}⏳ Waiting 30 seconds before next check...${NC}"
            sleep 30
        fi
        
        ((attempt++))
    done
    
    warning "Volume status check timeout after 20 minutes. Volume may still be provisioning."
    info "You can manually check volume status in the Azure portal or wait longer if needed."
    return 0
}

# Monitor replication status with metrics and transfer rate calculations
monitor_replication_status() {
    local volume_name="$1"
    local max_checks=${2:-30}  # Default 30 checks (30 minutes)
    local check_interval=60    # 1 minute intervals
    
    step_header "Replication Status Monitor"
    info "Starting real-time replication monitoring for volume: $volume_name"
    echo ""
    echo -e "${YELLOW}📊 Note: Azure metrics typically have a 5-minute delay in updates${NC}"
    echo -e "${BLUE}ℹ️  Monitoring will refresh every 60 seconds${NC}"
    echo -e "${BLUE}ℹ️  Press Ctrl+C at any time to stop monitoring and continue${NC}"
    echo ""
    
    # Variables to track transfer progress
    local initial_total_bytes=0
    local initial_timestamp=""
    # Cross-platform timestamp initialization
    local monitoring_start_time
    monitoring_start_time=$($PYTHON_CMD -c "import time; print(int(time.time()))")
    local first_measurement_taken=false
    local check_count=0
    
    while [[ $check_count -lt $max_checks ]]; do
        ((check_count++))
        local current_time=$(date '+%H:%M:%S')
        echo -e "${CYAN}🔍 Replication Check $check_count/$max_checks - $current_time${NC}"
        
        # Get fresh token
        local token=$(cat "$TOKEN_FILE" 2>/dev/null || echo "")
        if [[ -z "$token" ]]; then
            warning "Token expired, getting new one..."
            get_token
            token=$(cat "$TOKEN_FILE")
        fi
        
        # Build metrics API URLs
        local subscription_id=$(get_config_value 'azure_subscription_id')
        local resource_group=$(get_config_value 'target_resource_group')
        local account_name=$(get_config_value 'target_netapp_account')
        local pool_name=$(get_config_value 'target_capacity_pool')
        
        local resource_id="/subscriptions/${subscription_id}/resourceGroups/${resource_group}/providers/Microsoft.NetApp/netAppAccounts/${account_name}/capacityPools/${pool_name}/volumes/${volume_name}"
        local metrics_base_url="https://management.azure.com${resource_id}/providers/Microsoft.Insights/metrics"
        
        # Get current time for metrics query using Python for cross-platform reliability
        local time_calculations
        time_calculations=$($PYTHON_CMD -c "
import datetime
now = datetime.datetime.utcnow()
start = now - datetime.timedelta(minutes=10)
print('{0}|{1}'.format(now.strftime('%Y-%m-%dT%H:%M:%SZ'), start.strftime('%Y-%m-%dT%H:%M:%SZ')))
")
        
        local end_time=$(echo "$time_calculations" | cut -d'|' -f1)
        local start_time=$(echo "$time_calculations" | cut -d'|' -f2)
        
        # Query replication metrics
        local metrics_url="${metrics_base_url}?api-version=2018-01-01&metricnames=VolumeReplicationTotalTransfer,VolumeReplicationTotalProgress&timespan=${start_time}/${end_time}&interval=PT1M"
        
        local metrics_response=$(curl -s --max-time 30 -H "Authorization: Bearer $token" "$metrics_url" 2>/dev/null)
        local curl_exit_code=$?
        
        if [[ $curl_exit_code -eq 0 && -n "$metrics_response" ]]; then
            # Parse metrics response
            # Temporarily disable set -e to prevent script exit on Python errors
            set +e
            echo "$metrics_response" | $PYTHON_CMD -c "
import json, sys
from datetime import datetime, timezone
try:
    data = json.load(sys.stdin)
    if 'value' in data and len(data['value']) > 0:
        for metric in data['value']:
            metric_name = metric.get('name', {}).get('value', 'Unknown')
            timeseries = metric.get('timeseries', [])
            
            if metric_name == 'VolumeReplicationTotalTransfer':
                if timeseries and len(timeseries) > 0 and 'data' in timeseries[0]:
                    data_points = timeseries[0]['data']
                    if data_points:
                        # Get the most recent data point
                        latest_point = data_points[-1]
                        total_bytes = latest_point.get('total', 0)
                        timestamp = latest_point.get('timeStamp', '')
                        
                        # Convert bytes to human readable format
                        if total_bytes >= 1024**4:  # TB
                            size_str = f'{total_bytes / (1024**4):.2f} TB'
                        elif total_bytes >= 1024**3:  # GB
                            size_str = f'{total_bytes / (1024**3):.2f} GB'
                        elif total_bytes >= 1024**2:  # MB
                            size_str = f'{total_bytes / (1024**2):.2f} MB'
                        else:
                            size_str = f'{total_bytes} bytes'
                        
                        print(f'📊 Total Transferred: {size_str}')
                        print(f'🕒 Last Update: {timestamp}')
                        
                        # Store for rate calculation
                        with open('.replication_stats', 'w') as f:
                            f.write(f'{total_bytes}|{timestamp}')
                    else:
                        print('📊 Total Transferred: No data available yet')
                else:
                    print('📊 Total Transferred: Waiting for metrics...')
            
            elif metric_name == 'VolumeReplicationTotalProgress':
                if timeseries and len(timeseries) > 0 and 'data' in timeseries[0]:
                    data_points = timeseries[0]['data']
                    if data_points:
                        latest_point = data_points[-1]
                        progress_bytes = latest_point.get('total', 0)
                        
                        if progress_bytes >= 1024**4:  # TB
                            progress_str = f'{progress_bytes / (1024**4):.2f} TB'
                        elif progress_bytes >= 1024**3:  # GB
                            progress_str = f'{progress_bytes / (1024**3):.2f} GB'
                        elif progress_bytes >= 1024**2:  # MB
                            progress_str = f'{progress_bytes / (1024**2):.2f} MB'
                        else:
                            progress_str = f'{progress_bytes} bytes'
                        
                        print(f'📈 Progress: {progress_str}')
    else:
        print('📊 Metrics: No data available (may be too early or metrics delay)')
        
except Exception as e:
    print(f'📊 Metrics: Error parsing response - {str(e)}')
    print('Raw response (first 100 chars):')
    raw = sys.stdin.read()[:100]
    print(raw)
" 2>/dev/null
            # Re-enable set -e
            set -e
            
            # Calculate average transfer rate since monitoring started
            if [[ -f ".replication_stats" ]]; then
                local stats_line=$(cat ".replication_stats" 2>/dev/null)
                local current_bytes=$(echo "$stats_line" | cut -d'|' -f1)
                local current_timestamp=$(echo "$stats_line" | cut -d'|' -f2)
                
                if [[ "$first_measurement_taken" == "false" && -n "$current_bytes" && "$current_bytes" != "0" ]]; then
                    # Store initial measurement for average calculation
                    initial_total_bytes=$current_bytes
                    initial_timestamp="$current_timestamp"
                    first_measurement_taken=true
                    echo -e "${BLUE}🏁 Baseline established: Starting average rate calculation${NC}"
                elif [[ "$first_measurement_taken" == "true" && -n "$current_bytes" && "$current_bytes" != "$initial_total_bytes" ]]; then
                    # Calculate average transfer rate since monitoring started
                    local bytes_transferred=$((current_bytes - initial_total_bytes))
                    # Cross-platform current time calculation
                    local current_time
                    current_time=$($PYTHON_CMD -c "import time; print(int(time.time()))")
                    local elapsed_seconds=$((current_time - monitoring_start_time))
                    
                    if [[ $elapsed_seconds -gt 0 && $bytes_transferred -gt 0 ]]; then
                        local avg_bytes_per_sec=$((bytes_transferred / elapsed_seconds))
                        
                        # Use Python for decimal calculations instead of bc
                        local rate_calculations=$($PYTHON_CMD -c "
avg_bytes_per_sec = $avg_bytes_per_sec
avg_mbps = (avg_bytes_per_sec * 8) / (1024 * 1024)
avg_mb_per_sec = avg_bytes_per_sec / (1024 * 1024)
bytes_transferred = $bytes_transferred

# Format transferred amount
if bytes_transferred >= (1024**3):  # GB
    transferred_str = f'{bytes_transferred / (1024**3):.2f} GB'
elif bytes_transferred >= (1024**2):  # MB
    transferred_str = f'{bytes_transferred / (1024**2):.2f} MB'
else:
    transferred_str = f'{bytes_transferred} bytes'

print(f'{avg_mb_per_sec:.2f}|{avg_mbps:.2f}|{transferred_str}')
")
                        
                        local avg_mb_per_sec=$(echo "$rate_calculations" | cut -d'|' -f1)
                        local avg_mbps=$(echo "$rate_calculations" | cut -d'|' -f2)
                        local transferred_str=$(echo "$rate_calculations" | cut -d'|' -f3)
                        
                        # Calculate elapsed time in human readable format
                        local hours=$((elapsed_seconds / 3600))
                        local minutes=$(((elapsed_seconds % 3600) / 60))
                        local seconds=$((elapsed_seconds % 60))
                        
                        local elapsed_str=""
                        if [[ $hours -gt 0 ]]; then
                            elapsed_str="${hours}h ${minutes}m ${seconds}s"
                        elif [[ $minutes -gt 0 ]]; then
                            elapsed_str="${minutes}m ${seconds}s"
                        else
                            elapsed_str="${seconds}s"
                        fi
                        
                        echo -e "${GREEN}🚀 Average Transfer Rate: ${avg_mb_per_sec} MB/s (${avg_mbps} Mbps)${NC}"
                        echo -e "${GREEN}📈 Total Progress: ${transferred_str} in ${elapsed_str}${NC}"
                    else
                        echo -e "${YELLOW}🚀 Average Transfer Rate: Calculating... (need more time)${NC}"
                    fi
                elif [[ "$first_measurement_taken" == "true" ]]; then
                    echo -e "${YELLOW}🚀 Average Transfer Rate: No new data since baseline${NC}"
                fi
            fi
        else
            warning "Failed to retrieve metrics (attempt $check_count)"
        fi
        
        echo ""
        
        # Check if user wants to stop monitoring
        if [[ $check_count -lt $max_checks ]]; then
            echo -e "${BLUE}⏳ Next check in 60 seconds... (Press Ctrl+C to stop monitoring)${NC}"
            
            # Use timeout to allow interruption
            timeout 60 sleep 60 2>/dev/null || sleep 60
        fi
    done
    
    # Cleanup temp file
    rm -f ".replication_stats" 2>/dev/null
    
    echo ""
    echo -e "${GREEN}✅ Replication monitoring completed${NC}"
    echo -e "${BLUE}💡 You can continue monitoring in the Azure Portal or restart this monitor anytime${NC}"
}

# List all replication volumes and let user select one to monitor
list_replication_volumes() {
    step_header "Available Replication Volumes"
    
    info "Discovering replication volumes in your NetApp account..."
    
    # Get fresh token
    get_token_interactive
    
    local token=$(cat "$TOKEN_FILE" 2>/dev/null || echo "")
    local subscription_id=$(get_config_value 'azure_subscription_id')
    local resource_group=$(get_config_value 'target_resource_group')
    local account_name=$(get_config_value 'target_netapp_account')
    
    # List all capacity pools in the account
    local pools_url="https://management.azure.com/subscriptions/${subscription_id}/resourceGroups/${resource_group}/providers/Microsoft.NetApp/netAppAccounts/${account_name}/capacityPools?api-version=2025-06-01"
    
    info "Retrieving capacity pools..."
    local pools_response=$(curl -s --max-time 30 -H "Authorization: Bearer $token" "$pools_url")
    
    if [[ $? -ne 0 ]]; then
        error_exit "Failed to retrieve capacity pools"
    fi
    
    # Parse pools and get volumes with replication
    echo "$pools_response" | $PYTHON_CMD -c "
import json, sys, subprocess, os
try:
    pools_data = json.load(sys.stdin)
    replication_volumes = []
    
    if 'value' in pools_data:
        for pool in pools_data['value']:
            pool_name = pool.get('name', 'Unknown')
            print(f'Checking pool: {pool_name}...', file=sys.stderr)
            
            # Get volumes in this pool
            pool_resource_id = pool.get('id', '')
            if pool_resource_id:
                volumes_url = f'https://management.azure.com{pool_resource_id}/volumes?api-version=2025-06-01'
                
                # Use subprocess to call curl for volumes
                cmd = ['curl', '-s', '--max-time', '30', 
                       '-H', 'Authorization: Bearer $token'.replace('$token', os.environ.get('ANF_TOKEN', '')), 
                       volumes_url]
                
                try:
                    result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
                    if result.returncode == 0:
                        volumes_data = json.loads(result.stdout)
                        
                        if 'value' in volumes_data:
                            for volume in volumes_data['value']:
                                # Check if volume has replication configured
                                properties = volume.get('properties', {})
                                data_protection = properties.get('dataProtection', {})
                                replication = data_protection.get('replication', {})
                                
                                if replication and properties.get('volumeType') == 'Migration':
                                    volume_name = volume.get('name', 'Unknown')
                                    creation_token = properties.get('creationToken', '')
                                    remote_path = replication.get('remotePath', {})
                                    source_volume = remote_path.get('volumeName', 'Unknown')
                                    source_server = remote_path.get('serverName', 'Unknown')
                                    replication_schedule = replication.get('replicationSchedule', 'Unknown')
                                    
                                    replication_volumes.append({
                                        'volume_name': creation_token or volume_name.split('/')[-1],
                                        'full_name': volume_name,
                                        'source_volume': source_volume,
                                        'source_server': source_server,
                                        'schedule': replication_schedule,
                                        'pool_name': pool_name
                                    })
                                    
                except Exception as e:
                    print(f'Error checking volumes in pool {pool_name}: {str(e)}', file=sys.stderr)
    
    if replication_volumes:
        print(f'Found {len(replication_volumes)} replication volume(s):')
        print('')
        for i, vol in enumerate(replication_volumes, 1):
            print(f'{i}. Volume: {vol[\"volume_name\"]}')
            print(f'   Source: {vol[\"source_volume\"]} (from {vol[\"source_server\"]})')
            print(f'   Schedule: {vol[\"schedule\"]}')
            print(f'   Pool: {vol[\"pool_name\"]}')
            print('')
        
        # Store the list for selection
        with open('.replication_volumes_list', 'w') as f:
            json.dump(replication_volumes, f)
        
        sys.exit(0)
    else:
        print('No replication volumes found.')
        print('Make sure you have completed the peering setup phase for at least one migration.')
        sys.exit(1)
        
except Exception as e:
    print(f'Error listing replication volumes: {str(e)}')
    print('Raw response (first 200 chars):')
    raw = sys.stdin.read()
    print(raw[:200])
    sys.exit(2)
" 2>/dev/null
    
    local list_result=$?
    case $list_result in
        0)
            return 0  # Success, volumes found
            ;;
        1)
            warning "No replication volumes found"
            return 1
            ;;
        2)
            error_exit "Failed to parse volume information"
            ;;
    esac
}

# Standalone replication monitoring workflow
run_replication_monitor_standalone() {
    check_dependencies
    validate_config
    
    # Set monitoring mode to bypass interactive prompts
    export ANF_MONITORING_MODE="true"
    
    step_header "Replication Status Monitor"
    
    info "Starting real-time replication monitoring for all available volumes..."
    echo -e "${YELLOW}📊 Note: Press Ctrl+C at any time to stop monitoring${NC}"
    echo ""
    
    # Set token in environment for Python subprocess
    local token=$(cat "$TOKEN_FILE" 2>/dev/null || echo "")
    export ANF_TOKEN="$token"
    
    # List available replication volumes
    if ! list_replication_volumes; then
        echo ""
        error "No replication volumes found."
        echo "To use this monitoring tool:"
        echo "1. Complete the peering setup phase first (run: ./anf_interactive.sh peering)"
        echo "2. Wait a few minutes for replication to start"
        echo "3. Then run this monitor again"
        exit 1
    fi
    
    # Auto-select first available volume for monitoring
    local selected_info=$($PYTHON_CMD -c "
import json
try:
    with open('.replication_volumes_list', 'r') as f:
        volumes = json.load(f)
    
    if len(volumes) > 0:
        vol = volumes[0]  # Select first volume automatically
        print(f\"{vol['volume_name']}|{vol['source_volume']}\")
    else:
        print('NONE')
except:
    print('ERROR')
")
    
    if [[ "$selected_info" == "NONE" ]]; then
        error_exit "No replication volumes available"
    elif [[ "$selected_info" == "ERROR" ]]; then
        error_exit "Error reading volume list"
    fi
    
    local selected_volume=$(echo "$selected_info" | cut -d'|' -f1)
    local selected_name=$(echo "$selected_info" | cut -d'|' -f2)
    
    # Clean up temp files
    rm -f ".replication_volumes_list" 2>/dev/null
    unset ANF_TOKEN
    
    echo ""
    success "Monitoring volume: $selected_volume (source: $selected_name)"
    info "Monitoring will continue until you press Ctrl+C"
    echo ""
    
    # Start monitoring with unlimited duration (will run until Ctrl+C)
    monitor_replication_status "$selected_volume" "999999"  # Very large number for continuous monitoring
    
    echo ""
    echo -e "${GREEN}🎉 Monitoring session stopped!${NC}"
    
    # Clean up monitoring mode
    unset ANF_MONITORING_MODE
}

# Monitor async operation status and return final response data
monitor_async_operation() {
    local async_url="$1"
    local max_attempts=120  # 2 hours with 1-minute intervals
    local attempt=1
    
    # Create temp file to store final response data
    local final_response_file=$(mktemp)
    
    info "Monitoring asynchronous operation..."
    info "Will check every 60 seconds (max 2 hours)"
    
    while [[ $attempt -le $max_attempts ]]; do
        echo ""
        echo -e "${CYAN}🔍 Check $attempt/$max_attempts - $(date '+%H:%M:%S')${NC}"
        
        local token=$(cat "$TOKEN_FILE" 2>/dev/null || echo "")
        if [[ -z "$token" ]]; then
            warning "Token expired, getting new one..."
            get_token
            token=$(cat "$TOKEN_FILE")
        fi
        
        local status_response=$(curl -s --max-time 30 -H "Authorization: Bearer $token" "$async_url")
        local curl_exit_code=$?
        
        if [[ $curl_exit_code -ne 0 ]]; then
            warning "Failed to check status (attempt $attempt)"
        else
            # Store the response for potential return
            echo "$status_response" > "$final_response_file"
            
            # Temporarily disable set -e to prevent script exit on non-zero Python exit codes
            set +e
            echo "$status_response" | $PYTHON_CMD -c "
import json, sys
try:
    data = json.load(sys.stdin)
    status = data.get('status', 'Unknown')
    percent = data.get('percentComplete', 0)
    start_time = data.get('startTime', '')
    end_time = data.get('endTime', '')
    
    print(f'Status: {status}')
    if percent > 0:
        print(f'Progress: {percent}%')
    if start_time:
        print(f'Started: {start_time}')
    if end_time:
        print(f'Ended: {end_time}')
    
    # Check for error information
    if 'error' in data:
        error_info = data['error']
        if isinstance(error_info, dict):
            print(f'Error Code: {error_info.get(\"code\", \"Unknown\")}')
            print(f'Error Message: {error_info.get(\"message\", \"No message provided\")}')
        else:
            print(f'Error: {error_info}')
    
    # Check for properties with additional info
    if 'properties' in data:
        props = data['properties']
        if 'resourceName' in props:
            print(f'Resource: {props[\"resourceName\"]}')
        if 'action' in props:
            print(f'Action: {props[\"action\"]}')
    
    # Determine exit code based on status
    if status in ['Succeeded', 'Completed']:
        sys.exit(0)  # Success
    elif status in ['Failed', 'Canceled', 'Cancelled']:
        sys.exit(1)  # Failed
    else:
        sys.exit(2)  # In progress (Creating, Running, InProgress, etc.)
except Exception as e:
    print(f'Error parsing status response: {str(e)}')
    raw = sys.stdin.read()
    print(raw[:500])
    if len(raw) > 500:
        print('...(truncated)')
    sys.exit(2)
" 2>/dev/null
            
            local parse_result=$?
            # Re-enable set -e
            set -e
            case $parse_result in
                0)
                    success "Operation completed successfully!"
                    echo ""
                    echo -e "${CYAN}Final Async Response Data:${NC}"
                    # Pretty print the final response
                    if cat "$final_response_file" | $PYTHON_CMD -c "import json, sys; json.load(sys.stdin)" 2>/dev/null; then
                        cat "$final_response_file" | $PYTHON_CMD -c "import json, sys; print(json.dumps(json.load(sys.stdin), indent=2))"
                    else
                        cat "$final_response_file"
                    fi
                    echo ""
                    
                    # Check if this response contains cluster or SVM peering information and display it
                    local cluster_command
                    local cluster_passphrase
                    local svm_command
                    
                    cluster_command=$(cat "$final_response_file" | $PYTHON_CMD -c "
import json, sys
try:
    data = json.load(sys.stdin)
    if 'properties' in data and 'clusterPeeringCommand' in data['properties']:
        print(data['properties']['clusterPeeringCommand'])
except:
    pass
" 2>/dev/null)
                    
                    cluster_passphrase=$(cat "$final_response_file" | $PYTHON_CMD -c "
import json, sys
try:
    data = json.load(sys.stdin)
    if 'properties' in data and 'passphrase' in data['properties']:
        print(data['properties']['passphrase'])
except:
    pass
" 2>/dev/null)
                    
                    svm_command=$(cat "$final_response_file" | $PYTHON_CMD -c "
import json, sys
try:
    data = json.load(sys.stdin)
    # Try both case variations for SVM peering command
    if 'properties' in data:
        if 'SvmPeeringCommand' in data['properties']:
            print(data['properties']['SvmPeeringCommand'])
        elif 'svmPeeringCommand' in data['properties']:
            print(data['properties']['svmPeeringCommand'])
except:
    pass
" 2>/dev/null)
                    
                    if [[ -n "$cluster_command" && -n "$cluster_passphrase" ]]; then
                        echo ""
                        echo -e "${GREEN}✅ Cluster Peer Command Retrieved:${NC}"
                        echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
                        echo -e "${CYAN}║ EXECUTE THIS COMMAND ON YOUR ON-PREMISES ONTAP SYSTEM:                      ║${NC}"
                        echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
                        echo ""
                        echo -e "${YELLOW}$cluster_command${NC}"
                        echo ""
                        echo -e "${GREEN}📋 Passphrase:${NC}"
                        echo -e "${YELLOW}$cluster_passphrase${NC}"
                        echo ""
                        echo -e "${BLUE}📋 Configuration Reference Values:${NC}"
                        local source_peer_addresses=$(get_config_value 'source_peer_addresses')
                        echo -e "${CYAN}  IP-SPACE-NAME: Default (or your custom IP space name)${NC}"
                        echo -e "${CYAN}  peer-addresses-list: $source_peer_addresses${NC}"
                        echo ""
                        echo -e "${CYAN}📝 Instructions:${NC}"
                        echo "  1. Log into your on-premises ONTAP system as an administrator"
                        echo "  2. Replace the placeholders in the command with your actual values:"
                        echo "     - Replace <IP-SPACE-NAME> with your IP space (usually 'Default')"
                        echo "     - Replace <peer-addresses-list> with the peer addresses shown above"
                        echo "  3. Execute the modified command"
                        echo "  4. When prompted, enter the passphrase: $cluster_passphrase"
                        echo "  5. Verify the command completes successfully"
                        echo "  6. Return here and confirm completion"
                        echo ""
                        
                        # Wait for user confirmation
                        while true; do
                            if ask_user_choice "Have you successfully executed the cluster peer command on your ONTAP system?" "n"; then
                                success "Cluster peer command execution confirmed"
                                break
                            else
                                echo ""
                                echo -e "${YELLOW}Please execute this cluster peer command on your ONTAP system:${NC}"
                                echo -e "${YELLOW}$cluster_command${NC}"
                                echo -e "${YELLOW}Passphrase: $cluster_passphrase${NC}"
                                echo -e "${CYAN}Reference - peer addresses: $source_peer_addresses${NC}"
                                echo ""
                                echo "The migration cannot proceed until this command is executed successfully."
                                echo ""
                                if ask_user_choice "Do you want to skip this step? (NOT RECOMMENDED - may cause migration failure)" "n"; then
                                    warning "Cluster peer step skipped by user - migration may fail"
                                    break
                                fi
                            fi
                        done
                    fi
                    
                    if [[ -n "$svm_command" ]]; then
                        echo ""
                        echo -e "${GREEN}✅ SVM Peering Command Retrieved:${NC}"
                        echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
                        echo -e "${CYAN}║ EXECUTE THIS COMMAND ON YOUR ON-PREMISES ONTAP SYSTEM:                      ║${NC}"
                        echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
                        echo ""
                        echo -e "${YELLOW}$svm_command${NC}"
                        echo ""
                        echo -e "${BLUE}📋 Configuration Reference Values:${NC}"
                        local source_svm_name=$(get_config_value 'source_svm_name')
                        local target_svm_name=$(get_config_value 'target_svm_name')
                        echo -e "${CYAN}  source-svm-name: $source_svm_name${NC}"
                        echo ""
                        echo -e "${CYAN}📝 Instructions:${NC}"
                        echo "  1. Log into your on-premises ONTAP system as an administrator"
                        echo "  2. Execute the command as shown (no placeholders to replace)"
                        echo "  3. Verify the command completes successfully"
                        echo "  4. Confirm the snapmirror relationship is healthy using:"
                        echo -e "${YELLOW}     snapmirror show -fields healthy -destination-path <dst_svm>:$(get_config_value 'target_volume_name')${NC}"
                        echo "     (Should show 'healthy: true' in the output)"
                        echo "  5. Return here and confirm completion"
                        echo ""
                        
                        # Wait for user confirmation
                        while true; do
                            if ask_user_choice "Have you successfully executed the SVM peering command on your ONTAP system?" "n"; then
                                success "SVM peering command execution confirmed"
                                
                                # Show completion message and next steps
                                echo ""
                                echo -e "${GREEN}🎉 Data Synchronization Phase Started!${NC}"
                                echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
                                echo -e "${CYAN}║ MIGRATION SETUP COMPLETE - DATA SYNC IN PROGRESS                            ║${NC}"
                                echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
                                echo ""
                                echo -e "${BLUE}📊 What's happening now:${NC}"
                                echo "  • Data is now synchronizing from your on-premises ONTAP system to Azure NetApp Files"
                                echo "  • This initial sync can take several hours or days depending on data size"
                                echo "  • The sync will continue automatically in the background"
                                echo ""
                                echo -e "${YELLOW}📈 How to monitor sync progress:${NC}"
                                echo "  1. Go to the Azure Portal"
                                echo "  2. Navigate to your Azure NetApp Files volume: ${target_volume_name:-[target volume]}"
                                echo "  3. Check the 'Metrics' section for replication progress"
                                echo "  4. Look for metrics like 'is Volume Replication Transferring' and 'Volume Replication Total Transfer'"
                                echo ""
                                echo -e "${PURPLE}⏳ Next steps:${NC}"
                                echo "  1. Wait for the initial data sync to complete (this can take hours/days)"
                                echo "  2. Monitor progress using Azure Portal metrics"
                                echo "  3. When ready to finalize the migration (break replication and make volume writable):"
                                echo "     Run this script again and select the 'break_replication' step"
                                echo ""
                                echo -e "${CYAN}💡 Important notes:${NC}"
                                echo "  • Do NOT break replication until you're ready to switch to the Azure volume"
                                echo "  • Breaking replication makes the Azure volume writable but stops sync from on-premises"
                                echo "  • Plan your cutover carefully to minimize downtime"
                                echo ""
                                
                                # Optional replication monitoring
                                if ask_user_choice "Would you like to monitor the replication status now? (Shows transfer progress and speed)" "n"; then
                                    local target_volume_name=$(get_config_value 'target_volume_name')
                                    echo ""
                                    info "Starting replication monitoring..."
                                    echo -e "${YELLOW}Note: You can stop monitoring at any time with Ctrl+C${NC}"
                                    echo ""
                                    monitor_replication_status "$target_volume_name" 30  # Monitor for up to 30 minutes
                                else
                                    info "Skipping replication monitoring - you can check progress in Azure Portal"
                                fi
                                echo ""
                                
                                echo -e "${GREEN}✅ Setup phase completed successfully!${NC}"
                                echo -e "${BLUE}📝 Detailed logs are available in: $LOG_FILE${NC}"
                                echo ""
                                
                                # Set a flag to indicate we should stop the workflow here
                                export MIGRATION_SYNC_STARTED="true"
                                break
                            else
                                echo ""
                                echo -e "${YELLOW}Please execute this SVM peering command on your ONTAP system:${NC}"
                                echo -e "${YELLOW}$svm_command${NC}"
                                echo -e "${CYAN}Reference - Source SVM: $source_svm_name, Target SVM: $target_svm_name${NC}"
                                echo ""
                                echo "The migration cannot proceed until this command is executed successfully."
                                echo ""
                                if ask_user_choice "Do you want to skip this step? (NOT RECOMMENDED - may cause migration failure)" "n"; then
                                    warning "SVM peering step skipped by user - migration may fail"
                                    break
                                fi
                            fi
                        done
                    fi
                    
                    # Store the response file path in a global variable
                    export ASYNC_RESPONSE_FILE="$final_response_file"
                    return 0
                    ;;
                1)
                    rm -f "$final_response_file"
                    error_exit "Operation failed or was canceled"
                    ;;
                2)
                    info "Operation still in progress..."
                    ;;
            esac
        fi
        
        if [[ $attempt -lt $max_attempts ]]; then
            echo -e "${YELLOW}⏳ Waiting 60 seconds before next check... (Press Ctrl+C to stop monitoring)${NC}"
            sleep 60
        fi
        
        ((attempt++))
    done
    
    rm -f "$final_response_file"
    warning "Monitoring timeout reached (2 hours). Operation may still be running."
    info "You can manually check status with: curl -H \"Authorization: Bearer \$(cat .token)\" \"$async_url\""
    return 1
}

# Helper function for yes/no questions
ask_user_choice() {
    local question="$1"
    local default="${2:-n}"
    
    if [[ "$default" == "y" ]]; then
        prompt="${question} (Y/n): "
    else
        prompt="${question} (y/N): "
    fi
    
    echo -e "${YELLOW}❓ ${prompt}${NC}"
    while true; do
        read -r REPLY
        if [[ -z "$REPLY" ]]; then
            REPLY="$default"
            echo -e "${BLUE}Using default: $default${NC}"
        fi
        case $REPLY in
            [Yy]|[Yy][Ee][Ss])
                return 0
                ;;
            [Nn]|[Nn][Oo])
                return 1
                ;;
            *)
                echo -e "${RED}Please answer yes (y) or no (n).${NC}"
                echo -e "${YELLOW}❓ ${prompt}${NC}"
                ;;
        esac
    done
}

# Helper functions to access async response data in subsequent steps
get_last_async_response_data() {
    if [[ -n "$LAST_ASYNC_RESPONSE_DATA" ]]; then
        echo "$LAST_ASYNC_RESPONSE_DATA"
        return 0
    elif [[ -f "${SCRIPT_DIR}/.last_async_response" ]]; then
        cat "${SCRIPT_DIR}/.last_async_response"
        return 0
    else
        warning "No async response data available"
        return 1
    fi
}

# Extract specific field from last async response
get_async_response_field() {
    local field_path="$1"
    local response_data
    
    if ! response_data=$(get_last_async_response_data); then
        return 1
    fi
    
    echo "$response_data" | $PYTHON_CMD -c "
import json, sys
try:
    data = json.load(sys.stdin)
    field_path = '$field_path'
    
    # Support nested field access with dot notation (e.g., 'properties.provisioningState')
    fields = field_path.split('.')
    result = data
    for field in fields:
        if isinstance(result, dict) and field in result:
            result = result[field]
        else:
            print(f'Field {field_path} not found in response', file=sys.stderr)
            sys.exit(1)
    
    if isinstance(result, (dict, list)):
        print(json.dumps(result, indent=2))
    else:
        print(str(result))
except Exception as e:
    print(f'Error extracting field {field_path}: {str(e)}', file=sys.stderr)
    sys.exit(1)
"
}

# Show current async response data (formatted)
show_async_response_data() {
    local response_data
    
    if response_data=$(get_last_async_response_data); then
        echo -e "${CYAN}Current Async Response Data:${NC}"
        if echo "$response_data" | $PYTHON_CMD -c "import json, sys; json.load(sys.stdin)" 2>/dev/null; then
            echo "$response_data" | $PYTHON_CMD -c "import json, sys; print(json.dumps(json.load(sys.stdin), indent=2))"
        else
            echo "$response_data"
        fi
        echo ""
        info "Use get_async_response_field 'field.path' to extract specific values"
        return 0
    else
        info "No async response data available"
        return 1
    fi
}

# Clear async response data
clear_async_response_data() {
    unset LAST_ASYNC_RESPONSE_DATA
    unset LAST_ASYNC_RESPONSE_FILE
    rm -f "${SCRIPT_DIR}/.last_async_response"
    info "Cleared async response data"
}

# Get Azure AD token (interactive version)
get_token_interactive() {
    step_header "Step: get_authentication_token"
    
    if ! confirm_step "get_authentication_token" "Get Azure AD authentication token for API access"; then
        return 0  # Step was skipped
    fi
    
    local tenant=$(get_config_value 'azure_tenant_id')
    local app_id=$(get_config_value 'azure_app_id')
    local app_secret=$(get_config_value 'azure_app_secret')
    local auth_url=$(get_config_value 'azure_auth_base_url')
    local api_url=$(get_config_value 'azure_api_base_url')
    local api_version=$(get_config_value 'azure_api_version')
    
    if [[ -z "$tenant" || -z "$app_id" || -z "$app_secret" ]]; then
        error_exit "Missing required authentication parameters in config"
    fi
    
    # Build the token endpoint URL
    local token_url="${auth_url}/${tenant}/oauth2/token?api-version=${api_version}"
    local post_data="grant_type=client_credentials&client_id=${app_id}&client_secret=${app_secret}&resource=${api_url}"
    
    info "Making OAuth2 token request..."
    echo -e "${CYAN}Method: POST${NC}"
    echo -e "${CYAN}URL: $token_url${NC}"
    echo -e "${CYAN}Request Body: grant_type=client_credentials&client_id=${app_id}&client_secret=***HIDDEN***&resource=${api_url}${NC}"
    
    echo ""
    info "Executing token request..."
    
    # Create temporary files for response and headers
    local response_file=$(mktemp)
    local headers_file=$(mktemp)
    
    # Execute the token request
    local http_status
    http_status=$(curl -s -w "%{http_code}" -o "$response_file" -D "$headers_file" \
        -X POST \
        -H "Content-Type: application/x-www-form-urlencoded" \
        --data "$post_data" \
        "$token_url")
    
    # Log the request (without sensitive data)
    log "Token Request: POST $token_url"
    log "HTTP Status: $http_status"
    log "Response Headers: $(cat "$headers_file")"
    
    # Display results
    echo ""
    echo -e "${PURPLE}═══ TOKEN RESPONSE ═══${NC}"
    echo -e "${CYAN}HTTP Status: $http_status${NC}"
    
    # Check if status is successful
    if [[ "$http_status" == "200" ]]; then
        success "Token request completed successfully (HTTP $http_status)"
    else
        warning "Unexpected HTTP status: $http_status (expected: 200)"
    fi
    
    # Show response headers (filtered)
    echo -e "${CYAN}Key Response Headers:${NC}"
    grep -i -E "(content-type|cache-control|expires)" "$headers_file" | head -5 || true
    
    # Process response body
    local response_content=$(cat "$response_file")
    
    if [[ -n "$response_content" ]]; then
        echo -e "${CYAN}Response Body (sanitized):${NC}"
        # Parse and display token info without showing the actual token
        local token_info
        token_info=$(echo "$response_content" | $PYTHON_CMD -c "
import json, sys
try:
    data = json.load(sys.stdin)
    sanitized = {
        'token_type': data.get('token_type', 'Unknown'),
        'expires_in': data.get('expires_in', 'Unknown'),
        'resource': data.get('resource', 'Unknown'),
        'access_token': '***TOKEN_HIDDEN***' if data.get('access_token') else 'NOT_FOUND'
    }
    print(json.dumps(sanitized, indent=2))
except Exception as e:
    print('Error parsing response:', str(e))
    print('Raw response:', sys.stdin.read()[:200] + '...')
")
        echo "$token_info"
    else
        echo -e "${YELLOW}(Empty response body)${NC}"
    fi
    
    echo ""
    echo -e "${PURPLE}═══ END TOKEN RESPONSE ═══${NC}"
    
    # Extract and store token
    local token
    token=$(echo "$response_content" | $PYTHON_CMD -c "
import json, sys
try:
    data = json.load(sys.stdin)
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
    
    log "Token stored securely in $TOKEN_FILE"
    success "Authentication token obtained and stored"
    
    # Clean up temp files
    rm -f "$response_file" "$headers_file"
    
    # Token request completed - no additional prompting needed
    # The next confirm_step() call will handle user interaction
    success "Authentication token obtained"
}

# Get Azure AD token (non-interactive version for use in API calls)
get_token() {
    info "Getting Azure AD authentication token..."
    
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
    token=$($PYTHON_CMD -c "
import json
try:
    data = json.loads('$response')
    print(data.get('access_token', ''))
except:
    pass
")
    
    if [[ -z "$token" ]]; then
        error_exit "Failed to extract access token from response: $response"
    fi
    
    # Store token securely
    echo "$token" > "$TOKEN_FILE"
    chmod 600 "$TOKEN_FILE"
    
    success "Authentication token obtained"
}

# Generate volume creation payload
get_volume_payload() {
    local protocol=$(get_protocol)
    local qos=$(get_qos)
    
    if [[ "$protocol" == "SMB" ]]; then
        if [[ "$qos" == "Manual" ]]; then
            echo '{
    "type": "Microsoft.NetApp/netAppAccounts/capacityPools/volumes",
    "location": "{{target_location}}",
    "zones": {{target_zones}},
    "properties": {
        "volumeType": "Migration",
        "dataProtection": {
            "replication": {
                "endpointType": "Dst",
                "replicationSchedule": "{{replication_schedule}}",
                "remotePath": {
                    "externalHostName": "{{source_hostname}}",
                    "serverName": "{{source_svm_name}}",
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
    "zones": {{target_zones}},
    "properties": {
        "volumeType": "Migration",
        "dataProtection": {
            "replication": {
                "endpointType": "Dst",
                "replicationSchedule": "{{replication_schedule}}",
                "remotePath": {
                    "externalHostName": "{{source_hostname}}",
                    "serverName": "{{source_svm_name}}",
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
   "zones":{{target_zones}},
   "properties":{
      "volumeType":"Migration",
      "dataProtection":{
         "replication":{
            "endpointType":"Dst",
            "replicationSchedule":"{{replication_schedule}}",
            "remotePath":{
               "externalHostName":"{{source_hostname}}",
               "serverName":"{{source_svm_name}}",
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
   "zones":{{target_zones}},
   "properties":{
      "volumeType":"Migration",
      "dataProtection":{
         "replication":{
            "endpointType":"Dst",
            "replicationSchedule":"{{replication_schedule}}",
            "remotePath":{
               "externalHostName":"{{source_hostname}}",
               "serverName":"{{source_svm_name}}",
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

# Check if required tools are available
check_dependencies() {
    info "Checking dependencies..."
    
    command -v curl >/dev/null 2>&1 || error_exit "curl is required but not installed"
    command -v $PYTHON_CMD >/dev/null 2>&1 || error_exit "Python is required but not installed (tried: $PYTHON_CMD)"
    
    # Check if PyYAML is available
    if ! $PYTHON_CMD -c "import yaml" 2>/dev/null; then
        error_exit "PyYAML is required but not installed. Run: pip install PyYAML"
    fi
    
    success "Dependencies check passed"
}

# Validate configuration
validate_config() {
    info "Validating configuration..."
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        error_exit "Configuration file $CONFIG_FILE not found. Please run the setup wizard first (option 1)."
    fi
    
    # Test if we can actually read the config file using the CONFIG_FILE variable
    if ! $PYTHON_CMD -c "import yaml; yaml.safe_load(open('$CONFIG_FILE'))" 2>/dev/null; then
        error_exit "Configuration file exists but cannot be parsed. Please run the setup wizard again (option 1)."
    fi
    
    # Validation passed - show current config
    success "Configuration is valid"
    echo ""
    show_config
}

# Show help
show_help() {
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  Azure NetApp Files Migration Assistant - Interactive Mode${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "This tool provides a menu-driven approach to Azure NetApp Files migration,"
    echo "with step-by-step execution and full visibility into each REST API call."
    echo ""
    echo -e "${BLUE}Usage:${NC} $0 [OPTIONS] [COMMAND]"
    echo ""
    echo -e "${CYAN}Options:${NC}"
    echo "  --config FILE, -c FILE    Use custom config file (default: config.yaml)"
    echo "  --config=FILE             Alternative syntax for custom config file"
    echo ""
    echo -e "${CYAN}Commands:${NC}"
    echo "  menu     - Show interactive menu (default)"
    echo "  setup    - Run setup wizard configuration"
    echo "  peering  - Run peering setup (volume creation through SVM peering)"
    echo "  break    - Run break replication workflow (finalize migration)"
    echo "  monitor  - Monitor replication status for existing migrations"
    echo "  config   - Show current configuration"
    echo "  token    - Get authentication token only"
    echo "  help     - Show this help message"
    echo ""
    echo -e "${YELLOW}Workflow Phases:${NC}"
    echo -e "${PURPLE}Phase 1 - Setup:${NC} Configure parameters and generate config file"
    echo -e "${PURPLE}Phase 2 - Peering:${NC} Create volume, establish cluster/SVM peering, start sync"
    echo -e "${PURPLE}Phase 3 - Finalization:${NC} Break replication and make volume writable"
    echo ""
    echo -e "${CYAN}Features:${NC}"
    echo "  • Menu-driven workflow selection for better organization"
    echo "  • Step-by-step execution with user confirmation"
    echo "  • Full REST API request/response visibility"
    echo "  • Interactive ONTAP command execution guidance"
    echo "  • Multiple monitoring modes: Full, Quick, or Custom"
    echo "  • Natural stopping points between workflow phases"
    echo "  • Detailed logging of all API interactions"
    echo ""
    echo -e "${GREEN}Typical Usage Pattern:${NC}"
    echo "  1. Run 'anf_interactive.sh setup' or choose menu option 1"
    echo "  2. Run 'anf_interactive.sh peering' or choose menu option 2"
    echo "  3. Wait for data sync to complete (monitor in Azure Portal)"
    echo "  4. Run 'anf_interactive.sh break' or choose menu option 3"
    echo ""
    echo -e "${GREEN}Custom Config File Examples:${NC}"
    echo "  ./anf_interactive.sh --config production.yaml peering"
    echo "  ./anf_interactive.sh -c test-config.yaml monitor"
    echo "  ./anf_interactive.sh --config=staging.yaml menu"
    echo ""
}

# Main menu system
show_main_menu() {
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  Azure NetApp Files Migration Assistant - Interactive Mode${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${BLUE}Please select the workflow you want to execute:${NC}"
    echo ""
    echo -e "${CYAN}  1. Run Setup Wizard${NC}"
    echo -e "${YELLOW}     Configure migration parameters and generate config file${NC}"
    echo ""
    echo -e "${CYAN}  2. Run Peering Setup${NC}"
    echo -e "${YELLOW}     Execute volume creation, cluster peering, and SVM peering${NC}"
    echo -e "${YELLOW}     (Stops after data sync begins)${NC}"
    echo ""
    echo -e "${CYAN}  3. Break Replication & Finalize Migration${NC}"
    echo -e "${YELLOW}     Complete the migration by breaking replication and making volume writable${NC}"
    echo -e "${YELLOW}     (Run this after data sync is complete)${NC}"
    echo ""
    echo -e "${CYAN}  4. Monitor Replication Status${NC}"
    echo -e "${YELLOW}     Check transfer progress and speed for existing migrations${NC}"
    echo -e "${YELLOW}     (Select from available replication volumes)${NC}"
    echo ""
    echo -e "${PURPLE}  5. Show Current Configuration${NC}"
    echo -e "${PURPLE}  6. Get Authentication Token Only${NC}"
    echo -e "${PURPLE}  7. Help${NC}"
    echo -e "${PURPLE}  q. Quit${NC}"
    echo ""
}

# Setup wizard workflow
run_setup_wizard() {
    step_header "Setup Wizard"
    info "Launching configuration wizard..."
    
    if [[ -f "${SCRIPT_DIR}/setup_wizard.py" ]]; then
        $PYTHON_CMD "${SCRIPT_DIR}/setup_wizard.py"
        if [[ $? -eq 0 ]]; then
            success "Configuration wizard completed successfully"
            info "Config file updated: $CONFIG_FILE"
            echo ""
            if ask_user_choice "Would you like to review the configuration?" "y"; then
                echo ""
                step_header "Current Configuration"
                show_config
            fi
        else
            warning "Configuration wizard exited without completing"
        fi
    else
        warning "Setup wizard not found at ${SCRIPT_DIR}/setup_wizard.py"
        info "Please run the setup wizard manually or ensure the file exists"
    fi
}

# Peering setup workflow (Steps 1-4: Authentication, Volume Creation, Cluster Peering, SVM Peering)
run_peering_setup() {
    check_dependencies
    validate_config
    
    local protocol=$(get_protocol)
    local qos=$(get_qos)
    
    step_header "Peering Setup Workflow"
    
    info "Starting peering setup workflow for $protocol with $qos QoS"
    echo ""
    echo -e "${BLUE}This workflow will:${NC}"
    echo "  1. Authenticate with Azure"
    echo "  2. Create the target volume"
    echo "  3. Set up cluster peering (with ONTAP command execution)"
    echo "  4. Set up SVM peering (with ONTAP command execution)"
    echo "  5. Begin data synchronization"
    echo ""
    echo -e "${YELLOW}After completion, you'll need to:${NC}"
    echo "  • Monitor sync progress in Azure Portal"
    echo "  • Wait for data synchronization to complete"
    echo "  • Run workflow #3 when ready to finalize migration"
    echo ""
    
    if ! ask_user_choice "Do you want to proceed with the peering setup workflow?" "y"; then
        info "Workflow cancelled by user"
        return 0
    fi
    
    # Ask about interaction level
    echo ""
    echo -e "${CYAN}🔧 Interaction Level Configuration${NC}"
    echo "Choose your preferred level of interaction during this workflow:"
    echo ""
    echo "  [M] Minimal - Only stop for ONTAP commands (faster, experienced users)"
    echo "  [F] Full - Step-by-step prompts for each operation (default)"
    echo ""
    
    local interaction_mode="full"
    while true; do
        read -p "Choose interaction level [M/F]: " -n 1 -r
        echo ""
        case $REPLY in
            [Mm])
                interaction_mode="minimal"
                info "Minimal interaction mode - will only prompt for ONTAP command execution"
                break
                ;;
            [Ff]|"")  # Default to full if just ENTER is pressed
                interaction_mode="full"
                info "Full interaction mode - step-by-step prompts for each operation"
                break
                ;;
            *)
                echo "Please choose M (minimal) or F (full). Press ENTER for full interaction."
                ;;
        esac
    done
    
    # Export the interaction mode for use throughout the workflow
    export ANF_INTERACTION_MODE="$interaction_mode"
    
    # Use full monitoring mode by default
    local monitoring_mode="full"
    info "Using full monitoring mode for all operations"
    
    export ANF_MONITORING_MODE="$monitoring_mode"
    
    # Step 1: Authentication
    get_token_interactive
    
    # Step 2: Create target volume
    local volume_payload=$(get_volume_payload)
    execute_api_call "create_volume" "PUT" \
        "/subscriptions/{{azure_subscription_id}}/resourceGroups/{{target_resource_group}}/providers/Microsoft.NetApp/netAppAccounts/{{target_netapp_account}}/capacityPools/{{target_capacity_pool}}/volumes/{{target_volume_name}}" \
        "$volume_payload" \
        "Create migration target volume ($protocol with $qos QoS)" \
        "200,201,202"
    
    # Step 3: Issue cluster peer request (always prompt - ONTAP commands required)
    if [[ "${ANF_INTERACTION_MODE:-full}" == "minimal" ]]; then
        step_header "Critical Step: Cluster Peering Setup"
        info "This step requires ONTAP command execution - prompting regardless of interaction mode"
        echo ""
    fi
    execute_api_call "peer_request" "POST" \
        "/subscriptions/{{azure_subscription_id}}/resourceGroups/{{target_resource_group}}/providers/Microsoft.NetApp/netAppAccounts/{{target_netapp_account}}/capacityPools/{{target_capacity_pool}}/volumes/{{target_volume_name}}/peerExternalCluster" \
        '{"PeerClusterName":"{{source_cluster_name}}","PeerAddresses":["{{source_peer_addresses}}"]}' \
        "Initiate cluster peering with source ONTAP system (ONTAP commands required)" \
        "200,201,202"
    
    # Step 4: Authorize external replication (always prompt - SVM peering commands required)
    if [[ "${ANF_INTERACTION_MODE:-full}" == "minimal" ]]; then
        step_header "Critical Step: SVM Peering Authorization"
        info "This step requires SVM peering command execution - prompting regardless of interaction mode"
        echo ""
    fi
    execute_api_call "authorize_replication" "POST" \
        "/subscriptions/{{azure_subscription_id}}/resourceGroups/{{target_resource_group}}/providers/Microsoft.NetApp/netAppAccounts/{{target_netapp_account}}/capacityPools/{{target_capacity_pool}}/volumes/{{target_volume_name}}/authorizeExternalReplication" \
        "" \
        "Authorize the external replication relationship (SVM peering commands required)" \
        "200,201,202"
    
    # Check if migration sync was started (SVM peering completed)
    if [[ "${MIGRATION_SYNC_STARTED:-}" == "true" ]]; then
        info "Peering setup completed - data synchronization in progress"
        echo ""
        echo -e "${GREEN}🎉 Peering Setup Completed Successfully!${NC}"
        echo ""
        echo -e "${BLUE}Next Steps:${NC}"
        echo "  1. Monitor sync progress in Azure Portal"
        echo "  2. Wait for data synchronization to complete"
        echo "  3. When ready to cut over, run this script again and select option 3"
        echo ""
        return 0
    fi
    
    warning "Peering setup completed but sync flag not set - this may indicate an issue"
    info "Please check the Azure Portal for volume status and replication progress"
}

# Break replication workflow (Steps 5-7: Replication Transfer, Break Replication, Finalize)
run_break_replication() {
    check_dependencies
    validate_config
    
    step_header "Break Replication & Finalize Migration"
    
    info "This workflow will complete your migration by:"
    echo "  1. Performing final replication transfer"
    echo "  2. Breaking the replication relationship"
    echo "  3. Finalizing the migration (cleanup)"
    echo ""
    echo -e "${RED}⚠️  IMPORTANT WARNING:${NC}"
    echo -e "${YELLOW}Breaking replication will:${NC}"
    echo "  • Stop data synchronization from on-premises"
    echo "  • Make the Azure volume writable"
    echo "  • This action cannot be easily undone"
    echo ""
    echo -e "${CYAN}Before proceeding, ensure:${NC}"
    echo "  • Data synchronization is complete (check Azure Portal metrics)"
    echo "  • You're ready to switch users to the Azure volume"
    echo "  • You have a rollback plan if needed"
    echo ""
    
    if ! ask_user_choice "Are you sure you want to break replication and finalize the migration?" "n"; then
        info "Break replication workflow cancelled by user"
        return 0
    fi
    
    # Phase 3 - Interaction Level Configuration
    step_header "Break Replication & Finalization Workflow"
    echo -e "${BLUE}🔧 Interaction Level Configuration${NC}"
    echo "Choose your preferred level of interaction during this workflow:"
    echo ""
    echo "  [M] Minimal - Auto-continue through most steps (faster, experienced users)"
    echo "  [F] Full - Step-by-step prompts for each operation (default)"
    echo ""
    
    local interaction_choice
    read -p "Choose interaction level [M/F]: " interaction_choice
    
    case "${interaction_choice,,}" in
        m|minimal)
            export ANF_INTERACTION_MODE="minimal"
            info "✅ Using minimal interaction mode - will auto-continue through most steps"
            ;;
        *)
            export ANF_INTERACTION_MODE="full"
            info "✅ Using full interaction mode - step-by-step prompts"
            ;;
    esac
    echo ""

    # Always refresh authentication token for break replication
    # (tokens likely expired since initial setup)
    info "Refreshing authentication token for break replication workflow..."
    get_token
    
    # Use full monitoring mode by default
    local monitoring_mode="full"
    info "Using full monitoring mode for all operations"
    
    export ANF_MONITORING_MODE="$monitoring_mode"
    
    # Step 5: Perform replication transfer (this can take a long time)
    execute_api_call "replication_transfer" "POST" \
        "/subscriptions/{{azure_subscription_id}}/resourceGroups/{{target_resource_group}}/providers/Microsoft.NetApp/netAppAccounts/{{target_netapp_account}}/capacityPools/{{target_capacity_pool}}/volumes/{{target_volume_name}}/performReplicationTransfer" \
        "" \
        "Start the final data replication transfer" \
        "200,201,202"
    
    # Step 6: Break replication relationship
    execute_api_call "break_replication" "POST" \
        "/subscriptions/{{azure_subscription_id}}/resourceGroups/{{target_resource_group}}/providers/Microsoft.NetApp/netAppAccounts/{{target_netapp_account}}/capacityPools/{{target_capacity_pool}}/volumes/{{target_volume_name}}/breakReplication" \
        "" \
        "Break the replication relationship (makes target writable)" \
        "200,201,202"
    
    # Step 7: Finalize external replication
    execute_api_call "finalize_replication" "POST" \
        "/subscriptions/{{azure_subscription_id}}/resourceGroups/{{target_resource_group}}/providers/Microsoft.NetApp/netAppAccounts/{{target_netapp_account}}/capacityPools/{{target_capacity_pool}}/volumes/{{target_volume_name}}/finalizeExternalReplication" \
        "" \
        "Finalize and clean up the external replication configuration" \
        "200,201,202"
    
    step_header "🎉 Migration Completed Successfully!"
    success "All migration steps have been executed"
    echo ""
    echo -e "${GREEN}✅ Your Azure NetApp Files volume is now ready for production use!${NC}"
    echo ""
    echo -e "${BLUE}Post-Migration Steps:${NC}"
    echo "  1. Update DNS records to point to the new Azure volume"
    echo "  2. Update client mount configurations if needed"
    echo "  3. Test application connectivity and functionality"
    echo "  4. Monitor performance and adjust as needed"
    echo ""
    echo -e "${CYAN}Volume Information:${NC}"
    local target_volume_name=$(get_config_value 'target_volume_name')
    local target_resource_group=$(get_config_value 'target_resource_group')
    echo "  • Volume Name: $target_volume_name"
    echo "  • Resource Group: $target_resource_group"
    echo "  • Check Azure Portal for mount targets and connection details"
    echo ""
    info "Detailed logs are available in: $LOG_FILE"
}

# Main menu loop
run_main_menu() {
    while true; do
        show_main_menu
        read -p "Enter your choice [1-7/q]: " -r
        echo ""
        
        case $REPLY in
            1)
                run_setup_wizard
                echo ""
                echo -e "${CYAN}Press ENTER to return to main menu...${NC}"
                read
                ;;
            2)
                run_peering_setup
                echo ""
                echo -e "${CYAN}Press ENTER to return to main menu...${NC}"
                read
                ;;
            3)
                run_break_replication
                echo ""
                echo -e "${CYAN}Press ENTER to return to main menu...${NC}"
                read
                ;;
            4)
                run_replication_monitor_standalone
                echo ""
                echo -e "${CYAN}Press ENTER to return to main menu...${NC}"
                read
                ;;
            5)
                step_header "Current Configuration"
                show_config
                echo ""
                echo -e "${CYAN}Press ENTER to return to main menu...${NC}"
                read
                ;;
            6)
                step_header "Authentication Token"
                get_token
                echo ""
                echo -e "${CYAN}Press ENTER to return to main menu...${NC}"
                read
                ;;
            7|"help"|"--help"|"-h")
                show_help
                echo ""
                echo -e "${CYAN}Press ENTER to return to main menu...${NC}"
                read
                ;;
            [Qq])
                info "Goodbye!"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid choice. Please select 1-7 or q.${NC}"
                echo ""
                echo -e "${CYAN}Press ENTER to continue...${NC}"
                read
                ;;
        esac
    done
}

# Main execution
case "${1:-menu}" in
    "menu"|"")
        run_main_menu
        ;;
    "setup"|"wizard")
        run_setup_wizard
        ;;
    "peering")
        run_peering_setup
        ;;
    "break"|"finalize")
        run_break_replication
        ;;
    "monitor")
        run_replication_monitor_standalone
        ;;
    "run")
        # Legacy support - run peering setup
        run_peering_setup
        ;;
    "config")
        show_config
        ;;
    "token")
        get_token
        ;;
    "help"|"--help"|"-h")
        show_help
        ;;
    *)
        echo "Unknown command: $1"
        echo ""
        echo "Usage: $0 [OPTIONS] [COMMAND]"
        echo ""
        echo "Options:"
        echo "  --config FILE, -c FILE    Use custom config file (default: config.yaml)"
        echo ""
        echo "Available commands:"
        echo "  menu     - Show interactive menu (default)"
        echo "  setup    - Run setup wizard"
        echo "  peering  - Run peering setup workflow"
        echo "  break    - Run break replication workflow"
        echo "  monitor  - Monitor replication status"
        echo "  config   - Show current configuration"
        echo "  token    - Get authentication token"
        echo "  help     - Show help"
        echo ""
        echo "Examples:"
        echo "  $0 --config production.yaml peering"
        echo "  $0 -c test.yaml monitor"
        exit 1
        ;;
esac
