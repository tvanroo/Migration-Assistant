# Azure NetApp Files Migration Assistant

A cross-platform command-line tool for managing Azure NetApp Files migration workflows with robust variable management and conditional logic. Built with bash scripts and Python for maximum compatibility across Windows, Linux, and macOS.

## 📋 Requirements

### System Requirements

- **Python 3.6+** (recommended: Python 3.7+)
- **PyYAML** - Python package for YAML configuration parsing
- **curl** - For API calls
- **bash** - Shell environment (see platform-specific setup below)

## 🚀 Quick Setup

### 🪟 **Windows Users**

#### Option 1: Automated Setup (Recommended)

```powershell
# Download and run the automated prerequisite checker
# This will detect and fix common issues automatically
.\check-prerequisites.ps1
```

The prerequisite checker can automatically:

- ✅ Install missing Python packages (PyYAML)
- ✅ Fix Windows Store Python stub issues
- ✅ Download missing Git for Windows
- ✅ Download missing project files from GitHub
- ✅ Provide clear guidance for manual installations

#### Option 2: Manual Setup

1. **Install Git for Windows** (includes Git Bash):
   - Download from: <https://git-scm.com/download/win>

2. **Install Python** (if not already installed):
   - Download from: <https://www.python.org/downloads/windows/>

3. **Install PyYAML**:

   ```powershell
   pip install PyYAML
   ```

4. **Run the migration script**:

   ```powershell
   # From PowerShell
   & "C:\Program Files\Git\bin\bash.exe" -c "./anf_interactive.sh"
   
   # Or open Git Bash directly and run
   ./anf_interactive.sh
   ```

### 🐧 **Linux/macOS Users**

bash and curl are typically pre-installed. Install Python dependencies:

```bash
# Install PyYAML
pip install PyYAML

# Or if you get permission errors
pip install --user PyYAML

# Conda users
conda install pyyaml
```

## 🔍 Verify Installation

```bash
# Check prerequisites
python3 --version  # Should be 3.6+
python3 -c "import yaml; print('✅ PyYAML available')"
curl --version     # Should be available
bash --version     # Should be available
```

**Windows users:** Run `.\check-prerequisites.ps1` to automatically verify all requirements.

## 🚀 Getting Started

### 1. Run Prerequisites Check (Windows)

```powershell
# Automated prerequisite checking and fixing
.\check-prerequisites.ps1
```

### 2. Interactive Setup

Configure your migration parameters:

```bash
# Run setup wizard (works on all platforms)
python3 setup_wizard.py

# Windows Git Bash alternative
& "C:\Program Files\Git\bin\bash.exe" -c "python3 setup_wizard.py"
```

### 3. Execute Migration

```bash
# Interactive migration with menu system
./anf_interactive.sh

# Specific phases
./anf_interactive.sh setup     # Phase 1: Configuration
./anf_interactive.sh peering   # Phase 2: Peering setup  
./anf_interactive.sh break     # Phase 3: Break replication
./anf_interactive.sh monitor   # Monitor replication status anytime
```

## ✅ Development Status

**Current Status:** The Migration Assistant is feature-complete and production-ready.

- ✅ **Phase 1: Setup** - Complete with interactive wizard and validation
- ✅ **Phase 2: Peering** - Complete with interaction modes and optional monitoring  
- ✅ **Phase 3: Break Replication** - Complete with interaction modes
- ✅ **Standalone Monitoring** - Real-time replication status monitoring
- ✅ **Cross-Platform Support** - Windows, Linux, and macOS compatibility
- ✅ **Interaction Modes** - Minimal and Full modes for different user experience levels

> **All migration phases are now complete and tested.** The tool provides a comprehensive migration workflow from initial setup through final volume activation, with flexible monitoring and user interaction options.

## 📂 Core Migration Scripts

This Migration Assistant focuses on two main script types for maximum cross-platform compatibility:

### 🐍 **Python Scripts (.py)**

- **Universal compatibility** across Windows, Linux, and macOS
- **Rich libraries** for YAML parsing, JSON handling, and API interactions
- **Interactive wizards** with user-friendly prompts and validation

### 🐚 **Bash Scripts (.sh)**

- **Native Linux/macOS** shell environment support
- **Windows compatibility** through Git Bash
- **Robust workflow management** with conditional logic and error handling
- **Direct system integration** for file operations and process management

### Available Scripts

#### Setup & Configuration

- `setup_wizard.py` - Interactive configuration wizard

### Migration Execution  

- `anf_interactive.sh` - Interactive migration with menu system

### Usage Examples

#### Interactive Mode (Recommended)

```bash
# Start with menu system
./anf_interactive.sh

# Available menu options:
# 1. Run Setup Wizard
# 2. Run Peering Setup 
# 3. Break Replication & Finalize Migration
# 4. Monitor Replication Status
# 5. Show Current Configuration
# 6. Get Authentication Token Only
# 7. Help
```

#### Direct Phase Execution

