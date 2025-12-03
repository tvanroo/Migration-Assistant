# Azure NetApp Files Migration Assistant

A Windows-native PowerShell tool for managing Azure NetApp Files migration workflows with interactive configuration, automated peering setup, and comprehensive monitoring capabilities.

## 📋 Requirements

### System Requirements

- **Windows 10/11** with PowerShell 5.1 or PowerShell Core 7+
- **Azure Service Principal** - Required for Azure authentication (see setup below)
- **Internet Access** - For Azure API calls
- **Network Connectivity** - Between on-premises ONTAP and Azure

### Azure Service Principal Setup

Before running the migration, you need to create an Azure Service Principal with appropriate permissions:

1. **Open Azure Cloud Shell** in your target subscription
2. **Create the Service Principal**:

   ```bash
   az ad sp create-for-rbac --name ANFMigrate
   ```

3. **Save the Output**:
   - **App ID** (appId) - Use for `azure_app_id` in your configuration
   - **Password** (password) - Use for `azure_app_secret` in your configuration
   - **Tenant ID** (tenant) - Use for `azure_tenant_id` in your configuration

> **Note**: The service principal will have Contributor role by default, which is sufficient for Azure NetApp Files operations.

## 🚀 Quick Start

### 1. Run the Interactive Script

```powershell
# Start the migration assistant
.\anf_interactive.ps1

# Or use specific commands
.\anf_interactive.ps1 setup      # Configure migration parameters
.\anf_interactive.ps1 peering    # Execute peering and start sync
.\anf_interactive.ps1 break      # Finalize migration
.\anf_interactive.ps1 monitor    # Monitor replication status
```

### 2. Configuration

The script uses `config.json` for all settings. On first run, you'll be guided through the setup wizard to create this file.

Alternatively, copy `config.template.json` to `config.json` and edit it manually.

## ✅ Features

### Complete Migration Workflow

- ✅ **Phase 1: Setup** - Interactive configuration wizard with validation
- ✅ **Phase 2: Peering** - Automated volume creation, cluster peering, and data sync
- ✅ **Phase 3: Break Replication** - Final data transfer and migration finalization
- ✅ **Standalone Monitoring** - Real-time replication progress tracking

### Key Capabilities

- **Windows-Native**: Pure PowerShell implementation, no external dependencies
- **Interactive Menus**: Easy-to-use menu system for all operations
- **Automated Workflows**: End-to-end automation with safety confirmations
- **Comprehensive Logging**: Detailed logs of all API calls and operations
- **Token Caching**: Automatic OAuth token management and refresh
- **Error Handling**: Clear error messages with actionable guidance

## 📖 Usage Guide

### Interactive Menu

```powershell
.\anf_interactive.ps1
```

**Menu Options:**
1. Show / Edit current configuration
2. Get authentication token
3. Peering workflow (Phase 2)
4. Break replication & finalize (Phase 3)
5. Monitor replication status
6. Diagnose config (basic JSON sanity check)
7. Help / usage
0. Exit

### Direct Commands

```powershell
# Configuration setup
.\anf_interactive.ps1 setup

# View current configuration
.\anf_interactive.ps1 config

# Execute peering workflow (create volume, setup peering, start sync)
.\anf_interactive.ps1 peering

# Monitor replication progress
.\anf_interactive.ps1 monitor

# Finalize migration (break replication, make volume writable)
.\anf_interactive.ps1 break

# Test authentication
.\anf_interactive.ps1 token

# Show help
.\anf_interactive.ps1 help
```

### Custom Configuration Files

Use different configuration files for multiple environments:

```powershell
# Production environment
.\anf_interactive.ps1 peering config-production.json

# Test environment
.\anf_interactive.ps1 monitor config-test.json

# Development environment
.\anf_interactive.ps1 setup config-dev.json
```

## 🔧 Configuration

The `config.json` file contains two main sections:

### Secrets Section
```json
{
  "secrets": {
    "azure_app_secret": "your-service-principal-password"
  }
}
```

### Variables Section
```json
{
  "variables": {
    "azure_tenant_id": "your-tenant-id",
    "azure_subscription_id": "your-subscription-id",
    "azure_app_id": "your-app-id",
    "target_resource_group": "your-rg-name",
    "target_netapp_account": "your-anf-account",
    "target_capacity_pool": "your-pool-name",
    "target_volume_name": "new-volume-name",
    "source_cluster_name": "ontap-cluster",
    "source_svm_name": "svm-name",
    "source_volume_name": "source-volume"
  }
}
```

See `config.template.json` for a complete configuration example.

## 📋 Migration Workflow

### Phase 1: Setup & Configuration

Configure migration parameters using the interactive setup wizard:

```powershell
.\anf_interactive.ps1 setup
```

**What it does:**
- Guides you through all configuration parameters
- Validates inputs and provides helpful prompts
- Creates `config.json` file
- Tests Azure authentication

### Phase 2: Peering Setup

Establish connectivity and begin data synchronization:

```powershell
.\anf_interactive.ps1 peering
```

**What it does:**
1. Authenticates with Azure
2. Creates the target ANF volume
3. Initiates cluster peering (provides ONTAP commands to run)
4. Sets up SVM peering (provides ONTAP commands to run)
5. Begins data synchronization

