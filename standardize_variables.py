#!/usr/bin/env python3
"""
Variable Name Standardization Script
Updates all variable references across the Migration Assistant codebase
"""

import re
import os
from pathlib import Path

# Variable mapping from old names to new names
VARIABLE_MAPPING = {
    # Authentication & Azure Configuration
    'tenant': 'azure_tenant_id',
    'subscriptionId': 'azure_subscription_id',
    'appId': 'azure_app_id',
    'appIdPassword': 'azure_app_secret',
    'api-version': 'azure_api_version',
    'apicloudurl': 'azure_api_base_url',
    'authcloudurl': 'azure_auth_base_url',
    
    # Target Azure NetApp Files Configuration
    'resourceGroupName': 'target_resource_group',
    'location': 'target_location',
    'accountName': 'target_netapp_account',
    'poolName': 'target_capacity_pool',
    'volumeName': 'target_volume_name',
    'serviceLevel': 'target_service_level',
    'volsubnetId': 'target_subnet_id',
    'networkFeatures': 'target_network_features',
    'isLargeVolume': 'target_is_large_volume',
    'volusageThreshold': 'target_usage_threshold',
    'volthroughputMibps': 'target_throughput_mibps',
    'volumeProtocolTypes': 'target_protocol_types',
    
    # Source NetApp Configuration
    'maclusterName': 'source_cluster_name',
    'maexternalHostName': 'source_hostname',
    'mapeerAddresses': 'source_peer_addresses',
    'maserverName': 'source_server_name',
    'mavolumeName': 'source_volume_name',
    
    # Replication Configuration
    'replicationSchedule': 'replication_schedule',
}

def update_file_variables(file_path: Path, dry_run: bool = True):
    """Update variable references in a single file"""
    print(f"\n{'='*60}")
    print(f"Processing: {file_path}")
    print(f"{'='*60}")
    
    try:
        with open(file_path, 'r') as f:
            content = f.read()
        
        original_content = content
        changes_made = []
        
        # Update variable references in different contexts
        for old_var, new_var in VARIABLE_MAPPING.items():
            # Pattern 1: {{variable}} in shell scripts
            pattern1 = f'{{{{\\s*{re.escape(old_var)}\\s*}}}}'
            replacement1 = f'{{{{{new_var}}}}}'
            if re.search(pattern1, content):
                content = re.sub(pattern1, replacement1, content)
                changes_made.append(f"  {{{{{{old_var}}}}}} → {{{{{{new_var}}}}}}")
            
            # Pattern 2: YAML keys (at start of line or after whitespace)
            pattern2 = f'^(\\s*){re.escape(old_var)}(\\s*:)'
            replacement2 = f'\\g<1>{new_var}\\g<2>'
            if re.search(pattern2, content, re.MULTILINE):
                content = re.sub(pattern2, replacement2, content, flags=re.MULTILINE)
                changes_made.append(f"  YAML key: {old_var}: → {new_var}:")
            
            # Pattern 3: Python dictionary/variable references
            pattern3 = f"['\"]\\s*{re.escape(old_var)}\\s*['\"]"
            replacement3 = f"'{new_var}'"
            if re.search(pattern3, content):
                content = re.sub(pattern3, replacement3, content)
                changes_made.append(f"  Python string: '{old_var}' → '{new_var}'")
            
            # Pattern 4: get_config_value calls
            pattern4 = f'get_config_value\\s*\\(\\s*["\']\\s*{re.escape(old_var)}\\s*["\']\\s*\\)'
            replacement4 = f'get_config_value("{new_var}")'
            if re.search(pattern4, content):
                content = re.sub(pattern4, replacement4, content)
                changes_made.append(f"  Config call: get_config_value('{old_var}') → get_config_value('{new_var}')")
        
        if changes_made:
            print(f"✅ Found {len(changes_made)} variable references to update:")
            for change in changes_made:
                print(change)
            
            if not dry_run:
                with open(file_path, 'w') as f:
                    f.write(content)
                print(f"✅ File updated successfully")
            else:
                print(f"🔍 DRY RUN - No changes written")
        else:
            print("ℹ️  No variable references found to update")
            
    except Exception as e:
        print(f"❌ Error processing {file_path}: {e}")

def main():
    """Main function to update all files"""
    print("🔄 Variable Name Standardization Script")
    print("=" * 50)
    
    # Get current directory
    script_dir = Path('.')
    
    # Files to update
    files_to_update = [
        'anf_workflow.sh',
        'anf_interactive.sh', 
        'anf_runner.sh',
        'setup_wizard.py',
        'validate_variables.py'
    ]
    
    print(f"Variable mapping ({len(VARIABLE_MAPPING)} variables):")
    for old, new in VARIABLE_MAPPING.items():
        print(f"  {old} → {new}")
    
    # Ask user for confirmation
    print(f"\nFiles to update: {', '.join(files_to_update)}")
    response = input("\nRun in dry-run mode first? (y/N): ").strip().lower()
    dry_run = response in ['y', 'yes']
    
    if dry_run:
        print("\n🔍 RUNNING IN DRY-RUN MODE - No files will be modified")
    else:
        print("\n✏️  RUNNING IN UPDATE MODE - Files will be modified")
    
    # Process each file
    for filename in files_to_update:
        file_path = script_dir / filename
        if file_path.exists():
            update_file_variables(file_path, dry_run=dry_run)
        else:
            print(f"⚠️  File not found: {filename}")
    
    print(f"\n{'='*60}")
    print("🎉 Variable standardization complete!")
    
    if dry_run:
        print("🔄 Run again with 'N' to apply changes")
    else:
        print("✅ All files have been updated with standardized variable names")

if __name__ == "__main__":
    main()
