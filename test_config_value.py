#!/usr/bin/env python3
import sys
import yaml

def get_config_value(config_file, key):
    """Recreate the bash script's get_config_value function"""
    try:
        with open(config_file, 'r', encoding='utf-8') as f:
            config = yaml.safe_load(f)
            all_vars = {**config.get('variables', {}), **config.get('secrets', {})}
            return all_vars.get(key, '')
    except Exception as e:
        print(f"Error: {e}")
        return ''

def main():
    if len(sys.argv) != 2:
        print("Usage: python test_config_value.py <config_file>")
        sys.exit(1)
    
    config_file = sys.argv[1]
    
    # Test with keys that should exist in the config
    keys_to_test = [
        'target_location',
        'target_resource_group',
        'target_netapp_account',
        'target_capacity_pool',
        'target_volume_name',
        'replication_schedule',
        'source_cluster_name'
    ]
    
    print(f"Testing config file: {config_file}\n")
    
    for key in keys_to_test:
        value = get_config_value(config_file, key)
        print(f"{key}: '{value}'")
    
    return 0

if __name__ == "__main__":
    sys.exit(main())