**ONTAP Commands**: You'll be prompted to execute specific commands on your on-premises ONTAP system. The script provides the exact commands needed.

**Timeline**: Setup takes 15-30 minutes. Data synchronization continues in the background and may take hours or days depending on data size.

### Phase 3: Break Replication & Finalize

Complete the migration when data sync is finished:

```powershell
.\anf_interactive.ps1 break
```

**What it does:**
1. Waits for any in-progress transfer to complete
2. Performs final data replication transfer
3. Breaks the replication relationship
4. Makes the Azure volume writable
5. Cleans up replication configuration

**⚠️ Warning**: Breaking replication stops data synchronization from on-premises. Ensure:
- Data synchronization is complete (check Azure Portal metrics)
- You're ready to switch users to the Azure volume
- You have a rollback plan if needed

### Standalone Monitoring

Monitor replication progress at any time:

```powershell
.\anf_interactive.ps1 monitor
```

**Features:**
- Real-time replication status
- Transfer progress and rates
- Mirror state monitoring
- Continuous updates (Ctrl+C to stop)

## 🔍 Monitoring & Logging

### Log Files

All operations are logged to `anf_migration_interactive.log` in the script directory:
- API requests and responses
- Authentication tokens (masked)
- Configuration changes
- Error details

### Azure Portal Monitoring

Monitor replication in the Azure Portal:
1. Navigate to your Azure NetApp Files volume
2. Check the **Metrics** section
3. Key metrics:
   - Volume Replication Total Transfer
   - Volume Replication Last Transfer Size
   - Volume Replication Lag Time

## 🔒 Security

- **Secrets Protection**: Service principal password stored in `config.json` (gitignored)
- **Token Caching**: OAuth tokens cached in `.token` file (gitignored)
- **Log Sanitization**: Sensitive data masked in logs
- **Least Privilege**: Use dedicated service principal with minimum required permissions

### Recommended Service Principal Permissions

```
Microsoft.NetApp/*
Microsoft.Network/virtualNetworks/subnets/read
Microsoft.Network/virtualNetworks/subnets/join/action
```

## 🆘 Troubleshooting

### Common Issues

**"Failed to get authentication token"**
- Verify service principal credentials in config.json
- Ensure service principal has Contributor role on target resources
- Check azure_tenant_id is correct

**"Config file not found"**
- Run `.\anf_interactive.ps1 setup` to create configuration
- Ensure config.json exists in script directory

**"Volume create request failed"**
- Verify all Azure resource names are correct
- Ensure capacity pool has sufficient space
- Check subnet is properly delegated to Microsoft.NetApp/volumes

**"A new transfer cannot be started since a transfer is already in progress"**
- The script automatically waits for ongoing transfers to complete
- If timeout occurs, wait for current transfer to finish in Azure Portal

### Getting Help

```powershell
# Show detailed help
.\anf_interactive.ps1 help

# Check configuration
.\anf_interactive.ps1 config

# Validate JSON syntax
.\anf_interactive.ps1 diagnose

# View logs
Get-Content .\anf_migration_interactive.log -Tail 50
```

## 📁 File Structure

```
Migration-Assistant/
├── anf_interactive.ps1       # Main PowerShell script
├── config.template.json      # Configuration template
├── config.json               # Your configuration (gitignored)
├── .token                    # Cached auth token (gitignored)
├── anf_migration_interactive.log  # Operation log
├── README.md                 # This file
├── PREREQUISITES.md          # Detailed prerequisites
└── MIGRATION_GUIDE.md        # Migration best practices
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License.

---

## 📚 ONTAP Information Collection Guide

### Purpose

This guide helps you collect the necessary information from your on-premises ONTAP system for migration configuration.

### Required Information

- **Cluster Name** - ONTAP cluster identifier
- **SVM Name** - Storage Virtual Machine name
- **Volume Name** - Source volume to migrate
- **LIF IP Addresses** - Intercluster LIF IPs for peering

### Step-by-Step Collection

#### 1. Log into ONTAP

```bash
ssh admin@<cluster-mgmt-IP>
```

#### 2. Find Your Volume

```bash
volume show
```

Note the **Volume Name** and **Vserver (SVM) Name**.

#### 3. Get Cluster Name

```bash
cluster identity show
```

Note the **Cluster Name**.

#### 4. Get SVM Confirmation

```bash
volume show -volume <VOLUME_NAME> -fields vserver
```

Confirm the **SVM Name**.

#### 5. Get LIF IP Addresses

```bash
network interface show -vserver <SVM_NAME> -fields address
```

Note all **IP addresses** (these are your peer addresses).

### Example Output

| Field | Example Value |
|-------|---------------|
| **Cluster Name** | ONTAP-CLUSTER-01 |
| **SVM Name** | svm_production |
| **Volume Name** | vol_data_01 |
| **LIF IPs** | 10.100.1.10, 10.100.1.11 |

Use these values when running the setup wizard.

---

**For detailed prerequisites and network requirements, see [PREREQUISITES.md](PREREQUISITES.md).**
