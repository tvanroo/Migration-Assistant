# Migr## 📋 Requirements

### System Requirements
- **Python 3.6+** (recommended: Python 3.7+)
- **curl** - For API calls (Linux/macOS) or PowerShell Invoke-WebRequest (Windows)
- **bash** - Shell environment (Linux/macOS) or **PowerShell 5.0+** (Windows)Assistant

# Azure NetApp Files Migration Assistant

A command-line tool for managing Azure NetApp Files migration workflows with robust variable management and conditional logic.

## � Requirements

### System Requirements
- **Python 3.6+** (recommended: Python 3.7+)
- **curl** - For API calls
- **bash** - Shell environment

### Python Dependencies
```bash
# Linux/macOS
pip install PyYAML

# Windows (Command Prompt or PowerShell)
pip install PyYAML
# or if you get permission errors:
pip install --user PyYAML

# Conda (all platforms)
conda install pyyaml
```

### Verification
```bash
# Check Python version (requires 3.6+)
python3 --version

# Test dependencies
python3 -c "import yaml, json, sys; print('✅ All dependencies available')"
```

## �🚀 Quick Start

### 1. Interactive Setup
Configure your migration settings using the interactive wizard:

```bash
./anf_runner.sh setup
```

### 2. Validate Configuration
```bash
./anf_runner.sh validate
```

### 3. Run Migration Workflow
```bash
# Auto-detect protocol and QoS from config
./anf_runner.sh generate

# Or specify explicitly
./anf_runner.sh generate NFSv3 Auto
./anf_runner.sh generate SMB Manual
```

## �️ Cross-Platform Support

This Migration Assistant supports both Unix/Linux/macOS (bash) and Windows (PowerShell) environments:

### Linux/macOS (Bash Scripts)
```bash
# Interactive setup
./anf_runner.sh setup

# Validate configuration  
./anf_runner.sh validate

# Run interactive workflow
./anf_interactive.sh
```

### Windows (PowerShell Scripts)
```powershell
# Interactive setup
.\anf_runner.ps1 setup

# Validate configuration
.\anf_runner.ps1 validate

# Run interactive workflow
.\anf_interactive.ps1
```

### Available Script Pairs
| Purpose | Linux/macOS | Windows |
|---------|-------------|---------|
| Main Runner | `anf_runner.sh` | `anf_runner.ps1` |
| Core Workflow | `anf_workflow.sh` | `anf_workflow.ps1` |
| Interactive Mode | `anf_interactive.sh` | `anf_interactive.ps1` |
| Setup Wizard | `setup_wizard.py` | `setup_wizard.py` |

## �📁 Project Structure

```
ANF/Migration Assistant/
├── generated_scripts/         # Individual CURL scripts
├── config.yaml               # Configuration file
├── anf_config.py            # Configuration manager
├── anf_runner.sh           # Main workflow runner
├── setup_wizard.py         # Interactive setup wizard
└── workflow_*.sh          # Generated workflow scripts
```

## 🔧 Configuration

The system uses `config.yaml` for all settings. You can edit this file directly or use the interactive setup wizard.

### Required Variables
- `azure_tenant_id`: Azure AD tenant ID
- `azure_subscription_id`: Azure subscription ID  
- `target_resource_group`: Target resource group
- `target_netapp_account`: NetApp account name
- `target_capacity_pool`: Capacity pool name
- `target_volume_name`: Destination volume name
- `azure_app_id`: Service principal application ID
- `azure_app_secret`: Service principal secret
- `target_location`: Azure region (e.g., "eastus")

### Protocol & QoS Detection
The system automatically detects:
- **Protocol**: NFSv3 vs SMB based on `target_protocol_types`
- **QoS**: Auto vs Manual based on presence of `target_throughput_mibps`

## 🛠 Commands

### Configuration Management
```bash
# Interactive configuration setup
./anf_runner.sh setup

# Validate configuration
./anf_runner.sh validate

# List available workflows  
./anf_runner.sh list
```

### Token Management
```bash
# Get fresh Azure AD token
./anf_runner.sh token
```

### Workflow Execution
```bash
# Generate and run workflow (auto-detect settings)
./anf_runner.sh generate

# Generate specific protocol/QoS combination
./anf_runner.sh generate NFSv3 Auto
./anf_runner.sh generate SMB Manual

# Run existing workflow script
./anf_runner.sh run workflow_nfsv3_auto.sh
```

## 📋 Migration Workflow Steps