```bash
./anf_interactive.sh setup    # Configure parameters
./anf_interactive.sh peering  # Set up connectivity and start sync
./anf_interactive.sh break    # Finalize migration
./anf_interactive.sh monitor  # Monitor replication progress
./anf_interactive.sh config   # Show current configuration
./anf_interactive.sh token    # Get authentication token
./anf_interactive.sh help     # Show help information
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

- Configure migration parameters with interactive wizard
- Generate config.yaml file with validation
- Test Azure and ONTAP connectivity
- **Features**: Step-by-step guidance, configuration validation, backup management

### Phase 2: Peering Setup  

- Authenticate with Azure
- Create target volume with availability zones and QoS support
- Establish cluster peering with ONTAP commands
- Set up SVM peering and authorization
- Begin data synchronization
- **Features**: Interaction modes (Minimal/Full), optional real-time monitoring, consolidated prompting

### Phase 3: Break Replication

- Perform final data transfer
- Break replication relationship  
- Make target volume writable
- Complete migration cleanup
- **Features**: Interaction modes (Minimal/Full), safety confirmations, automated finalization

### Standalone Monitoring

- Discover all replication volumes automatically
- Select volume by source name for monitoring
- Real-time transfer progress and speed calculations
- Average transfer rate since monitoring started
- **Features**: Flexible duration options, Azure metrics integration, Ctrl+C interrupt support

## 🔍 Monitoring & Logging

### Real-Time Monitoring

- **Interactive Mode**: Step-by-step progress with user confirmations
- **Interaction Modes**: Choose between Minimal (auto-continue) or Full (step-by-step) modes
- **Optional Phase 2 Monitoring**: Real-time replication progress during setup
- **Standalone Monitoring**: Monitor any existing replication anytime with `./anf_interactive.sh monitor`

### Monitoring Features

- **Volume Discovery**: Automatically finds all replication volumes
- **Source Volume Selection**: Choose which migration to monitor by source name
- **Transfer Metrics**: Total transferred, progress, and average transfer rates
- **Flexible Duration**: 15 minutes to 2+ hours, or custom duration
- **Azure Metrics Integration**: Uses Azure Insights API with 5-minute delay awareness

### Monitoring Levels

```bash
# Full monitoring (recommended for new users)
export ANF_MONITORING_MODE="full"
./anf_interactive.sh peering

# Quick mode (minimal prompts for experienced users)  
export ANF_MONITORING_MODE="quick"
./anf_interactive.sh peering

# Custom monitoring (user choice each time)
export ANF_MONITORING_MODE="custom"
./anf_interactive.sh peering
```

### Interaction Modes (Phase 2 & 3)

```bash
# Set interaction mode for automated workflows
export ANF_INTERACTION_MODE="minimal"  # Auto-continue through most steps
export ANF_INTERACTION_MODE="full"     # Step-by-step prompts (default)
```

### Logging

- **Detailed Logs**: All API calls and responses logged to `anf_migration_interactive.log`
- **Azure Portal**: Monitor replication progress and volume status
- **Timestamped Events**: Complete audit trail of all migration activities

## 🛠️ Advanced Usage

### Environment-Based Interaction Modes

```bash
# Minimal mode - Auto-continue through most steps (experienced users)
export ANF_INTERACTION_MODE="minimal"
./anf_interactive.sh peering
./anf_interactive.sh break

# Full mode - Step-by-step prompts (default, new users)
export ANF_INTERACTION_MODE="full"
./anf_interactive.sh peering
./anf_interactive.sh break
```

### Custom Monitoring

```bash
# Full monitoring (recommended)
export ANF_MONITORING_MODE="full"
./anf_interactive.sh peering

# Quick mode (minimal prompts)  
export ANF_MONITORING_MODE="quick"
./anf_interactive.sh peering

# Custom mode (user choice each time)
export ANF_MONITORING_MODE="custom"
./anf_interactive.sh peering
```

### Standalone Replication Monitoring

```bash
# Monitor existing replications anytime
./anf_interactive.sh monitor

# Available in interactive menu as option 4
./anf_interactive.sh
# Then select: 4. Monitor Replication Status
```

### Configuration Management

```bash
# Show current configuration
./anf_interactive.sh config

# Get authentication token
./anf_interactive.sh token

# Run setup wizard again
./anf_interactive.sh setup
```

### Workflow Combinations

```bash
# Complete migration in sequence
./anf_interactive.sh setup    # Configure everything
./anf_interactive.sh peering  # Start replication
./anf_interactive.sh monitor  # Check progress (optional)
./anf_interactive.sh break    # Finalize migration

# Quick experienced user workflow
export ANF_INTERACTION_MODE="minimal"
./anf_interactive.sh peering && ./anf_interactive.sh break
```

## 📁 File Structure

```text
├── setup_wizard.py          # Interactive configuration wizard
├── anf_interactive.sh        # Main migration workflow (bash script)
├── check-prerequisites.ps1  # Windows prerequisite checker with auto-fix
├── config.template.yaml     # Configuration template
├── config_backups/          # Backup storage (auto-created)
├── validate_variables.py    # Configuration validation utilities
└── README.md                # This file
```

### Core Files

- **`anf_interactive.sh`** - Cross-platform bash script for migration workflows
- **`setup_wizard.py`** - Python configuration wizard for easy setup
- **`check-prerequisites.ps1`** - Windows PowerShell script for automated prerequisite checking and fixing

## 🔒 Security Notes

- Service principal secrets are stored in `config.yaml` (ignored by Git)
- Configuration backups are created automatically with timestamps
- Never commit `config.yaml` or backup files to version control
- Use least-privilege Azure permissions for the service principal

## 🆘 Troubleshooting

### Windows Users - Quick Fix

For Windows users experiencing setup issues, run the automated prerequisite checker:

```powershell
.\check-prerequisites.ps1
```

This will automatically detect and fix common issues like:

- Missing or broken Python installations
- Windows Store Python stub problems  
- Missing PyYAML package
- Missing Git for Windows
- Missing project files

### Common Issues (All Platforms)

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
