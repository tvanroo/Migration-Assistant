#!/usr/bin/env python3
import yaml
import sys

def main():
    config_file = sys.argv[1]
    print(f"Trying to read {config_file}")
    
    try:
        with open(config_file) as f:
            config = yaml.safe_load(f)
            print("Successfully loaded YAML!")
            print("Contents:", config)
            
            if 'variables' in config:
                print("\nVariables:")
                for key, value in config['variables'].items():
                    print(f"  {key}: {value}")
            
            if 'secrets' in config:
                print("\nSecrets:")
                for key in config['secrets'].keys():
                    print(f"  {key}: (hidden)")
    except Exception as e:
        print(f"Error loading YAML: {e}")
        return 1
        
    return 0

if __name__ == "__main__":
    exit(main())