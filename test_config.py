#!/usr/bin/env python
import yaml
import os

print("Current working directory:", os.getcwd())
print("Script location:", os.path.dirname(os.path.abspath(__file__)))

config_file = "config.yaml"
print(f"Looking for config file: {config_file}")
print(f"Config file exists: {os.path.exists(config_file)}")

if os.path.exists(config_file):
    try:
        with open(config_file, 'r') as f:
            config = yaml.safe_load(f)
            print("Config loaded successfully!")
            print("Variables section:", list(config.get('variables', {}).keys())[:5])
    except Exception as e:
        print(f"Error loading config: {e}")
else:
    # Try absolute path
    abs_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "config.yaml")
    print(f"Trying absolute path: {abs_path}")
    print(f"Absolute path exists: {os.path.exists(abs_path)}")