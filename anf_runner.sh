#!/bin/bash
# Azure NetApp Files Migration Assistant Script Runner
# Handles token management and enhanced workflow execution

set -e

# Configuration
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

# Warning message
warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
    log "WARNING: $1"
}

# Info message
info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
    log "INFO: $1"
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

# Extract value from YAML config
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

# Get Azure AD token
get_token() {
    info "Requesting Azure AD token..."
    
    local tenant=$(get_config_value "tenant")
    local app_id=$(get_config_value "appId")
    local app_secret=$(get_config_value "appIdPassword")
    local auth_url=$(get_config_value "authcloudurl")
    local api_url=$(get_config_value "apicloudurl")
    local api_version=$(get_config_value "api-version")
    
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
    
    # Extract token (using jq if available, otherwise python)
    local token
    if command -v jq >/dev/null 2>&1; then
        token=$(echo "$response" | jq -r '.access_token // empty')
    else
        token=$(python3 -c "
import json, sys
try:
    data = json.loads('$response')
    print(data.get('access_token', ''))
except:
    pass
")
    fi
    
    if [[ -z "$token" || "$token" == "null" ]]; then
        error_exit "Failed to extract access token from response: $response"
    fi
    
    # Store token securely
    echo "$token" > "$TOKEN_FILE"
    chmod 600 "$TOKEN_FILE"
    
    success "Token obtained and stored"
    info "Token expires in $(echo "$response" | python3 -c "import json,sys; print(json.loads(input()).get('expires_in', 'unknown'))" 2>/dev/null || echo 'unknown') seconds"
}

# Check if token is valid and not expired
check_token() {
    if [[ ! -f "$TOKEN_FILE" ]]; then
        return 1
    fi
    
    # Simple check - in a production system you'd validate the JWT
    local token=$(cat "$TOKEN_FILE")
    if [[ -z "$token" ]]; then
        return 1
    fi
    
    return 0
}

# Execute a specific workflow script 
run_workflow() {
    local workflow_script="$1"
    
    if [[ "$workflow_script" == "anf_workflow.sh" ]]; then
        # Use the new dynamic workflow
        info "Running dynamic ANF Migration workflow..."
        ./anf_workflow.sh run
    elif [[ -f "$workflow_script" ]]; then
        # Legacy static workflow script
        info "Running workflow: $workflow_script"
        bash "$workflow_script"
    else
        error_exit "Workflow script $workflow_script not found"
    fi
}

# Run the dynamic workflow
generate_and_run() {
    local protocol="${1:-}"
    local qos="${2:-}"
    
    info "Running ANF Migration Assistant workflow..."
    
    # Show what will be executed
    ./anf_workflow.sh config
    echo ""
    
    # Confirm execution
    echo "This will execute the complete migration workflow."
    read -p "Continue? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "Workflow cancelled by user"
        return 0
    fi
    
    # Execute the workflow
    ./anf_workflow.sh run
}

# Show usage
show_usage() {
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  setup                   - Interactive configuration setup"
    echo "  validate                - Validate configuration"
    echo "  token                   - Get new Azure AD token"
    echo "  run [SCRIPT]           - Run a specific workflow script"
    echo "  generate [PROTOCOL] [QOS] - Generate and run workflow"
    echo "  list                    - List available workflow scripts"
    echo ""
    echo "Getting Started:"
    echo "  $0 setup                - First-time configuration wizard"
    echo ""
    echo "Examples:"
    echo "  $0 setup                - Interactive setup wizard"
    echo "  $0 validate"
    echo "  $0 generate NFSv3 Auto"
    echo "  $0 generate SMB Manual"
    echo "  $0 run workflow_nfsv3_auto.sh"
    echo ""
}

# List available workflows
list_workflows() {
    echo "Available workflow options:"
    echo "  🚀 anf_workflow.sh - Dynamic workflow (reads config.yaml at runtime)"
    
    # Show any legacy static workflows if they exist
    if ls workflow_*.sh 2>/dev/null | grep -q .; then
        echo "  📄 Legacy static workflows:"
        ls -1 workflow_*.sh 2>/dev/null | sed 's/^/     /' 
    fi
    
    echo ""
    echo "Supported protocol/QoS combinations:"
    echo "  📁 NFSv3 + Auto QoS"
    echo "  📁 NFSv3 + Manual QoS  "
    echo "  📁 CIFS + Auto QoS"
    echo "  📁 CIFS + Manual QoS"
    
    echo ""
    echo "Current configuration:"
    ./anf_workflow.sh config
}

# Main execution
main() {
    log "Starting ANF Migration Assistant Runner"
    
    case "${1:-help}" in
        "setup")
            info "Starting interactive setup wizard..."
            python3 setup_wizard.py
            ;;
        "validate")
            check_dependencies
            validate_config
            ;;
        "token")
            check_dependencies
            get_token
            ;;
        "run")
            if [[ -z "$2" ]]; then
                error_exit "Please specify a workflow script to run"
            fi
            check_dependencies
            validate_config || error_exit "Configuration validation failed"
            run_workflow "$2"
            ;;
        "generate")
            check_dependencies
            validate_config || error_exit "Configuration validation failed"
            generate_and_run "$2" "$3"
            ;;
        "list")
            list_workflows
            ;;
        "help"|"--help"|"-h"|"")
            show_usage
            ;;
        *)
            error_exit "Unknown command: $1. Use '$0 help' for usage information."
            ;;
    esac
}

# Run main function
main "$@"
