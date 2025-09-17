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
CONFIG_FILE="${SCRIPT_DIR}/config.yaml"
TOKEN_FILE="${SCRIPT_DIR}/.token"
LOG_FILE="${SCRIPT_DIR}/anf_migration_interactive.log"

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

# Enhanced user confirmation with options
confirm_step() {
    local step_name="$1"
    local description="$2"
    
    echo -e "${CYAN}📋 About to execute: $step_name${NC}"
    echo -e "${CYAN}Description: $description${NC}"
    echo ""
    echo "Options:"
    echo "  [c] Continue with this step"
    echo "  [s] Skip this step"
    echo "  [q] Quit the workflow"
    echo "  [r] Review current configuration"
    echo ""
    
    while true; do
        read -p "What would you like to do? [c/s/q/r]: " -n 1 -r
        echo ""
        case $REPLY in
            [Cc])
                return 0  # Continue
                ;;
            [Ss])
                warning "Skipping step: $step_name"
                return 1  # Skip
                ;;
            [Qq])
                info "Workflow terminated by user"
                exit 0
                ;;
            [Rr])
                ./anf_workflow.sh config
                echo ""
                ;;
            *)
                echo "Invalid option. Please choose c, s, q, or r."
                ;;
        esac
    done
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
import sys, yaml, json
with open('$CONFIG_FILE') as f:
    config = yaml.safe_load(f)
    all_vars = {**config.get('variables', {}), **config.get('secrets', {})}
    
