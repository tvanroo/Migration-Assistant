# Variable Name Standardization Mapping

## Naming Convention
- Use **snake_case** for all variables
- Use descriptive, full words (avoid abbreviations)
- Group related variables with consistent prefixes
- Separate secrets from regular variables clearly

## Variable Mapping (Old → New)

### Authentication & Azure Configuration
| Old Name | New Name | Description |
|----------|----------|-------------|
| `tenant` | `azure_tenant_id` | Azure AD tenant ID |
| `subscriptionId` | `azure_subscription_id` | Azure subscription ID |
| `appId` | `azure_app_id` | Service principal application ID |
| `appIdPassword` | `azure_app_secret` | Service principal secret |
| `api-version` | `azure_api_version` | Azure API version |
| `apicloudurl` | `azure_api_base_url` | Azure API base URL |
| `authcloudurl` | `azure_auth_base_url` | Azure authentication base URL |

### Target Azure NetApp Files Configuration
| Old Name | New Name | Description |
|----------|----------|-------------|
| `resourceGroupName` | `target_resource_group` | Target resource group name |
| `location` | `target_location` | Azure region/location |
| `accountName` | `target_netapp_account` | Target NetApp account name |
| `poolName` | `target_capacity_pool` | Target capacity pool name |
| `volumeName` | `target_volume_name` | Target volume name |
| `serviceLevel` | `target_service_level` | Target service level |
| `volsubnetId` | `target_subnet_id` | Target virtual network subnet ID |
| `networkFeatures` | `target_network_features` | Target network features |
| `isLargeVolume` | `target_is_large_volume` | Whether target is large volume |
| `volusageThreshold` | `target_usage_threshold` | Target volume usage threshold |
| `volthroughputMibps` | `target_throughput_mibps` | Target volume throughput (MiB/s) |
| `volumeProtocolTypes` | `target_protocol_types` | Target volume protocol types |

### Source NetApp Configuration (Migration)
| Old Name | New Name | Description |
|----------|----------|-------------|
| `maclusterName` | `source_cluster_name` | Source NetApp cluster name |
| `maexternalHostName` | `source_hostname` | Source NetApp external hostname |
| `mapeerAddresses` | `source_peer_addresses` | Source peer IP addresses |
| `maserverName` | `source_server_name` | Source NetApp server name |
| `mavolumeName` | `source_volume_name` | Source volume name |

### Replication Configuration
| Old Name | New Name | Description |
|----------|----------|-------------|
| `replicationSchedule` | `replication_schedule` | Replication schedule |

## File Updates Required
1. `config.template.yaml` - Update all variable names
2. `anf_workflow.sh` - Update variable references in API calls
3. `anf_interactive.sh` - Update variable references
4. `anf_runner.sh` - Update variable references  
5. `setup_wizard.py` - Update variable names and validation
6. `validate_variables.py` - Update variable references
7. `README.md` - Update documentation examples

## Implementation Steps
1. Create new `config.template.yaml` with standardized names
2. Update all shell scripts with new variable references
3. Update Python scripts with new variable names
4. Update documentation
5. Test all functionality
6. Create migration guide for existing users
