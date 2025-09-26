#!/usr/bin/env python3
"""
Simple YAML validation script
"""
import sys
import yaml

def main():
    if len(sys.argv) != 2:
        print("Usage: python validate-yaml.py <file>")
        sys.exit(1)
    
    config_file = sys.argv[1]
    
    try:
        with open(config_file, 'r', encoding='utf-8') as f:
            yaml.safe_load(f)
        sys.exit(0)  # Success
    except Exception:
        sys.exit(1)  # Failure

if __name__ == "__main__":
    main()