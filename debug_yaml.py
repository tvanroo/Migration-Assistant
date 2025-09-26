#!/usr/bin/env python3
import sys
import os
import yaml
import binascii

def analyze_file(filepath):
    print(f"Analyzing file: {filepath}")
    print(f"File exists: {os.path.exists(filepath)}")
    
    if not os.path.exists(filepath):
        return
        
    print(f"File size: {os.path.getsize(filepath)} bytes")
    
    # Try different encodings to detect issues
    encodings = ['utf-8', 'utf-8-sig', 'latin-1', 'cp1252']
    
    for encoding in encodings:
        try:
            with open(filepath, 'r', encoding=encoding) as f:
                content = f.read()
                print(f"\nSuccessfully read with encoding: {encoding}")
                print(f"File length: {len(content)} characters")
                
                # Check for BOM
                if content.startswith('\ufeff'):
                    print("WARNING: File starts with UTF-8 BOM")
                
                # Check line endings
                if '\r\n' in content:
                    print("Line endings: CRLF (Windows)")
                elif '\n' in content:
                    print("Line endings: LF (Unix)")
                else:
                    print("No line breaks detected")
                
                # Look at first few bytes
                with open(filepath, 'rb') as binary_file:
                    bytes_data = binary_file.read(20)
                    print(f"First 20 bytes (hex): {binascii.hexlify(bytes_data).decode()}")
                
                # Try to parse as YAML
                try:
                    yaml_data = yaml.safe_load(content)
                    print("✅ Valid YAML: Successfully parsed")
                    
                    # Check structure
                    if 'variables' in yaml_data:
                        print(f"Found 'variables' section with {len(yaml_data['variables'])} entries")
                        
                        # Check a few important keys
                        var_dict = yaml_data['variables']
                        print("\nKey checks:")
                        for key in ['target_location', 'target_resource_group', 'target_netapp_account']:
                            if key in var_dict:
                                print(f"  ✓ '{key}' = '{var_dict[key]}'")
                            else:
                                print(f"  ✗ '{key}' not found")
                    else:
                        print("❌ No 'variables' section found")
                    
                    if 'secrets' in yaml_data:
                        print(f"Found 'secrets' section with {len(yaml_data['secrets'])} entries")
                    else:
                        print("No 'secrets' section found")
                    
                except yaml.YAMLError as e:
                    print(f"❌ Invalid YAML: {e}")
                
                break
        
        except UnicodeDecodeError:
            print(f"Cannot read with encoding {encoding}")
            continue
        except Exception as e:
            print(f"Error reading file with {encoding}: {e}")
            continue

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python debug_yaml.py <config_file>")
        sys.exit(1)
        
    analyze_file(sys.argv[1])