1. **Authentication** - Obtain Azure AD token (30 seconds)
2. **Create Target Volume** - Create destination volume (5-10 minutes)
3. **Cluster Peer Request** - Initiate peering with source cluster (1-2 minutes)
4. **Accept Peer Request** - Accept the peering relationship (30 seconds)
5. **Authorize Replication** - Authorize external replication (1 minute)
6. **Re-Sync** - Perform replication transfer (depends on data size)
7. **Break Relationship** - Break replication relationship (30 seconds)
8. **Finalize** - Finalize external replication (1 minute)

⏱️ **Total Time**: Typically 15-30 minutes + data transfer time

### 🔍 **Monitoring Options**
- **Interactive Mode** (`anf_interactive.sh`): Full monitoring with progress tracking
- **Basic Mode** (`anf_runner.sh generate`): Fast execution with minimal monitoring
- **Volume Creation**: Monitored every 30 seconds up to 20 minutes
- **Async Operations**: Monitored every 60 seconds up to 2 hours

## 🔄 Protocol & QoS Combinations

The system supports 4 combinations:

| Protocol | QoS Type | Description |
|----------|----------|-------------|
| NFSv3    | Auto     | Automatic throughput scaling |
| NFSv3    | Manual   | Fixed throughput (specify `volthroughputMibps`) |
| NFSv4.1  | Auto     | Automatic throughput scaling |
| NFSv4.1  | Manual   | Fixed throughput (specify `volthroughputMibps`) |
| CIFS     | Auto     | Automatic throughput scaling |  
| CIFS     | Manual   | Fixed throughput (specify `volthroughputMibps`) |

## 🔐 Security Features

- **Token Management**: Secure storage of Azure AD tokens
- **Secret Handling**: Sensitive data marked separately in config
- **Validation**: Required field checking and placeholder detection
- **Logging**: All operations logged to `anf_migration.log`

## 📝 Examples

### Example 1: NFSv3 with Auto QoS
```bash
# Configure for NFSv3
echo 'target_protocol_types: NFSv3' >> config.yaml
echo 'target_throughput_mibps: ""' >> config.yaml

# Generate and run
./anf_runner.sh generate
```

### Example 2: CIFS with Manual QoS
```bash
# Use the setup wizard - when prompted for QoS, enter a number
./anf_runner.sh setup
# At QoS prompt: enter "500" for 500 MiB/s manual throughput

# Or edit config manually
echo 'target_protocol_types: CIFS' >> config.yaml  
echo 'target_throughput_mibps: "500"' >> config.yaml

# Generate and run
./anf_runner.sh generate
```

### Example 3: Just validate without running
```bash
# Check configuration and show detected settings
./anf_runner.sh validate
```

## 🚨 Troubleshooting

### Common Issues

**"Configuration validation failed"**
- Check that all required fields are filled in `config.yaml`
- Ensure no placeholder values like "CHANGE_ME" remain

**"Token request failed"**
- Verify `appId` and `appIdPassword` are correct
- Check that the service principal has proper permissions
- Ensure `tenant` ID is correct

**"Workflow execution failed"**
- Check the log file: `tail -f anf_migration.log`
- Verify Azure resources exist (resource group, NetApp account, etc.)
- Ensure sufficient permissions on the Azure subscription

### Debug Mode
```bash
# Enable verbose logging
export DEBUG=1
./anf_runner.sh generate
```

## 📚 Generated Files

- `workflow_*.sh` - Complete workflow scripts
- `.token` - Cached Azure AD token (expires in 1 hour)
- `anf_migration.log` - Operation logs
- Individual scripts in `generated_scripts/` directory

## 🔄 Advanced Usage

### Running Individual Steps
```bash
# Run just the authentication step
bash generated_scripts/01_*.sh

# Run just volume creation
bash generated_scripts/03_*.sh  # or 04, 05, 06 depending on protocol/QoS
```

### Custom Modifications
The generated scripts can be edited for specific requirements before execution.

### Configuration Management
- **Manual editing**: Directly edit `config.yaml`
- **Interactive setup**: Use `./anf_runner.sh setup`
- **Mixed approach**: Edit manually then validate with `./anf_runner.sh validate`

## 🎛️ Setup Wizard Features

The interactive setup wizard provides:
- **Smart defaults** from existing configuration
- **Protocol validation** (NFSv3, NFSv4.1, CIFS only)
- **Azure cloud selection** (Commercial, Government, Custom)
- **Improved QoS input** - Enter 'Auto' or a number (MiB/s)
- **Default save behavior** - Saves unless you explicitly decline (Y/n)
- **Configuration backup** before changes

## 📞 Support

For issues or questions:
1. Check the log file: `anf_migration.log`
2. Validate configuration: `./anf_runner.sh validate`
3. Review the generated CURL commands in `workflow_*.sh`

---

*Azure NetApp Files Migration Assistant - Standalone CLI Tool*
