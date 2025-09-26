# Show configuration summary with all variables
show_config() {
    local protocol=$(get_protocol)
    local qos=$(get_qos)
    
    echo "📋 Current Configuration:"
    echo "📄 Config File: $CONFIG_FILE"
    
    # Display main configuration values with icons
    echo "🌐 Azure Region: $(get_config_value 'target_location')"
    echo "📁 Resource Group: $(get_config_value 'target_resource_group')" 
    echo "🗄️  NetApp Account: $(get_config_value 'target_netapp_account')"
    echo "📊 Capacity Pool: $(get_config_value 'target_capacity_pool')"
    echo "💾 Volume: $(get_config_value 'target_volume_name')"
    echo "🔌 Protocol: $protocol"
    echo "⚡ QoS: $qos"
    echo "🔄 Replication: $(get_config_value 'replication_schedule')"
    
    # Display source configuration
    echo ""
    echo "📋 Source Configuration:"
    echo "🖥️  Source Cluster: $(get_config_value 'source_cluster_name')"
    echo "🌐 Source Hostname: $(get_config_value 'source_hostname')"
    echo "📁 Source SVM: $(get_config_value 'source_svm_name')"
    echo "💾 Source Volume: $(get_config_value 'source_volume_name')"
    
    # Format peer addresses
    local peer_addresses=$(get_config_value 'source_peer_addresses')
    if [[ "$peer_addresses" == *"["* ]]; then
        # Try to parse JSON array and make it more readable
        echo -n "🔌 Peer Addresses: "
        $PYTHON_CMD -c "
import json
try:
    addresses = json.loads('$peer_addresses')
    print(', '.join(addresses))
except Exception:
    print('$peer_addresses')
"
    else
        echo "🔌 Peer Addresses: $peer_addresses"
    fi
    
    # Display target volume details
    echo ""
    echo "📋 Target Volume Details:"
    
    # Convert usage threshold to GiB
    local usage_threshold=$(get_config_value 'target_usage_threshold')
    if [[ -n "$usage_threshold" && "$usage_threshold" != "" ]]; then
        # Convert bytes to GiB
        local size_gib=$((usage_threshold / 1024 / 1024 / 1024))
        echo "📏 Volume Size: $size_gib GiB"
    else
        echo "📏 Volume Size: <not set>"
    fi
    
    echo "🏷️  Service Level: $(get_config_value 'target_service_level')"
    
    # Format zones
    local zones=$(get_config_value 'target_zones')
    if [[ "$zones" == *"["* ]]; then
        # Try to parse JSON array and make it more readable
        echo -n "🔳 Availability Zones: "
        $PYTHON_CMD -c "
import json
try:
    zones = json.loads('$zones')
    if zones:
        print(', '.join(zones))
    else:
        print('<none>')
except Exception:
    print('$zones')
"
    else
        echo "🔳 Availability Zones: $zones"
    fi
    
    echo "🔄 Large Volume: $(get_config_value 'target_is_large_volume')"
    
    # Display subnet ID in a more readable format
    local subnet=$(get_config_value 'target_subnet_id')
    if [[ -n "$subnet" && "$subnet" != "" ]]; then
        echo "🌐 Subnet: $subnet"
    fi
    
    # Display Azure configuration details
    echo ""
    echo "📋 Azure Configuration:"
    echo "🔑 Tenant ID: $(get_config_value 'azure_tenant_id')"
    echo "📑 Subscription ID: $(get_config_value 'azure_subscription_id')"
    echo "🔌 App ID: $(get_config_value 'azure_app_id')"
    echo "🔒 App Secret: <hidden>"
    echo "🌍 API Version: $(get_config_value 'azure_api_version')"
    
    # Display manual QoS if set
    local throughput=$(get_config_value 'target_throughput_mibps')
    if [[ -n "$throughput" && "$throughput" != "" ]]; then
        echo "🚀 Manual Throughput: $throughput MiB/s"
    fi
}