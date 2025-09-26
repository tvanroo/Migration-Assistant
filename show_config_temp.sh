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