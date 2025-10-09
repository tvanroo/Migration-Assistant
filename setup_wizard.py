#!/usr/bin/env python3
"""
Azure NetApp Files Migration Assistant - Interactive Setup Wizard
Walks through configuring all required variables step by step
"""

import os
import re
import sys
import shutil
import getpass
import platform
import argparse
from datetime import datetime
from pathlib import Path
from typing import Dict, Any, Optional

# Check for required dependencies
try:
    import yaml
except ImportError:
    print("❌ Error: PyYAML is required but not installed.")
    print("\n💡 To fix this, run one of the following commands:")
    print("   pip install PyYAML")
    print("   pip3 install PyYAML")
    print("   pip install --user PyYAML")
    print("\n📚 For more help, see: https://pyyaml.org/wiki/PyYAMLDocumentation")
    sys.exit(1)

class ANFSetupWizard:
    """Interactive wizard for setting up ANF Migration Assistant"""
    
    def __init__(self, config_file: str = "config.yaml"):
        self.config = {
            'variables': {},
            'secrets': {}
        }
        self.config_file = Path(config_file)
        
    def print_header(self):
        """Print welcome header"""
        print("=" * 80)
        print("🚀 Azure NetApp Files Migration Assistant - Setup Wizard")
        print("=" * 80)
        print(f"\n📁 Configuration will be saved to: {self.config_file}")
        print("\nThis wizard will help you configure all required variables.")
        print("You can press ENTER to keep existing values or type 'skip' to leave blank.\n")
    
    def print_section(self, title: str):
        """Print section header"""
        print(f"\n{'─' * 60}")
        print(f"📋 {title}")
        print('─' * 60)
    
    def load_existing_config(self) -> Dict[str, Any]:
        """Load existing configuration if it exists"""
        if self.config_file.exists():
            with open(self.config_file) as f:
                return yaml.safe_load(f)
        
        # No config.yaml exists - check if user wants to use template
        template_file = Path("config.template.yaml")
        if template_file.exists():
            print(f"\n📄 No existing configuration found at {self.config_file}")
            print(f"🎯 Found template file: {template_file}")
            print("\nWould you like to start with the template as a baseline?")
            print("This will pre-populate fields with example values that you can modify.")
            
            while True:
                choice = input("\nUse template as starting point? [y/n]: ").lower().strip()
                if choice in ['y', 'yes']:
                    print(f"✅ Loading template from {template_file}")
                    try:
                        with open(template_file) as f:
                            template_config = yaml.safe_load(f)
                            print("📋 Template loaded successfully!")
                            return template_config
                    except Exception as e:
                        print(f"⚠️  Error loading template: {e}")
                        print("Starting with blank configuration instead.")
                        break
                elif choice in ['n', 'no']:
                    print("✅ Starting with blank configuration")
                    break
                else:
                    print("Please enter 'y' for yes or 'n' for no")
        
        return {'variables': {}, 'secrets': {}}
    
    def get_input(self, prompt: str, current_value: str = "", required: bool = True, 
                  secret: bool = False, validate_func=None) -> str:
        """Get user input with validation"""
        
        if current_value and not secret:
            display_prompt = f"{prompt} [{current_value}]: "
        else:
            display_prompt = f"{prompt}: "
        
        while True:
            if secret:
                value = getpass.getpass(display_prompt)
            else:
                value = input(display_prompt).strip()
            
            # Use current value if empty
            if not value and current_value:
                return current_value
            
            # Allow skipping non-required fields
            if not value and not required:
                return ""
            
            # Check if user wants to skip
            if value.lower() == 'skip':
                return current_value if current_value else ""
            
            # Validate input
            if validate_func:
                try:
                    validate_func(value)
                except ValueError as e:
                    print(f"❌ {e}")
                    continue
            
            if required and not value:
                print("❌ This field is required. Please enter a value.")
                continue
            
            return value
    
    def validate_uuid(self, value: str):
        """Validate UUID format"""
        uuid_pattern = r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        if not re.match(uuid_pattern, value, re.IGNORECASE):
            raise ValueError("Must be a valid UUID format (xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx)")
    
    def validate_azure_region(self, value: str):
        """Validate Azure region format"""
        # Common Azure regions - not exhaustive but covers most cases
        valid_regions = {
            'eastus', 'eastus2', 'westus', 'westus2', 'westus3', 'centralus', 'northcentralus', 'southcentralus',
            'canadacentral', 'canadaeast', 'brazilsouth', 'northeurope', 'westeurope', 'francecentral',
            'uksouth', 'ukwest', 'germanywc', 'norwayeast', 'switzerlandnorth', 'uaenorth',
            'southafricanorth', 'australiaeast', 'australiasoutheast', 'southeastasia', 'eastasia',
            'japaneast', 'japanwest', 'koreacentral', 'centralindia', 'southindia', 'westindia'
        }
        
        if value.lower() not in valid_regions:
            print(f"⚠️  Warning: '{value}' might not be a valid Azure region.")
            confirm = input("Continue anyway? (y/n): ").lower()
            if confirm != 'y':
                raise ValueError("Please enter a valid Azure region")
    
    def validate_service_level(self, value: str):
        """Validate ANF service level"""
        valid_levels = ['Standard', 'Premium', 'Ultra']
        if value not in valid_levels:
            raise ValueError(f"Must be one of: {', '.join(valid_levels)}")
    
    def validate_protocol(self, value: str):
        """Validate protocol type"""
        valid_protocols = ['NFSv3', 'NFSv4.1', 'CIFS']
        if value not in valid_protocols:
            raise ValueError(f"Must be one of: {', '.join(valid_protocols)}")
    
    def validate_replication_schedule(self, value: str):
        """Validate replication schedule"""
        valid_schedules = ['Hourly', 'Daily', 'Weekly']
        if value not in valid_schedules:
            raise ValueError(f"Must be one of: {', '.join(valid_schedules)}")
    
    def validate_ip_address(self, value: str):
        """Validate IP address format"""
        import socket
        try:
            socket.inet_aton(value)
        except socket.error:
            raise ValueError("Must be a valid IP address (e.g., 192.168.1.100)")
    
    def validate_numeric(self, value: str):
        """Validate numeric input"""
        if not value.isdigit():
            raise ValueError("Must be a number")
    
    def collect_peer_addresses(self, existing: Dict) -> str:
        """Collect multiple peer addresses from user"""
        print("\n📋 Source Cluster Peer Addresses")
        print("💡 Enter the IP address(es) of your ONTAP cluster's LIFs")
        print("   You can find these with: 'network interface show -vserver <SVM> -fields address'")
        print("   Enter one IP address at a time. Press ENTER with no input when done.\n")
        
        # Parse existing peer addresses
        current_peers = existing.get('variables', {}).get('source_peer_addresses', '')
        existing_ips = []
        
        if current_peers and current_peers.strip() and current_peers != '192.168.1.100':
            # Try to parse existing format - could be comma-separated or JSON array format
            import re
            # Extract IP addresses from various formats
            ip_matches = re.findall(r'(?:\")?([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})(?:\")?', current_peers)
            existing_ips = [ip for ip in ip_matches if ip != '192.168.1.100']  # Filter out placeholder
        
        peer_ips = []
        
        # Show existing IPs if any
        if existing_ips:
            print(f"📋 Current peer addresses:")
            for i, ip in enumerate(existing_ips, 1):
                print(f"  {i}. {ip}")
            
            keep_existing = self.get_input(
                "Keep existing peer addresses? (Y/n)", 
                "Y", 
                required=False
            )
            
            if keep_existing.lower() in ['y', 'yes', '']:
                peer_ips = existing_ips.copy()
                print(f"✅ Keeping {len(peer_ips)} existing peer address(es)")
            else:
                print("🗑️  Starting fresh with peer addresses")
        
        # Collect additional or new peer addresses
        peer_count = len(peer_ips)
        while True:
            prompt = f"Peer IP Address #{peer_count + 1} (or ENTER to finish)"
            
            try:
                ip_address = self.get_input(
                    prompt,
                    "",
                    required=False,
                    validate_func=None  # We'll validate manually to allow empty
                )
                
                # User finished entering IPs
                if not ip_address:
                    break
                
                # Validate the IP address
                try:
                    self.validate_ip_address(ip_address)
                except ValueError as e:
                    print(f"❌ {e}")
                    continue
                
                # Check for duplicates
                if ip_address in peer_ips:
                    print(f"⚠️  IP {ip_address} already added, skipping")
                    continue
                
                peer_ips.append(ip_address)
                peer_count += 1
                print(f"✅ Added peer IP: {ip_address}")
                
            except KeyboardInterrupt:
                raise
            except Exception as e:
                print(f"❌ Error: {e}")
                continue
        
        # Validate we have at least one peer address
        if not peer_ips:
            print("⚠️  Warning: No peer addresses configured. This will cause cluster peering to fail.")
            add_placeholder = self.get_input(
                "Add placeholder IP (192.168.1.100)? You can update it later (Y/n)",
                "Y",
                required=False
            )
            
            if add_placeholder.lower() in ['y', 'yes', '']:
                return "192.168.1.100"
            else:
                return ""
        
        # Format the addresses for the config
        if len(peer_ips) == 1:
            result = peer_ips[0]
        else:
            # For multiple IPs, store as JSON array string
            import json
            result = json.dumps(peer_ips)
        
        print(f"\n✅ Configured {len(peer_ips)} peer address(es): {', '.join(peer_ips)}")
        return result
    
    def configure_azure_basics(self, existing: Dict):
        """Configure basic Azure settings"""
        self.print_section("Azure Basics")
        
        # Tenant ID
        current_tenant = existing.get('variables', {}).get('azure_tenant_id', '')
        self.config['variables']['azure_tenant_id'] = self.get_input(
            "Azure AD Tenant ID", 
            current_tenant, 
            required=True, 
            validate_func=self.validate_uuid
        )
        
        # Subscription ID
        current_sub = existing.get('variables', {}).get('azure_subscription_id', '')
        self.config['variables']['azure_subscription_id'] = self.get_input(
            "Azure Subscription ID", 
            current_sub, 
            required=True, 
            validate_func=self.validate_uuid
        )
        
        # Location
        current_location = existing.get('variables', {}).get('target_location', 'eastus2')
        self.config['variables']['target_location'] = self.get_input(
            "Azure Region (e.g., eastus, westus2)", 
            current_location, 
            required=True, 
            validate_func=self.validate_azure_region
        )
        
        # Resource Group
        current_rg = existing.get('variables', {}).get('target_resource_group', '')
        self.config['variables']['target_resource_group'] = self.get_input(
            "Resource Group Name", 
            current_rg, 
            required=True
        )
    
    def configure_service_principal(self, existing: Dict):
        """Configure service principal authentication"""
        self.print_section("Service Principal Authentication")
        print("💡 You need a service principal with NetApp contributor permissions")
        
        # App ID
        current_app_id = existing.get('variables', {}).get('azure_app_id', '')
        self.config['variables']['azure_app_id'] = self.get_input(
            "Service Principal Application ID", 
            current_app_id, 
            required=True, 
            validate_func=self.validate_uuid
        )
        
        # App Secret
        current_secret = existing.get('secrets', {}).get('azure_app_secret', '')
        if current_secret and current_secret != 'CHANGE_ME':
            print(f"✅ Service principal secret already configured")
            keep_secret = input("Keep existing secret? (Y/n): ").lower()
            if keep_secret == 'y' or keep_secret == '':
                self.config['secrets']['azure_app_secret'] = current_secret
            else:
                self.config['secrets']['azure_app_secret'] = self.get_input(
                    "Service Principal Secret", 
                    "", 
                    required=True, 
                    secret=True
                )
        else:
            self.config['secrets']['azure_app_secret'] = self.get_input(
                "Service Principal Secret", 
                "", 
                required=True, 
                secret=True
            )
        
        # API Endpoints - Auth URL with options
        current_auth_url = existing.get('variables', {}).get('azure_auth_base_url', '')
        
        # Determine current selection
        if 'login.microsoftonline.com' in current_auth_url:
            current_selection = 'commercial'
        elif 'login.microsoftonline.us' in current_auth_url:
            current_selection = 'government'
        else:
            current_selection = 'other'
        
        print("\n💡 Auth URL Options:")
        print("  1. Commercial (default) - https://login.microsoftonline.com/")
        print("  2. Government - https://login.microsoftonline.us/")
        print("  3. Other - specify custom URL")
        
        current_display = {'commercial': '1', 'government': '2', 'other': '3'}.get(current_selection, '1')
        auth_choice = self.get_input(
            f"Select Auth URL (1/2/3)", 
            current_display, 
            required=True
        )
        
        if auth_choice == '1' or auth_choice.lower() == 'commercial':
            self.config['variables']['azure_auth_base_url'] = 'https://login.microsoftonline.com/'
        elif auth_choice == '2' or auth_choice.lower() == 'government':
            self.config['variables']['azure_auth_base_url'] = 'https://login.microsoftonline.us/'
        elif auth_choice == '3' or auth_choice.lower() == 'other':
            self.config['variables']['azure_auth_base_url'] = self.get_input(
                "Custom Auth URL", 
                current_auth_url, 
                required=True
            )
        else:
            # Default to commercial if invalid choice
            self.config['variables']['azure_auth_base_url'] = 'https://login.microsoftonline.com/'
        
        # API URL - standard for all regions
        current_api_url = existing.get('variables', {}).get('azure_api_base_url', 'https://management.azure.com')
        self.config['variables']['azure_api_base_url'] = self.get_input(
            "Azure Management API URL", 
            current_api_url, 
            required=True
        )
    
    def configure_netapp_resources(self, existing: Dict):
        """Configure NetApp Files resources"""
        self.print_section("Azure NetApp Files Resources")
        
        # Account Name
        current_account = existing.get('variables', {}).get('target_netapp_account', '')
        self.config['variables']['target_netapp_account'] = self.get_input(
            "NetApp Account Name", 
            current_account, 
            required=True
        )
        
        # Pool Name
        current_pool = existing.get('variables', {}).get('target_capacity_pool', '')
        self.config['variables']['target_capacity_pool'] = self.get_input(
            "Capacity Pool Name", 
            current_pool, 
            required=True
        )
        
        # Service Level
        current_service_level = existing.get('variables', {}).get('target_service_level', '')
        self.config['variables']['target_service_level'] = self.get_input(
            "Service Level (Standard/Premium/Ultra)", 
            current_service_level, 
            required=True, 
            validate_func=self.validate_service_level
        )
        
        # Volume subnet
        current_subnet = existing.get('variables', {}).get('target_subnet_id', '')
        print("\n💡 Volume subnet format: /subscriptions/{sub-id}/resourceGroups/{rg}/providers/Microsoft.Network/virtualNetworks/{vnet}/subnets/{subnet}")
        self.config['variables']['target_subnet_id'] = self.get_input(
            "Volume Subnet ID (get the SUBNET, not vNet ID.)", 
            current_subnet, 
            required=True
        )
    
    def configure_migration_settings(self, existing: Dict):
        """Configure migration-specific settings"""
        self.print_section("Migration Configuration")
        
        # Destination Volume
        current_vol_name = existing.get('variables', {}).get('target_volume_name', '')
        self.config['variables']['target_volume_name'] = self.get_input(
            "Destination Volume Name", 
            current_vol_name, 
            required=True
        )
        
        # Volume size (in bytes, displayed in GiB)
        current_usage = existing.get('variables', {}).get('target_usage_threshold', '')
        size_gib = int(current_usage) // (1024**3) if current_usage and current_usage.isdigit() else 100
        print(f"\n💡 Current size: {size_gib} GiB")
        print("   Note: GiB (Gibibytes) = 1024³ bytes, used for binary storage calculations")
        print("   Reference: 1 TiB = 1,024 GiB")
        new_size_gib = self.get_input(
            "Volume Size (GiB)", 
            str(size_gib), 
            required=True, 
            validate_func=self.validate_numeric
        )
        self.config['variables']['target_usage_threshold'] = str(int(new_size_gib) * 1024**3)
        
        # Protocol
        current_protocol = existing.get('variables', {}).get('target_protocol_types', 'CIFS')
        self.config['variables']['target_protocol_types'] = self.get_input(
            "Protocol Type (NFSv3/NFSv4.1/CIFS)", 
            current_protocol, 
            required=True, 
            validate_func=self.validate_protocol
        )
        
        # QoS Setting
        current_throughput = existing.get('variables', {}).get('target_throughput_mibps', '')
        
        # Determine current QoS type for display
        if current_throughput and current_throughput.strip():
            current_qos_display = current_throughput
        else:
            current_qos_display = "Auto"
        
        print("\n💡 QoS Options: Enter 'Auto' for automatic QoS, or a number (MiB/s) for manual QoS")
        qos_input = self.get_input(
            "QoS Setting (Auto or MiB/s number)", 
            current_qos_display, 
            required=True
        )
        
        # Process QoS input
        if qos_input.lower() == 'auto':
            self.config['variables']['target_throughput_mibps'] = ''
        elif qos_input.isdigit():
            self.config['variables']['target_throughput_mibps'] = qos_input
        else:
            # Try to parse as number
            try:
                float(qos_input)
                self.config['variables']['target_throughput_mibps'] = qos_input
            except ValueError:
                print("⚠️  Invalid QoS input. Using 'Auto' as fallback.")
                self.config['variables']['target_throughput_mibps'] = ''
        
        # Availability Zone configuration
        print("\n🌐 Availability Zone Configuration")
        current_zones = existing.get('variables', {}).get('target_zones', '["1"]')
        
        # Extract simple number from JSON array format for user-friendly display
        try:
            import json
            parsed_zones = json.loads(current_zones)
            if parsed_zones and len(parsed_zones) > 0:
                current_display = parsed_zones[0]
            else:
                current_display = ""  # Empty for no zone
        except (json.JSONDecodeError, TypeError):
            current_display = "1"  # Default fallback
        
        zone_input = self.get_input(
            "Availability Zone (enter just the number: 1, 2, 3, or press ENTER for no specific zone)",
            current_display,
            required=False
        )
        
        if zone_input.strip() == '':
            zones_value = '[]'
            print("💡 No specific availability zone - volume will be deployed regionally")
        elif zone_input in ['1', '2', '3']:
            zones_value = f'["{zone_input}"]'
            print(f"💡 Zone {zone_input} selected")
        else:
            print("⚠️  Availability zone must be 1, 2, or 3. Using default zone 1.")
            zones_value = '["1"]'
        
        self.config['variables']['target_zones'] = zones_value
        
        # Source cluster details
        print("\n📋 Source ONTAP Cluster Information")
        print("\n💡 Need help collecting this information from your ONTAP system?")
        print("   See: https://github.com/tvanroo/Migration-Assistant#ontap-volume-identification-and-cluster-information-collection-guide")
        print("   The guide provides step-by-step commands to gather all required details.")
        
        current_cluster = existing.get('variables', {}).get('source_cluster_name', '')
        self.config['variables']['source_cluster_name'] = self.get_input(
            "Source Cluster Name/Hostname, case-sensitive (Can be seen with 'cluster identity show' on ONTAP CLI)", 
            current_cluster, 
            required=True
        )
        
        current_server = existing.get('variables', {}).get('source_svm_name', '')
        self.config['variables']['source_svm_name'] = self.get_input(
            "Source SVM Name, case-sensitive (Can be seen with 'volume show -volume <volname> -fields vserver' on ONTAP CLI)", 
            current_server, 
            required=True
        )
        
        current_source_vol = existing.get('variables', {}).get('source_volume_name', '')
        self.config['variables']['source_volume_name'] = self.get_input(
            "Source Volume Name, case-sensitive (Can be seen with 'volume show' on ONTAP CLI)", 
            current_source_vol, 
            required=True
        )
        
        # Peer addresses
        peer_addresses = self.collect_peer_addresses(existing)
        self.config['variables']['source_peer_addresses'] = peer_addresses
        
        # Replication schedule - set to default hourly
        self.config['variables']['replication_schedule'] = 'Hourly'
    
    def configure_optional_settings(self, existing: Dict):
        """Configure optional settings"""
        self.print_section("Optional Settings")
        
        # API Version
        current_api_version = existing.get('variables', {}).get('azure_api_version', '2025-06-01')
        self.config['variables']['azure_api_version'] = self.get_input(
            "API Version", 
            current_api_version, 
            required=True
        )
        
        # Large volume support
        current_large_vol = existing.get('variables', {}).get('target_is_large_volume', 'false')
        large_vol = self.get_input(
            "Enable Large Volume Support (true/false)", 
            current_large_vol, 
            required=True
        )
        self.config['variables']['target_is_large_volume'] = large_vol.lower()
        
        # Network features - always use Standard
        self.config['variables']['target_network_features'] = 'Standard'
    
    def save_configuration(self):
        """Save configuration to file"""
        print(f"\n💾 Saving configuration to {self.config_file}")
        
        # Create backup if file exists
        if self.config_file.exists():
            # Create backup directory if it doesn't exist
            backup_dir = Path("config_backups")
            backup_dir.mkdir(exist_ok=True)
            
            # Create timestamped backup filename
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            backup_filename = f"config.backup_{timestamp}.yaml"
            backup_file = backup_dir / backup_filename
            
            # Copy the file to backup location
            import shutil
            shutil.copy2(self.config_file, backup_file)
            print(f"📁 Backup saved to {backup_file}")
        
        with open(self.config_file, 'w') as f:
            yaml.dump(self.config, f, default_flow_style=False, indent=2)
        
        print(f"✅ Configuration saved successfully!")
    
    def show_summary(self):
        """Show configuration summary"""
        self.print_section("Configuration Summary")
        
        protocol = self.config['variables'].get('target_protocol_types', 'Unknown')
        throughput = self.config['variables'].get('target_throughput_mibps', '')
        if throughput and throughput.strip():
            qos_type = f'Manual QoS ({throughput} MiB/s)'
        else:
            qos_type = 'Auto QoS'
        size_bytes = int(self.config['variables'].get('target_usage_threshold', '0'))
        size_gib = size_bytes // (1024**3) if size_bytes > 0 else 0
        
        print(f"🌐 Azure Region: {self.config['variables'].get('target_location')}")
        print(f"📁 Resource Group: {self.config['variables'].get('target_resource_group')}")
        print(f"🗄️  NetApp Account: {self.config['variables'].get('target_netapp_account')}")
        print(f"📊 Capacity Pool: {self.config['variables'].get('target_capacity_pool')}")
        print(f"💾 Destination Volume: {self.config['variables'].get('target_volume_name')} ({size_gib} GiB)")
        print(f"🔌 Protocol: {protocol}")
        print(f"⚡ QoS: {qos_type}")
        print(f"🔄 Replication: {self.config['variables'].get('replication_schedule')}")
        print(f"🖥️  Source Cluster: {self.config['variables'].get('source_cluster_name')}")
        print(f"📂 Source Volume: {self.config['variables'].get('source_volume_name')}")
        
        # Show peer addresses
        peer_addresses = self.config['variables'].get('source_peer_addresses', '')
        if peer_addresses:
            try:
                import json
                # Try to parse as JSON array
                peer_list = json.loads(peer_addresses)
                if isinstance(peer_list, list):
                    peer_display = ', '.join(peer_list)
                else:
                    peer_display = str(peer_addresses)
            except (json.JSONDecodeError, TypeError):
                peer_display = str(peer_addresses)
            print(f"🌐 Peer Addresses: {peer_display}")
        else:
            print(f"🌐 Peer Addresses: ⚠️  NOT CONFIGURED")
    
    def run_wizard(self):
        """Run the complete setup wizard"""
        self.print_header()
        
        # Load existing configuration
        existing = self.load_existing_config()
        
        try:
            # Step through configuration sections
            self.configure_azure_basics(existing)
            self.configure_service_principal(existing)
            self.configure_netapp_resources(existing)
            self.configure_migration_settings(existing)
            self.configure_optional_settings(existing)
            
            # Show summary
            self.show_summary()
            
            # Confirm and save
            print(f"\n{'=' * 60}")
            save_config = input("💾 Save this configuration? (Y/n): ").lower()
            
            if save_config == 'n' or save_config == 'no':
                print("❌ Configuration not saved.")
                return False
            else:
                # Default to saving (Y/n pattern - save unless explicitly declined)
                self.save_configuration()
                
                print(f"\n🎉 Setup completed successfully!")
                print(f"\nNext steps:")
                print(f"1. Run interactive workflow:")
                
                # Provide platform-specific instructions
                if platform.system() == "Windows":
                    # Check if Git Bash is available in the standard location
                    git_bash_path = Path("C:\\Program Files\\Git\\bin\\bash.exe")
                    if git_bash_path.exists():
                        print(f"   # For Windows PowerShell:")
                        print(f"   & \"C:\\Program Files\\Git\\bin\\bash.exe\" -c \"./anf_interactive.sh\"")
                        print(f"")
                        print(f"   # Or open Git Bash directly and run:")
                        print(f"   ./anf_interactive.sh")
                    else:
                        print(f"   # Install Git for Windows first, then run:")
                        print(f"   & \"C:\\Program Files\\Git\\bin\\bash.exe\" -c \"./anf_interactive.sh\"")
                        print(f"   # Or use Git Bash: ./anf_interactive.sh")
                else:
                    # Linux/macOS instructions
                    print(f"   ./anf_interactive.sh")
                
                print(f"")
                
                return True
                
        except KeyboardInterrupt:
            print(f"\n\n❌ Setup cancelled by user.")
            return False
        except Exception as e:
            print(f"\n❌ Error during setup: {e}")
            return False

def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(
        description="Azure NetApp Files Migration Assistant - Setup Wizard",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python3 setup_wizard.py                    # Use default config.yaml
  python3 setup_wizard.py -c production.yaml # Use custom config file
  python3 setup_wizard.py --config test.yaml # Use custom config file
        """
    )
    parser.add_argument(
        '--config', '-c',
        default='config.yaml',
        help='Configuration file to create/modify (default: config.yaml)'
    )
    
    args = parser.parse_args()
    
    wizard = ANFSetupWizard(args.config)
    success = wizard.run_wizard()
    return 0 if success else 1

if __name__ == "__main__":
    exit(main())