data = sys.stdin.read()
for key, value in all_vars.items():
    # Special handling for mapeerAddresses to support multiple IPs
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
        if echo "$response_content" | python3 -c "import json, sys; json.load(sys.stdin)" 2>/dev/null; then
            echo "$response_content" | python3 -c "import json, sys; print(json.dumps(json.load(sys.stdin), indent=2))"
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
    
    # Ask user what to do next
    echo ""
    echo "What would you like to do next?"
    echo "  [c] Continue to next step"
    echo "  [w] Wait here (useful for long operations)"
    echo "  [r] Repeat this API call"
    echo "  [q] Quit workflow"
    
    while true; do
        read -p "Choose an option [c/w/r/q]: " -n 1 -r
        echo ""
        case $REPLY in
            [Cc])
                success "Proceeding to next step"
                return 0
                ;;
            [Ww])
                echo -e "${CYAN}⏸️  Workflow paused. Press ENTER when ready to continue...${NC}"
                read
                return 0
                ;;
            [Rr])
                warning "Repeating API call..."
                execute_api_call "$step_name" "$method" "$endpoint" "$data" "$description" "$expected_status"
                return $?
                ;;
            [Qq])
                info "Workflow terminated by user"
                exit 0
                ;;
            *)
                echo "Invalid option. Please choose c, w, r, or q."
                ;;
        esac
    done
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
            echo "$volume_response" | python3 -c "
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
            echo "$status_response" | python3 -c "
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
                    if cat "$final_response_file" | python3 -c "import json, sys; json.load(sys.stdin)" 2>/dev/null; then
                        cat "$final_response_file" | python3 -c "import json, sys; print(json.dumps(json.load(sys.stdin), indent=2))"
                    else
                        cat "$final_response_file"
                    fi
                    echo ""
                    
                    # Check if this response contains cluster peering information and display it
                    local cluster_command
                    local cluster_passphrase
                    
                    cluster_command=$(cat "$final_response_file" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    if 'properties' in data and 'clusterPeeringCommand' in data['properties']:
        print(data['properties']['clusterPeeringCommand'])
except:
    pass
" 2>/dev/null)
                    
                    cluster_passphrase=$(cat "$final_response_file" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    if 'properties' in data and 'passphrase' in data['properties']:
        print(data['properties']['passphrase'])
except:
    pass
" 2>/dev/null)
                    
                    if [[ -n "$cluster_command" && -n "$cluster_passphrase" ]]; then
                        echo ""
                        echo -e "${GREEN}🎉 Cluster Peering Information Extracted:${NC}"
                        echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
                        echo -e "${CYAN}║ EXECUTE THIS COMMAND ON YOUR ON-PREMISES ONTAP SYSTEM:                      ║${NC}"
                        echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
                        echo ""
                        echo -e "${YELLOW}$cluster_command${NC}"
                        echo ""
                        echo -e "${GREEN}📋 Passphrase:${NC} ${YELLOW}$cluster_passphrase${NC}"
                        echo ""
                        echo -e "${BLUE}📝 Instructions:${NC}"
                        echo "  1. Log into your on-premises ONTAP system as an administrator"
                        echo "  2. Replace <IP-SPACE-NAME> with your IP space (usually 'Default')"
                        echo "  3. Execute the modified command"
                        echo "  4. When prompted, enter the passphrase above"
                        echo "  5. Verify the command completes successfully"
                        echo ""
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
    
    echo "$response_data" | python3 -c "
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
        if echo "$response_data" | python3 -c "import json, sys; json.load(sys.stdin)" 2>/dev/null; then
            echo "$response_data" | python3 -c "import json, sys; print(json.dumps(json.load(sys.stdin), indent=2))"
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
        token_info=$(echo "$response_content" | python3 -c "
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
    token=$(echo "$response_content" | python3 -c "
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
    
    # Ask user what to do next (same as other API calls)
    echo ""
    echo "What would you like to do next?"
    echo "  [c] Continue to next step"
    echo "  [w] Wait here"
    echo "  [r] Repeat this token request"
    echo "  [q] Quit workflow"
    
    while true; do
        read -p "Choose an option [c/w/r/q]: " -n 1 -r
        echo ""
        case $REPLY in
            [Cc])
                success "Proceeding to next step"
                return 0
                ;;
            [Ww])
                echo -e "${CYAN}⏸️  Workflow paused. Press ENTER when ready to continue...${NC}"
                read
                return 0
                ;;
            [Rr])
                warning "Repeating token request..."
                get_token_interactive
                return $?
                ;;
            [Qq])
                info "Workflow terminated by user"
                exit 0
                ;;
            *)
                echo "Invalid option. Please choose c, w, r, or q."
                ;;
        esac
    done
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
    token=$(python3 -c "
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

# Main interactive workflow
run_interactive_workflow() {
    local protocol=$(get_protocol)
    local qos=$(get_qos)
    
    step_header "Azure NetApp Files Migration Assistant - Interactive Mode"
    
    info "Starting interactive migration workflow for $protocol with $qos QoS"
    info "Current configuration:"
    ./anf_workflow.sh config
    
    echo ""
    if ! ask_user_choice "Do you want to proceed with the interactive migration workflow?" "y"; then
        info "Workflow cancelled by user"
        exit 0
    fi
    
    # Ask about monitoring preferences
    echo ""
    echo -e "${BLUE}📊 Monitoring Options:${NC}"
    echo "  [f] Full monitoring - Check status for all operations (recommended)"
    echo "  [q] Quick mode - Skip most monitoring prompts for faster execution"
    echo "  [c] Custom - Ask for each operation individually"
    
    local monitoring_mode="custom"
    while true; do
        read -p "Choose monitoring mode [f/q/c]: " -n 1 -r
        echo ""
        case $REPLY in
            [Ff])
                monitoring_mode="full"
                info "Using full monitoring mode"
                break
                ;;
            [Qq])
                monitoring_mode="quick"
                info "Using quick mode - minimal monitoring"
                break
                ;;
            [Cc])
                monitoring_mode="custom"
                info "Using custom mode - will ask for each operation"
                break
                ;;
            *)
                echo "Please choose f, q, or c"
                ;;
        esac
    done
    
    export ANF_MONITORING_MODE="$monitoring_mode"
}

