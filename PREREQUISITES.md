# Azure NetApp Files Migration Assistant - Complete Prerequisites

## 🖥️ **System Requirements**

### **Operating System**
- ✅ **Linux** (Ubuntu, CentOS, RHEL, etc.)
- ✅ **macOS** (10.14+)
- ✅ **Windows** (10/11 with WSL, PowerShell, or Command Prompt)

### **Required Software**

#### **1. Python**
- **Minimum**: Python 3.6+
- **Recommended**: Python 3.7+ or newer
- **Features used**: f-strings, pathlib, type hints, dictionary unpacking

#### **2. Python Package: PyYAML**
- **Required for**: Configuration file parsing
- **Installation**: `pip install PyYAML`

#### **3. curl**
- **Required for**: Azure REST API calls
- **Linux/macOS**: Usually pre-installed
- **Windows**: Available in Windows 10 1803+ or install separately

#### **4. Bash Shell**
- **Linux/macOS**: Built-in
- **Windows**: Use WSL, Git Bash, or PowerShell (with modifications)

## 🔐 **Azure Prerequisites**

### **Azure Subscription**
- ✅ Active Azure subscription
- ✅ Sufficient permissions for NetApp resources
- ✅ Billing enabled for Azure NetApp Files

### **Service Principal (App Registration)**
- ✅ Azure AD App Registration created
- ✅ Client ID (Application ID)
- ✅ Client Secret (Application Password)
- ✅ Appropriate permissions assigned

### **Required Azure Permissions**
```
Microsoft.NetApp/*
Microsoft.Network/virtualNetworks/subnets/read
Microsoft.Network/virtualNetworks/subnets/join/action
```

### **Azure Resources (Pre-existing)**
- ✅ **Resource Group** - Target resource group
- ✅ **Virtual Network** - With delegated subnet for ANF
- ✅ **NetApp Account** - Azure NetApp Files account
- ✅ **Capacity Pool** - With sufficient capacity

### **Source NetApp System**
- ✅ **On-premises NetApp system** or **Cloud Volumes ONTAP**
- ✅ **Cluster management access**
- ✅ **Network connectivity** to Azure
- ✅ **Source volume** ready for migration

## 📋 **Configuration Information Needed**

### **Azure Authentication**
```yaml
azure_tenant_id: "your-tenant-id"
azure_subscription_id: "your-subscription-id"  
azure_app_id: "your-app-id"
azure_app_secret: "your-app-secret"
```

### **Azure API Configuration**
```yaml
azure_api_version: "2025-06-01"
azure_api_base_url: "https://management.azure.com"
azure_auth_base_url: "https://login.microsoftonline.com/"
```

### **Target Azure NetApp Files**
```yaml
target_resource_group: "your-rg-name"
target_location: "eastus" # or your preferred region
target_netapp_account: "your-anf-account"
target_capacity_pool: "your-pool-name"
target_volume_name: "your-new-volume-name"
target_service_level: "Standard" # Standard/Premium/Ultra
target_subnet_id: "/subscriptions/.../subnets/anf-subnet"
target_protocol_types: "NFSv3" # or CIFS/SMB
```

### **Source NetApp System**
```yaml
source_cluster_name: "source-cluster"
source_hostname: "source.netapp.com"
source_peer_addresses: "192.168.1.100"
source_server_name: "source-svm"
source_volume_name: "source_vol"
```

### **Replication Settings**
```yaml
replication_schedule: "Hourly" # Hourly/Daily/Weekly
target_usage_threshold: "107374182400" # in bytes
target_network_features: "Standard"
target_is_large_volume: "false"
```

## 🌐 **Network Requirements**

### **Connectivity**
- ✅ **Internet access** for Azure API calls
- ✅ **Azure NetApp Files subnet** properly delegated
- ✅ **Source NetApp system** accessible from Azure
- ✅ **Firewall rules** allowing required traffic

### **Ports and Protocols**
- ✅ **HTTPS (443)** - Azure API access
- ✅ **NetApp cluster management** - Source system access
- ✅ **Replication traffic** - Between source and Azure

## 💻 **Installation Commands by Platform**

