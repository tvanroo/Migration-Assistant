# Azure NetApp Files Migration Assistant - Prerequisites

## 🖥️ System Requirements

### Operating System
- ✅ **Windows 10** (version 1809 or later)
- ✅ **Windows 11** (all versions)
- ✅ **Windows Server 2019** or later

### PowerShell
- ✅ **PowerShell 5.1** (built-in to Windows 10/11)
- ✅ **PowerShell Core 7+** (optional, recommended for enhanced features)

> **Note**: No additional software installation required! The tool is pure PowerShell.

## 🔐 Azure Prerequisites

### Azure Subscription
- ✅ Active Azure subscription
- ✅ Sufficient permissions to create/manage NetApp resources
- ✅ Billing enabled for Azure NetApp Files

### Service Principal (Application Registration)

You need an Azure Service Principal with appropriate permissions for API authentication.

#### Creating a Service Principal

**Option 1: Azure Cloud Shell (Recommended)**
```bash
# Create service principal with Contributor role
az ad sp create-for-rbac --name "ANFMigrationAssistant" --role Contributor

# Save the output:
# - appId (Application ID) → use for azure_app_id
# - password (Client Secret) → use for azure_app_secret  
# - tenant (Tenant ID) → use for azure_tenant_id
```

**Option 2: Azure Portal**
1. Navigate to **Azure Active Directory** → **App registrations**
2. Click **New registration**
3. Name: "ANFMigrationAssistant"
4. Click **Register**
5. Copy **Application (client) ID** → use for `azure_app_id`
6. Copy **Directory (tenant) ID** → use for `azure_tenant_id`
7. Go to **Certificates & secrets** → **New client secret**
8. Copy the secret value → use for `azure_app_secret`
9. Go to your subscription's **Access control (IAM)**
10. Add role assignment: **Contributor** to your app registration

### Required Azure Permissions

The Service Principal needs these permissions:

```
Microsoft.NetApp/*
Microsoft.Network/virtualNetworks/subnets/read
Microsoft.Network/virtualNetworks/subnets/join/action
```

These are included in the **Contributor** role at the subscription or resource group level.

### Pre-existing Azure Resources

Before migration, you must have:

- ✅ **Resource Group** - Where ANF resources will be created
- ✅ **Virtual Network** - With a subnet delegated to Microsoft.NetApp/volumes
- ✅ **Azure NetApp Files Account** - Already created
- ✅ **Capacity Pool** - With sufficient free capacity for your volume

#### Subnet Delegation

Your subnet must be delegated to Azure NetApp Files:

1. Go to your Virtual Network → **Subnets**
2. Select your subnet
3. Under **Subnet delegation**, select **Microsoft.NetApp/volumes**
4. Save

## 🌐 Network Requirements

### Connectivity
- ✅ **Internet access** - For Azure API calls (HTTPS/443)
- ✅ **Azure NetApp Files subnet** - Properly configured and delegated
- ✅ **Source ONTAP system** - Network path from Azure to on-premises
- ✅ **Firewall rules** - Allowing required traffic

### Network Ports

| Direction | Port | Protocol | Purpose |
|-----------|------|----------|---------|
| Outbound | 443 | HTTPS | Azure API calls |
| Bidirectional | 11104-11105 | TCP | SnapMirror intercluster communication |
| Bidirectional | Various | TCP/UDP | ONTAP cluster peering |

### DNS Requirements
- On-premises ONTAP cluster must be resolvable from Azure (or use IP addresses)
- Azure NetApp Files resources are automatically assigned FQDNs

## 💾 Source NetApp System Requirements

### ONTAP Version
- ✅ **ONTAP 9.7** or later
- ✅ **Cloud Volumes ONTAP** supported

### ONTAP Prerequisites
- ✅ **Cluster management access** - Admin credentials
- ✅ **Intercluster LIFs** - Configured and reachable from Azure
- ✅ **Source volume** - Existing volume to migrate
- ✅ **SnapMirror license** - Required for replication

### Required ONTAP Information

You'll need to collect the following from your ONTAP system:

| Information | Command | Example Value |
|-------------|---------|---------------|
| Cluster Name | `cluster identity show` | ONTAP-CLUSTER-01 |
| SVM Name | `volume show` | svm_production |
| Volume Name | `volume show` | vol_data_01 |
| LIF IP Addresses | `network interface show -vserver <SVM> -fields address` | 10.100.1.10, 10.100.1.11 |

## 📋 Configuration Information Needed

Before starting the migration, gather the following information:

### Azure Authentication
```json
{
  "azure_tenant_id": "your-tenant-id-guid",
  "azure_subscription_id": "your-subscription-id-guid",
  "azure_app_id": "your-app-id-guid",
  "azure_app_secret": "your-service-principal-password"
}
```

### Target Azure NetApp Files
```json
{
  "target_resource_group": "rg-anf-prod",
  "target_location": "eastus",
  "target_netapp_account": "anf-account-01",
  "target_capacity_pool": "pool-premium",
  "target_volume_name": "vol-migrated-01",
  "target_service_level": "Premium",
  "target_subnet_id": "/subscriptions/.../subnets/anf-subnet",
  "target_protocol_types": "NFSv3",
  "target_usage_threshold": "107374182400"
}
```

### Source ONTAP System
```json
{
  "source_cluster_name": "ONTAP-CLUSTER-01",
  "source_svm_name": "svm_production",
  "source_volume_name": "vol_data_01",
  "source_peer_addresses": "10.100.1.10,10.100.1.11"
}
```

### Replication Settings
```json
{
  "replication_schedule": "hourly",
  "target_network_features": "Standard",
  "target_is_large_volume": "false"
}
```

## ✅ Quick Verification

### Check PowerShell Version
```powershell
# Check your PowerShell version
$PSVersionTable.PSVersion

# Should show 5.1 or higher
```

### Test Azure Connectivity
```powershell
# Test Azure API endpoint
Test-NetConnection -ComputerName management.azure.com -Port 443

# Should show TcpTestSucceeded: True
```

### Verify Service Principal
```powershell
# Test authentication (after configuration)
.\anf_interactive.ps1 token

# Should return a valid access token
```

## 🚀 Ready to Start?

Once you have:
1. ✅ Windows 10/11 with PowerShell 5.1+
2. ✅ Azure Service Principal created
3. ✅ Pre-existing Azure resources (VNet, ANF Account, Capacity Pool)
4. ✅ Source ONTAP system information collected
5. ✅ Network connectivity verified

You're ready to run:
```powershell
.\anf_interactive.ps1 setup
```

## 🆘 Troubleshooting Prerequisites

### "Cannot connect to Azure API"
- Check internet connectivity
- Verify firewall allows HTTPS/443 outbound
- Test: `Test-NetConnection -ComputerName management.azure.com -Port 443`

### "Service Principal authentication failed"
- Verify tenant ID, app ID, and secret are correct
- Ensure service principal has Contributor role
- Check if secret has expired (secrets expire after 1-2 years)

### "Subnet is not delegated"
- Go to Azure Portal → Virtual Network → Subnets
- Select your subnet → Subnet delegation
- Set to **Microsoft.NetApp/volumes**

### "Capacity pool has insufficient space"
- Check available space in your capacity pool
- Ensure target volume size fits within available capacity
- Consider resizing pool or using a different pool

---

*For detailed usage instructions, see [README.md](README.md).*
