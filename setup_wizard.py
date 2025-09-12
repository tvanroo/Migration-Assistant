#!/usr/bin/env python3
"""
Azure NetApp Files Migration Assistant - Interactive Setup Wizard
Walks through configuring all required variables step by step
"""

import os
import re
import yaml
import getpass
from pathlib import Path
from typing import Dict, Any, Optional

class ANFSetupWizard:
    """Interactive wizard for setting up ANF Migration Assistant"""
    
    def __init__(self):
        self.config = {
            'variables': {},
            'secrets': {}
        }
        self.config_file = Path("config.yaml")
        
    def print_header(self):
        """Print welcome header"""
        print("=" * 80)
        print("🚀 Azure NetApp Files Migration Assistant - Setup Wizard")
        print("=" * 80)
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
        print("💡 Enter the IP address(es) of your ONTAP cluster's intercluster LIFs")
        print("   You can find these with: 'network interface show -role intercluster'")
        print("   Enter one IP address at a time. Press ENTER with no input when done.\n")
        
        # Parse existing peer addresses
        current_peers = existing.get('variables', {}).get('mapeerAddresses', '')
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
        current_tenant = existing.get('variables', {}).get('tenant', '')
        self.config['variables']['tenant'] = self.get_input(
            "Azure AD Tenant ID", 
            current_tenant, 
            required=True, 
            validate_func=self.validate_uuid
        )
        
        # Subscription ID
        current_sub = existing.get('variables', {}).get('subscriptionId', '')
        self.config['variables']['subscriptionId'] = self.get_input(
            "Azure Subscription ID", 
            current_sub, 
            required=True, 
            validate_func=self.validate_uuid
        )
        
        # Location
        current_location = existing.get('variables', {}).get('location', '')
        self.config['variables']['location'] = self.get_input(
            "Azure Region (e.g., eastus, westus2)", 
            current_location, 
            required=True, 
            validate_func=self.validate_azure_region
        )
        
        # Resource Group
        current_rg = existing.get('variables', {}).get('resourceGroupName', '')
        self.config['variables']['resourceGroupName'] = self.get_input(
            "Resource Group Name", 
            current_rg, 
            required=True
        )
    
    def configure_service_principal(self, existing: Dict):
        """Configure service principal authentication"""
        self.print_section("Service Principal Authentication")
        print("💡 You need a service principal with NetApp contributor permissions")
        
        # App ID
        current_app_id = existing.get('variables', {}).get('appId', '')
        self.config['variables']['appId'] = self.get_input(
            "Service Principal Application ID", 
            current_app_id, 
            required=True, 
            validate_func=self.validate_uuid
        )
        
        # App Secret
        current_secret = existing.get('secrets', {}).get('appIdPassword', '')
        if current_secret and current_secret != 'CHANGE_ME':
            print(f"✅ Service principal secret already configured")
            keep_secret = input("Keep existing secret? (Y/n): ").lower()
            if keep_secret == 'y' or keep_secret == '':
                self.config['secrets']['appIdPassword'] = current_secret
            else:
                self.config['secrets']['appIdPassword'] = self.get_input(
                    "Service Principal Secret", 
                    "", 
                    required=True, 
                    secret=True
                )
        else:
            self.config['secrets']['appIdPassword'] = self.get_input(
                "Service Principal Secret", 
                "", 
                required=True, 
                secret=True
            )
        
        # API Endpoints - Auth URL with options
        current_auth_url = existing.get('variables', {}).get('authcloudurl', '')
        
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
            self.config['variables']['authcloudurl'] = 'https://login.microsoftonline.com/'
        elif auth_choice == '2' or auth_choice.lower() == 'government':
            self.config['variables']['authcloudurl'] = 'https://login.microsoftonline.us/'
        elif auth_choice == '3' or auth_choice.lower() == 'other':
            self.config['variables']['authcloudurl'] = self.get_input(
                "Custom Auth URL", 
                current_auth_url, 
                required=True
            )
        else:
            # Default to commercial if invalid choice
            self.config['variables']['authcloudurl'] = 'https://login.microsoftonline.com/'
        
        # API URL - standard for all regions
        current_api_url = existing.get('variables', {}).get('apicloudurl', '')
        self.config['variables']['apicloudurl'] = self.get_input(
            "Azure Management API URL", 
            current_api_url, 
            required=True
        )
    
    def configure_netapp_resources(self, existing: Dict):
        """Configure NetApp Files resources"""
        self.print_section("Azure NetApp Files Resources")
        
        # Account Name
        current_account = existing.get('variables', {}).get('accountName', '')
        self.config['variables']['accountName'] = self.get_input(
            "NetApp Account Name", 
            current_account, 
            required=True
        )
        
        # Pool Name
        current_pool = existing.get('variables', {}).get('poolName', '')
        self.config['variables']['poolName'] = self.get_input(
            "Capacity Pool Name", 
            current_pool, 
            required=True
        )
        
        # Service Level
        current_service_level = existing.get('variables', {}).get('serviceLevel', '')
        self.config['variables']['serviceLevel'] = self.get_input(
            "Service Level (Standard/Premium/Ultra)", 
            current_service_level, 
            required=True, 
            validate_func=self.validate_service_level
        )
        
        # Volume subnet
        current_subnet = existing.get('variables', {}).get('volsubnetId', '')
        print("\n💡 Volume subnet format: /subscriptions/{sub-id}/resourceGroups/{rg}/providers/Microsoft.Network/virtualNetworks/{vnet}/subnets/{subnet}")
        self.config['variables']['volsubnetId'] = self.get_input(
            "Volume Subnet ID", 
            current_subnet, 
            required=True
        )
    
    def configure_migration_settings(self, existing: Dict):
        """Configure migration-specific settings"""
        self.print_section("Migration Configuration")
        
        # Destination Volume
        current_vol_name = existing.get('variables', {}).get('volumeName', '')
        self.config['variables']['volumeName'] = self.get_input(
            "Destination Volume Name", 
            current_vol_name, 
            required=True
        )
        
        # Volume size (in bytes)
        current_usage = existing.get('variables', {}).get('volusageThreshold', '')
        size_gb = int(current_usage) // (1024**3) if current_usage and current_usage.isdigit() else 100
        print(f"\n💡 Current size: {size_gb} GB")
        new_size_gb = self.get_input(
            "Volume Size (GB)", 
            str(size_gb), 
            required=True, 
            validate_func=self.validate_numeric
        )
        self.config['variables']['volusageThreshold'] = str(int(new_size_gb) * 1024**3)
        
        # Protocol
        current_protocol = existing.get('variables', {}).get('volumeProtocolTypes', '')
        self.config['variables']['volumeProtocolTypes'] = self.get_input(
            "Protocol Type (NFSv3/NFSv4.1/CIFS)", 
            current_protocol, 
            required=True, 
            validate_func=self.validate_protocol
        )
        
        # QoS Setting
        current_throughput = existing.get('variables', {}).get('volthroughputMibps', '')
        
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
            self.config['variables']['volthroughputMibps'] = ''
        elif qos_input.isdigit():
            self.config['variables']['volthroughputMibps'] = qos_input
        else:
            # Try to parse as number
            try:
                float(qos_input)
                self.config['variables']['volthroughputMibps'] = qos_input
            except ValueError:
                print("⚠️  Invalid QoS input. Using 'Auto' as fallback.")
                self.config['variables']['volthroughputMibps'] = ''
        
        # Source cluster details
        print("\n📋 Source ONTAP Cluster Information")
        
        current_cluster = existing.get('variables', {}).get('maclusterName', '')
        self.config['variables']['maclusterName'] = self.get_input(
            "Source Cluster Name", 
            current_cluster, 
            required=True
        )
        
        current_hostname = existing.get('variables', {}).get('maexternalHostName', '')
        self.config['variables']['maexternalHostName'] = self.get_input(
            "Source External Host Name/IP", 
            current_hostname, 
            required=True
        )
        
        current_server = existing.get('variables', {}).get('maserverName', '')
        self.config['variables']['maserverName'] = self.get_input(
            "Source Server/SVM Name", 
            current_server, 
            required=True
        )
        
        current_source_vol = existing.get('variables', {}).get('mavolumeName', '')
        self.config['variables']['mavolumeName'] = self.get_input(
            "Source Volume Name", 
            current_source_vol, 
            required=True
        )
        
        # Peer addresses
        peer_addresses = self.collect_peer_addresses(existing)
        self.config['variables']['mapeerAddresses'] = peer_addresses
        
        # Replication schedule
        current_schedule = existing.get('variables', {}).get('replicationSchedule', '')
        self.config['variables']['replicationSchedule'] = self.get_input(
            "Replication Schedule (Hourly/Daily/Weekly)", 
            current_schedule, 
            required=True, 
            validate_func=self.validate_replication_schedule
        )
    
    def configure_optional_settings(self, existing: Dict):
        """Configure optional settings"""
        self.print_section("Optional Settings")
        
        # API Version
        current_api_version = existing.get('variables', {}).get('api-version', '')
        self.config['variables']['api-version'] = self.get_input(
            "API Version", 
            current_api_version, 
            required=True
        )
        
        # Large volume support
        current_large_vol = existing.get('variables', {}).get('isLargeVolume', '')
        large_vol = self.get_input(
            "Enable Large Volume Support (true/false)", 
            current_large_vol, 
            required=True
        )
        self.config['variables']['isLargeVolume'] = large_vol.lower()
        
        # Network features - always use Standard
        self.config['variables']['networkFeatures'] = 'Standard'
    
    def save_configuration(self):
        """Save configuration to file"""
        print(f"\n💾 Saving configuration to {self.config_file}")
        
        # Create backup if file exists
        if self.config_file.exists():
            backup_file = self.config_file.with_suffix('.backup.yaml')
            self.config_file.rename(backup_file)
            print(f"📁 Backup saved to {backup_file}")
        
        with open(self.config_file, 'w') as f:
            yaml.dump(self.config, f, default_flow_style=False, indent=2)
        
        print(f"✅ Configuration saved successfully!")
    
    def show_summary(self):
        """Show configuration summary"""
        self.print_section("Configuration Summary")
        
        protocol = self.config['variables'].get('volumeProtocolTypes', 'Unknown')
        throughput = self.config['variables'].get('volthroughputMibps', '')
        if throughput and throughput.strip():
            qos_type = f'Manual QoS ({throughput} MiB/s)'
        else:
            qos_type = 'Auto QoS'
        size_bytes = int(self.config['variables'].get('volusageThreshold', '0'))
        size_gb = size_bytes // (1024**3) if size_bytes > 0 else 0
        
        print(f"🌐 Azure Region: {self.config['variables'].get('location')}")
        print(f"📁 Resource Group: {self.config['variables'].get('resourceGroupName')}")
        print(f"🗄️  NetApp Account: {self.config['variables'].get('accountName')}")
        print(f"📊 Capacity Pool: {self.config['variables'].get('poolName')}")
        print(f"💾 Destination Volume: {self.config['variables'].get('volumeName')} ({size_gb} GB)")
        print(f"🔌 Protocol: {protocol}")
        print(f"⚡ QoS: {qos_type}")
        print(f"🔄 Replication: {self.config['variables'].get('replicationSchedule')}")
        print(f"🖥️  Source Cluster: {self.config['variables'].get('maclusterName')}")
        print(f"📂 Source Volume: {self.config['variables'].get('mavolumeName')}")
        
        # Show peer addresses
        peer_addresses = self.config['variables'].get('mapeerAddresses', '')
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
                print(f"1. Validate: ./anf_runner.sh validate")
                print(f"2. Run workflow: ./anf_runner.sh generate")
                print(f"3. Check logs: tail -f anf_migration.log")
                
                return True
                
        except KeyboardInterrupt:
            print(f"\n\n❌ Setup cancelled by user.")
            return False
        except Exception as e:
            print(f"\n❌ Error during setup: {e}")
            return False

def main():
    """Main entry point"""
    wizard = ANFSetupWizard()
    success = wizard.run_wizard()
    return 0 if success else 1

if __name__ == "__main__":
    exit(main())
