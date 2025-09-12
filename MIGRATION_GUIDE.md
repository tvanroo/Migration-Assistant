# Migration Guide: Variable Name Standardization

## Overview
The Azure NetApp Files Migration Assistant has been updated with standardized variable names for better consistency and clarity. All variable names now use `snake_case` format with descriptive prefixes.

## What Changed
All variable names have been updated to follow a consistent naming convention:
- **snake_case** format (e.g., `azure_tenant_id` instead of `tenant`)
- **Descriptive prefixes** (e.g., `target_` for destination, `source_` for migration source)
- **Full words** instead of abbreviations (e.g., `azure_app_id` instead of `appId`)

## For Existing Users

### If You Have an Existing `config.yaml`
Your existing configuration file will need to be updated with the new variable names. You have two options:

#### Option 1: Use the Setup Wizard (Recommended)
1. Backup your current config: `cp config.yaml config.yaml.backup`
2. Run the setup wizard: `./anf_runner.sh setup`
3. The wizard will walk you through all the new variable names

#### Option 2: Manual Migration
Use this mapping to update your `config.yaml` manually:

```yaml
# OLD → NEW Variable Names

# Authentication & Azure Configuration
tenant → azure_tenant_id
subscriptionId → azure_subscription_id
appId → azure_app_id
appIdPassword → azure_app_secret
api-version → azure_api_version
apicloudurl → azure_api_base_url
authcloudurl → azure_auth_base_url

# Target Azure NetApp Files Configuration
resourceGroupName → target_resource_group
location → target_location
accountName → target_netapp_account
poolName → target_capacity_pool
volumeName → target_volume_name
serviceLevel → target_service_level
volsubnetId → target_subnet_id
networkFeatures → target_network_features
isLargeVolume → target_is_large_volume
volusageThreshold → target_usage_threshold
volthroughputMibps → target_throughput_mibps
volumeProtocolTypes → target_protocol_types

# Source NetApp Configuration
maclusterName → source_cluster_name
maexternalHostName → source_hostname
mapeerAddresses → source_peer_addresses
maserverName → source_server_name
mavolumeName → source_volume_name

# Replication Configuration
replicationSchedule → replication_schedule
```

### New Config File Structure
The new `config.yaml` structure separates secrets from regular variables:

```yaml
# Sensitive authentication data
secrets:
  azure_app_secret: "your-app-secret"

# Configuration variables  
variables:
  # Azure Authentication & API Configuration
  azure_tenant_id: "your-tenant-id"
  azure_subscription_id: "your-subscription-id"
  azure_app_id: "your-app-id"
  # ... etc
```

## Benefits of the New Naming Convention
1. **Consistency**: All variables use snake_case format
2. **Clarity**: Descriptive names make purpose obvious
3. **Organization**: Related variables grouped with prefixes
4. **Maintainability**: Easier to understand and modify

## Verification
After updating your configuration:
1. Validate: `./anf_runner.sh validate`
2. Test setup: `./anf_runner.sh setup` (to verify wizard works)

## Need Help?
- Check the updated `config.template.yaml` for the complete new structure
- Run `./anf_runner.sh validate` to see current configuration status
- Refer to the updated README.md for examples with new variable names
