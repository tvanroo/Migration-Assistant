#!/usr/bin/env python3
import yaml
import os.path
import sys

def main():
    if len(sys.argv) < 2:
        print("Usage: python test_path.py <config_file>")
        return 1
        
    config_file = sys.argv[1]
    config_path = os.path.normpath(config_file)
    
    print(f"Original path: {config_file}")
    print(f"Normalized path: {config_path}")
    
    try:
        with open(config_path, encoding='utf-8') as f:
            config = yaml.safe_load(f)
            print("YAML loaded successfully!")
            
            if 'variables' in config:
                print(f"Variables section found with {len(config['variables'])} entries")
                
                # Test a few keys
                test_keys = ['target_location', 'target_resource_group']
                for key in test_keys:
                    value = config['variables'].get(key, '')
                    print(f"{key}: '{value}'")
            else:
                print("No variables section found!")
                
    except Exception as e:
        print(f"Error: {e}")
        return 1
        
    return 0

if __name__ == "__main__":
    sys.exit(main())