# Function to display cluster peer request result (re-display information from previous step)
get_cluster_peer_result() {
    step_header "Step: get_cluster_peer_result"
    
    if ! confirm_step "get_cluster_peer_result" "Display cluster peering command and passphrase"; then
        return 0  # Step was skipped
    fi
    
    info "Displaying cluster peer information from previous step..."
    
    # Check for persistent async response file
    local persistent_file="${SCRIPT_DIR}/.last_async_response"
    if [[ -f "$persistent_file" ]]; then
        info "Loading async response data from persistent file..."
        export LAST_ASYNC_RESPONSE_DATA=$(cat "$persistent_file")
    fi
    
    # Check if we have the async response data from the peer_request step
    if [[ -n "$LAST_ASYNC_RESPONSE_DATA" ]]; then
        info "Found async response data - checking for cluster peer information..."
        if [[ "${DEBUG:-}" == "1" ]]; then
            info "DEBUG: Async response data: ${LAST_ASYNC_RESPONSE_DATA:0:200}..." # Show first 200 chars
        fi
        
        # Check if this async response already contains the cluster peer information
        local peer_command_from_async
        local passphrase_from_async
        local python_error
        
        # Try to extract peer command with better error handling
        python_error=$(echo "$LAST_ASYNC_RESPONSE_DATA" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    if 'properties' in data and 'clusterPeeringCommand' in data['properties']:
        print(data['properties']['clusterPeeringCommand'])
    else:
        print('NOTFOUND', file=sys.stderr)
        sys.exit(1)
except Exception as e:
    print(f'ERROR: {e}', file=sys.stderr)
    sys.exit(1)
" 2>&1)
        
        if [[ $? -eq 0 ]]; then
            peer_command_from_async="$python_error"
            info "Successfully extracted peer command"
        else
            if [[ "${DEBUG:-}" == "1" ]]; then
                info "DEBUG: Failed to extract peer command: $python_error"
            fi
        fi
        
        # Try to extract passphrase with better error handling
        python_error=$(echo "$LAST_ASYNC_RESPONSE_DATA" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    if 'properties' in data and 'passphrase' in data['properties']:
        print(data['properties']['passphrase'])
    else:
        print('NOTFOUND', file=sys.stderr)
        sys.exit(1)
except Exception as e:
    print(f'ERROR: {e}', file=sys.stderr)
    sys.exit(1)
" 2>&1)
        
        if [[ $? -eq 0 ]]; then
            passphrase_from_async="$python_error"
            info "Successfully extracted passphrase"
        else
            if [[ "${DEBUG:-}" == "1" ]]; then
                info "DEBUG: Failed to extract passphrase: $python_error"
            fi
        fi
        
        if [[ -n "$peer_command_from_async" && -n "$passphrase_from_async" ]]; then
            info "Cluster peer command already available in async response - using cached data"
            # Set the variables for use in the display section
            peer_command="$peer_command_from_async"
            passphrase="$passphrase_from_async"
            if [[ "${DEBUG:-}" == "1" ]]; then
                info "DEBUG: Set peer_command and passphrase variables"
            fi
        else
            warning "Cluster peer command not found in cached async response"
            if [[ "${DEBUG:-}" == "1" ]]; then
                info "DEBUG: peer_command_from_async: '${peer_command_from_async:-EMPTY}'"
                info "DEBUG: passphrase_from_async: '${passphrase_from_async:-EMPTY}'"
            fi
            info "This may happen if the async operation hasn't completed yet or returned different data"
            info "You can:"
            echo "  1. Check the Azure portal for the operation status"
            echo "  2. Wait for the operation to complete and try again"
            echo "  3. Skip this step and proceed manually"
        fi
    else
        warning "No async response data available from peer_request step"
        if [[ "${DEBUG:-}" == "1" ]]; then
            info "DEBUG: LAST_ASYNC_RESPONSE_DATA is empty or not set"
        fi
        
        # Check if persistent file exists but is empty
        if [[ -f "$persistent_file" ]]; then
            local file_size=$(wc -c < "$persistent_file" 2>/dev/null || echo "0")
            warning "Persistent file exists but is empty or couldn't be read (size: $file_size bytes)"
        else
            warning "No persistent async response file found at: $persistent_file"
        fi
        
        info "This could happen if:"
        echo "  - The peer_request step was skipped"
        echo "  - Async monitoring was disabled"
        echo "  - The operation completed too quickly"
        echo "  - The previous step failed or didn't complete"
        echo ""
        echo "To resolve this issue:"
        echo "  1. Go back and ensure the peer_request step completed successfully"
        echo "  2. Make sure async monitoring was enabled"
        echo "  3. Check the Azure portal for the operation status"
        echo ""
        
        # Don't proceed with empty data
        warning "Cannot extract cluster peer command without async response data"
        info "Skipping cluster peer command extraction"
        return 1
    fi
    
    if [[ "${DEBUG:-}" == "1" ]]; then
        info "DEBUG: Reached end of data extraction section - continuing to display section"
    fi
    
    # Display the cluster peering command and passphrase if available
    echo ""
    if [[ -n "$peer_command" && -n "$passphrase" ]]; then
            echo ""
            echo -e "${GREEN}✅ Cluster Peer Command Retrieved:${NC}"
            echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
            echo -e "${CYAN}║ EXECUTE THIS COMMAND ON YOUR ON-PREMISES ONTAP SYSTEM:                      ║${NC}"
            echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
            echo ""
            
            # Display the command with placeholders intact
            echo -e "${YELLOW}$peer_command${NC}"
            echo ""
            echo -e "${GREEN}📋 Passphrase:${NC}"
            echo -e "${YELLOW}$passphrase${NC}"
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
            echo "  4. When prompted, enter the passphrase: $passphrase"
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
                    echo -e "${YELLOW}$peer_command${NC}"
                    echo -e "${YELLOW}Passphrase: $passphrase${NC}"
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
        else
            warning "Cluster peer command or passphrase not found in operation result"
            if [[ -n "$peer_command" ]]; then
                echo "Found command: $peer_command"
            fi
            if [[ -n "$passphrase" ]]; then
                echo "Found passphrase: $passphrase"
            fi
            info "Please check the Azure portal for the peering command and passphrase"
        fi
}

# Function to get async operation result and extract SVM peering command
get_async_operation_result() {
    step_header "Step: get_async_operation_result"
    
    if ! confirm_step "get_async_operation_result" "Get async operation result to retrieve SVM peering command"; then
        return 0  # Step was skipped
    fi
    
    info "Getting async operation result from authorize_replication step..."
    
    # Check if we have the async response data from the authorize_replication step
    local svm_command
    if [[ -n "$LAST_ASYNC_RESPONSE_DATA" ]]; then
        # Check if this async response already contains the SVM peer information
        svm_command=$(echo "$LAST_ASYNC_RESPONSE_DATA" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    if 'properties' in data and 'svmPeeringCommand' in data['properties']:
        print(data['properties']['svmPeeringCommand'])
    else:
        sys.exit(1)
except:
    sys.exit(1)
" 2>/dev/null)
        
        if [[ -n "$svm_command" ]]; then
            info "SVM peering command already available in async response - using cached data"
        else
            warning "SVM peering command not found in cached async response"
            info "This may happen if the async operation hasn't completed yet or returned different data"
            info "You can:"
            echo "  1. Check the Azure portal for the operation status"
            echo "  2. Wait for the operation to complete and try again"
            echo "  3. Skip this step and proceed manually"
        fi
    else
        warning "No async response data available from authorize_replication step"
        info "This could happen if:"
        echo "  - The authorize_replication step was skipped"
        echo "  - Async monitoring was disabled"
        echo "  - The operation completed too quickly"
    fi
    
    # Display the SVM peering command if available
    echo ""
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
            echo -e "${CYAN}  on-prem-svm-name: $source_svm_name${NC}"
            echo -e "${CYAN}  destination-svm-name: $target_svm_name${NC}"
            echo ""
            echo -e "${CYAN}📝 Instructions:${NC}"
            echo "  1. Log into your on-premises ONTAP system as an administrator"
            echo "  2. Replace the placeholders in the command with your actual values:"
            echo "     - Replace placeholders with the SVM names shown above"
            echo "  3. Execute the modified command"
            echo "  4. Verify the command completes successfully"
            echo "  5. Return here and confirm completion"
            echo ""
            
            # Wait for user confirmation
            while true; do
                if ask_user_choice "Have you successfully executed the SVM peering command on your ONTAP system?" "n"; then
                    success "SVM peering command execution confirmed"
                    break
                else
                    echo ""
                    echo -e "${YELLOW}Please execute this command on your ONTAP system:${NC}"
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
        else
            warning "SVM peering command not found in operation result"
            info "Please check the Azure portal for the peering command or operation status"
        fi
}

# Check if required tools are available
check_dependencies() {
    info "Checking dependencies..."
    
    command -v curl >/dev/null 2>&1 || error_exit "curl is required but not installed"
    command -v python3 >/dev/null 2>&1 || error_exit "python3 is required but not installed"
    command -v jq >/dev/null 2>&1 || warning "jq not found - JSON parsing will be limited"
    
    success "Dependencies check passed"
}

# Validate configuration
validate_config() {
    info "Validating configuration..."
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        error_exit "Configuration file $CONFIG_FILE not found"
    fi
    
    # Validation passed - show current config
    success "Configuration is valid"
    echo ""
    ./anf_workflow.sh config
}

# Main interactive workflow
run_interactive_workflow() {
    check_dependencies
    validate_config
    
    local protocol=$(get_protocol)
    local qos=$(get_qos)
    
    step_header "Azure NetApp Files Migration Assistant - Interactive Mode"
    
    info "Starting interactive migration workflow for $protocol with $qos QoS"
    info "Current configuration:"
    ./anf_workflow.sh config
    
    echo ""
    if ! ask_user_choice "Do you want to proceed with the interactive migration workflow?" "y"; then
        info "Workflow cancelled by user"
        exit 0
    fi
    
    # Ask about monitoring preferences
    echo ""
    echo -e "${BLUE}📊 Monitoring Options:${NC}"
    echo "  [f] Full monitoring - Check status for all operations (recommended)"
    echo "  [q] Quick mode - Skip most monitoring prompts for faster execution"
    echo "  [c] Custom - Ask for each operation individually"
    
    while true; do
        read -p "Choose monitoring mode [f/q/c]: " -n 1 -r
        echo ""
        case $REPLY in
            [Ff])
                monitoring_mode="full"
                info "Using full monitoring mode"
                break
                ;;
            [Qq])
                monitoring_mode="quick"
                info "Using quick mode - minimal monitoring"
                break
                ;;
            [Cc])
                monitoring_mode="custom"
                info "Using custom mode - will ask for each operation"
                break
                ;;
            *)
                echo "Please choose f, q, or c"
                ;;
        esac
    done
    
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
    
    # Step 3: Issue cluster peer request
    execute_api_call "peer_request" "POST" \
        "/subscriptions/{{azure_subscription_id}}/resourceGroups/{{target_resource_group}}/providers/Microsoft.NetApp/netAppAccounts/{{target_netapp_account}}/capacityPools/{{target_capacity_pool}}/volumes/{{target_volume_name}}/peerExternalCluster" \
        '{"PeerClusterName":"{{source_cluster_name}}","PeerAddresses":["{{source_peer_addresses}}"]}' \
        "Initiate cluster peering with source ONTAP system" \
        "200,201,202"
    
    # Step 3b: Get cluster peer result to retrieve cluster peering command and passphrase
    get_cluster_peer_result
    
    # Step 4: Authorize external replication
    execute_api_call "authorize_replication" "POST" \
        "/subscriptions/{{azure_subscription_id}}/resourceGroups/{{target_resource_group}}/providers/Microsoft.NetApp/netAppAccounts/{{target_netapp_account}}/capacityPools/{{target_capacity_pool}}/volumes/{{target_volume_name}}/authorizeExternalReplication" \
        "" \
        "Authorize the external replication relationship" \
        "200,201,202"
    
    # Step 4b: Get async operation result to retrieve SVM peering command
    get_async_operation_result
    
    # Step 5: Perform replication transfer (this can take a long time)
    execute_api_call "replication_transfer" "POST" \
        "/subscriptions/{{azure_subscription_id}}/resourceGroups/{{target_resource_group}}/providers/Microsoft.NetApp/netAppAccounts/{{target_netapp_account}}/capacityPools/{{target_capacity_pool}}/volumes/{{target_volume_name}}/performReplicationTransfer" \
        "" \
        "Start the initial data replication (THIS CAN TAKE HOURS)" \
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
    
    step_header "🎉 Migration Workflow Completed!"
    success "All migration steps have been executed"
    info "Check your Azure NetApp Files volume to verify the migration completed successfully"
    info "Detailed logs are available in: $LOG_FILE"
}

# Show help
show_help() {
    echo "Azure NetApp Files Migration Assistant - Interactive Mode"
    echo ""
    echo "This tool allows you to execute the migration workflow step-by-step,"
    echo "with full visibility into each REST API call and its response."
    echo ""
    echo "Usage: $0 [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  run     - Start the interactive migration workflow (default)"
    echo "  config  - Show current configuration"
    echo "  token   - Get authentication token only"
    echo "  help    - Show this help message"
    echo ""
    echo "Features:"
    echo "  • Step-by-step execution with user confirmation"
    echo "  • Full REST API request/response visibility"
    echo "  • Smart volume status checking (replaces problematic async monitoring)"
    echo "  • Multiple monitoring modes: Full, Quick, or Custom"
    echo "  • Option to pause, skip, or repeat steps"
    echo "  • Detailed logging of all API interactions"
    echo ""
}

# Main execution
case "${1:-run}" in
    "run")
        run_interactive_workflow
        ;;
    "config")
        ./anf_workflow.sh config
        ;;
    "token")
        get_token
        ;;
    "help"|"--help"|"-h")
        show_help
        ;;
    *)
        echo "Unknown command: $1"
        show_help
        exit 1
        ;;
esac
