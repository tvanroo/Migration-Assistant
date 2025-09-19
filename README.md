# Azure NetApp Files Migration Assistant

A command-line tool for managing Azure NetApp Files migration workflows with robust variable management and conditional logic.

## 📋 Requirements

### System Requirements

- **Python 3.6+** (recommended: Python 3.7+)
- **curl** - For API calls
- **bash** - Shell environment (Linux/macOS/WSL)

### Python Dependencies

```bash
# Install required dependencies
pip install PyYAML

# Or if you get permission errors:
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

## 🚀 Quick Start

### 1. Interactive Setup

Run the setup wizard to configure your migration parameters:

```bash
# Run setup wizard
python3 setup_wizard.py
```

### 2. Interactive Migration

Execute the migration workflow step-by-step:

```bash
# Run interactive migration (menu-driven)
./anf_interactive.sh

# Or run specific phases:
./anf_interactive.sh setup     # Phase 1: Configuration
./anf_interactive.sh peering   # Phase 2: Peering setup  
./anf_interactive.sh break     # Phase 3: Break replication
```



## 📂 Available Scripts

This Migration Assistant provides bash and Python scripts for cross-platform compatibility:

### Setup & Configuration

- `setup_wizard.py` - Interactive configuration wizard

### Migration Execution  

- `anf_interactive.sh` - Interactive migration with menu system

### Usage Examples

#### Interactive Mode (Recommended)

```bash
# Start with menu system
./anf_interactive.sh

# Direct phase execution
./anf_interactive.sh setup    # Configure parameters
./anf_interactive.sh peering  # Set up connectivity
./anf_interactive.sh break    # Finalize migration
```

## 🔧 Configuration

The tool uses `config.yaml` for all settings. You can:

1. **Run Setup Wizard** (recommended): `python3 setup_wizard.py`
2. **Manual Configuration**: Copy `config.template.yaml` to `config.yaml` and edit
3. **View Current Config**: `./anf_interactive.sh config`

### Configuration Sections

- **Azure Basics**: Tenant ID, Subscription ID, Resource Group
- **Service Principal**: App ID and Secret for authentication  
- **NetApp Resources**: Account, Capacity Pool, Volume settings
- **Migration Settings**: Source ONTAP details, protocols, sizing
- **Optional Settings**: QoS, network features, large volume support

## 📋 Workflow Phases

### Phase 1: Setup

- Configure migration parameters
- Generate config.yaml file
- Validate Azure and ONTAP connectivity

### Phase 2: Peering Setup  

- Authenticate with Azure
- Create target volume
- Establish cluster peering
- Set up SVM peering
- Begin data synchronization

### Phase 3: Break Replication

- Perform final data transfer
- Break replication relationship  
- Make target volume writable
- Complete migration

## 🔍 Monitoring & Logging

- **Interactive Mode**: Real-time progress with user confirmations
- **Monitoring Options**: Full, Quick, or Custom monitoring levels
- **Detailed Logs**: All API calls and responses logged
- **Azure Portal**: Monitor replication progress and volume status

## 🛠️ Advanced Usage

### Custom Monitoring

```bash
# Full monitoring (recommended)
export ANF_MONITORING_MODE="full"
./anf_interactive.sh peering

# Quick mode (minimal prompts)  
export ANF_MONITORING_MODE="quick"
./anf_interactive.sh peering
```

### Configuration Management

```bash
# Show current configuration
./anf_interactive.sh config

# Get authentication token
./anf_interactive.sh token
```

## 📁 File Structure

```
├── setup_wizard.py          # Interactive configuration wizard
├── anf_interactive.sh        # Menu-driven migration workflow
├── config.template.yaml     # Configuration template
├── config_backups/         # Backup storage (auto-created)
└── README.md               # This file
```

## 🔒 Security Notes

- Service principal secrets are stored in `config.yaml` (ignored by Git)
- Configuration backups are created automatically with timestamps
- Never commit `config.yaml` or backup files to version control
- Use least-privilege Azure permissions for the service principal

## 🆘 Troubleshooting

### Common Issues

1. **"curl: command not found"**

   ```bash
   # Ubuntu/Debian
   sudo apt-get install curl
   
   # RHEL/CentOS
   sudo yum install curl
   
   # macOS
   brew install curl
   ```

2. **"python3: command not found"**

   ```bash
   # Check if python is available instead
   python --version
   
   # Or install Python 3
   # Ubuntu/Debian: sudo apt-get install python3
   # RHEL/CentOS: sudo yum install python3
   # macOS: brew install python3
   ```

3. **"Permission denied" when running scripts**

   ```bash
   chmod +x *.sh
   ```

4. **"PyYAML not found"**

   ```bash
   pip3 install PyYAML
   # or
   pip install --user PyYAML
   ```

### Getting Help

- Run `./anf_interactive.sh help` for command options
- Check `config_backups/` for previous configurations
- Review logs for detailed API error messages
- Ensure service principal has NetApp Contributor permissions

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.