### **Linux (Ubuntu/Debian)**
```bash
# Update system
sudo apt update

# Install Python and pip
sudo apt install python3 python3-pip curl

# Install PyYAML
pip3 install PyYAML

# Verify installation
python3 --version
python3 -c "import yaml; print('PyYAML installed:', yaml.__version__)"
```

### **Linux (CentOS/RHEL/Fedora)**
```bash
# Install Python and pip
sudo yum install python3 python3-pip curl
# or for newer versions:
sudo dnf install python3 python3-pip curl

# Install PyYAML
pip3 install PyYAML

# Verify installation
python3 --version
python3 -c "import yaml; print('PyYAML installed:', yaml.__version__)"
```

### **macOS**
```bash
# Install Homebrew if not installed
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install Python
brew install python3

# Install PyYAML
pip3 install PyYAML

# Verify installation
python3 --version
python3 -c "import yaml; print('PyYAML installed:', yaml.__version__)"
```

### **Windows**
```cmd
REM Option 1: Using Python installer from python.org
REM Download and install Python 3.7+ from https://python.org
REM Make sure to check "Add Python to PATH"

REM Option 2: Using winget
winget install Python.Python.3

REM Install PyYAML
pip install PyYAML

REM Verify installation
python --version
python -c "import yaml; print('PyYAML installed:', yaml.__version__)"
```

### **Windows with WSL**
```bash
# Install WSL Ubuntu, then follow Linux Ubuntu instructions above
wsl --install -d Ubuntu
```

## ✅ **Quick Verification Script**

Create and run this verification script:

```bash
#!/bin/bash
# verify_prerequisites.sh

echo "🔍 Checking Prerequisites for ANF Migration Assistant"
echo "=================================================="

# Check Python
if command -v python3 >/dev/null 2>&1; then
    PYTHON_VERSION=$(python3 --version)
    echo "✅ Python: $PYTHON_VERSION"
    
    # Check Python version (3.6+)
    python3 -c "
import sys
if sys.version_info >= (3, 6):
    print('✅ Python version is compatible (3.6+)')
else:
    print('❌ Python version too old. Requires Python 3.6+')
    exit(1)
"
else
    echo "❌ Python 3 not found"
    exit 1
fi

# Check PyYAML
if python3 -c "import yaml" 2>/dev/null; then
    YAML_VERSION=$(python3 -c "import yaml; print(yaml.__version__)")
    echo "✅ PyYAML: $YAML_VERSION"
else
    echo "❌ PyYAML not installed. Run: pip install PyYAML"
    exit 1
fi

# Check curl
if command -v curl >/dev/null 2>&1; then
    CURL_VERSION=$(curl --version | head -n1)
    echo "✅ curl: $CURL_VERSION"
else
    echo "❌ curl not found"
    exit 1
fi

# Check bash
if command -v bash >/dev/null 2>&1; then
    BASH_VERSION=$(bash --version | head -n1)
    echo "✅ bash: $BASH_VERSION"
else
    echo "❌ bash not found"
    exit 1
fi

echo ""
echo "🎉 All prerequisites are satisfied!"
echo "You can now run the ANF Migration Assistant."
```

## 📚 **Next Steps After Meeting Prerequisites**

1. **Clone/Download** the Migration Assistant
2. **Run setup wizard**: `./anf_runner.sh setup`
3. **Validate configuration**: `./anf_runner.sh validate`
4. **Test connection**: `./anf_runner.sh token`
5. **Run migration**: `./anf_runner.sh generate`

## 🆘 **Common Issues and Solutions**

### **"python3 not found"**
- Install Python 3.6+ from official source
- Ensure Python is in system PATH

### **"No module named yaml"**
- Run: `pip install PyYAML`
- Try: `pip3 install PyYAML`
- Use: `pip install --user PyYAML` if permission issues

### **"curl not found"**
- **Linux**: `sudo apt install curl` or `sudo yum install curl`
- **Windows**: Use Windows 10 1803+ or install curl separately

### **"Permission denied"**
- Use `pip install --user PyYAML`
- Run terminal as administrator (Windows)
- Use `sudo` for system-wide installation (Linux/macOS)

---

*This completes all prerequisites for the Azure NetApp Files Migration Assistant.*
