#!/bin/bash
# Azure NetApp Files Migration Assistant - Interactive Step-by-Step Mode
# Execute each REST API call individually with result inspection

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
        http_status=$(curl -s -w "%{http_code}" -o "$response_file" -D "$headers_file" \
            -X "$method" \
            -H "Authorization: Bearer $token" \
            "$full_url")
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
                if ask_user_choice "Do you want to monitor this operation?" "y"; then
                    should_monitor="true"
                fi
                ;;
        esac
        
        if [[ "$should_monitor" == "true" ]]; then
            monitor_async_operation "$async_url"
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

# Monitor async operation status
monitor_async_operation() {
    local async_url="$1"
    local max_attempts=120  # 2 hours with 1-minute intervals
    local attempt=1
    
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
        
        local status_response=$(curl -s -H "Authorization: Bearer $token" "$async_url")
        
        if [[ $? -ne 0 ]]; then
            warning "Failed to check status (attempt $attempt)"
        else
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
                    return 0
                    ;;
                1)
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
    
    warning "Monitoring timeout reached (2 hours). Operation may still be running."
    info "You can manually check status with: curl -H \"Authorization: Bearer \$(cat .token)\" \"$async_url\""
}

# Helper function for yes/no questions
ask_user_choice() {
    local question="$1"
    local default="${2:-n}"
    
    if [[ "$default" == "y" ]]; then
        prompt="$question (Y/n): "
    else
        prompt="$question (y/N): "
    fi
    
    while true; do
        read -p "$prompt" -r
        if [[ -z "$REPLY" ]]; then
            REPLY="$default"
        fi
        case $REPLY in
            [Yy]|[Yy][Ee][Ss])
                return 0
                ;;
            [Nn]|[Nn][Oo])
                return 1
                ;;
            *)
                echo "Please answer yes (y) or no (n)."
                ;;
        esac
    done
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
                "replication_schedule": "{{replication_schedule}}",
                "remotePath": {
                    "externalHostName": "{{source_hostname}}",
                    "serverName": "{{source_server_name}}",
                    "volumeName": "{{source_volume_name}}"
                }
            }
        },
        'target_service_level': "{{target_service_level}}",
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
        'target_network_features': "Standard",
        'target_is_large_volume': "{{target_is_large_volume}}"
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
                "replication_schedule": "{{replication_schedule}}",
                "remotePath": {
                    "externalHostName": "{{source_hostname}}",
                    "serverName": "{{source_server_name}}",
                    "volumeName": "{{source_volume_name}}"
                }
            }
        },
        'target_service_level': "{{target_service_level}}",
        "creationToken": "{{target_volume_name}}",
        "usageThreshold": "{{target_usage_threshold}}",
        "exportPolicy": {
            "rules": []
        },
        "protocolTypes": [
            "CIFS"
        ],
        "subnetId": "{{target_subnet_id}}",
        'target_network_features': "Standard",
        'target_is_large_volume': "{{target_is_large_volume}}"
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
            "replication_schedule":"{{replication_schedule}}",
            "remotePath":{
               "externalHostName":"{{source_hostname}}",
               "serverName":"{{source_server_name}}",
               "volumeName":"{{source_volume_name}}"
            }
         }
      },
      'target_service_level':"{{target_service_level}}",
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
      'target_network_features':"Standard",
      'target_is_large_volume':"{{target_is_large_volume}}"
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
            "replication_schedule":"{{replication_schedule}}",
            "remotePath":{
               "externalHostName":"{{source_hostname}}",
               "serverName":"{{source_server_name}}",
               "volumeName":"{{source_volume_name}}"
            }
         }
      },
      'target_service_level':"{{target_service_level}}",
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
      'target_network_features':"Standard",
      'target_is_large_volume':"{{target_is_large_volume}}"
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
    
    # Step 4: Authorize external replication
    execute_api_call "authorize_replication" "POST" \
        "/subscriptions/{{azure_subscription_id}}/resourceGroups/{{target_resource_group}}/providers/Microsoft.NetApp/netAppAccounts/{{target_netapp_account}}/capacityPools/{{target_capacity_pool}}/volumes/{{target_volume_name}}/authorizeExternalReplication" \
        "" \
        "Authorize the external replication relationship" \
        "200,201,202"
    
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
