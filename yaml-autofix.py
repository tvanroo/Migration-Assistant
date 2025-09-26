#!/usr/bin/env python3
"""
YAML Auto-Remediation Tool
Automatically fixes common Windows YAML editing issues
"""

import os
import sys
import yaml
import tempfile
import shutil
from pathlib import Path

def auto_fix_yaml_file(config_file):
    """
    Automatically fix common YAML issues that occur when editing on Windows
    Returns True if file was fixed and is now valid, False if unfixable
    """
    print(f"Auto-fixing YAML file: {config_file}")
    
    # Try to read the file with different encodings
    file_content = None
    original_encoding = None
    encodings_to_try = ['utf-8', 'utf-8-sig', 'latin-1', 'cp1252', 'iso-8859-1']
    
    for encoding in encodings_to_try:
        try:
            with open(config_file, 'r', encoding=encoding) as f:
                file_content = f.read()
            original_encoding = encoding
            print(f"Successfully read file with encoding: {encoding}")
            break
        except (UnicodeDecodeError, UnicodeError):
            continue
    
    if file_content is None:
        print("ERROR: Could not read file with any encoding")
        return False
    
    # Track what we fixed
    fixes_applied = []
    
    # Fix 1: Remove BOM (Byte Order Mark)
    if file_content.startswith('\ufeff'):
        file_content = file_content[1:]
        fixes_applied.append("Removed BOM (Byte Order Mark)")
    
    # Fix 2: Convert Windows line endings to Unix
    if '\r\n' in file_content:
        file_content = file_content.replace('\r\n', '\n')
        fixes_applied.append("Converted CRLF to LF line endings")
    
    # Fix 3: Replace tabs with spaces (assuming 2-space indentation)
    if '\t' in file_content:
        # Count leading tabs to determine indentation level
        lines = file_content.split('\n')
        fixed_lines = []
        
        for line in lines:
            if line.startswith('\t'):
                # Replace leading tabs with 2 spaces per tab
                leading_tabs = len(line) - len(line.lstrip('\t'))
                spaces = '  ' * leading_tabs  # 2 spaces per tab level
                fixed_line = spaces + line.lstrip('\t')
                fixed_lines.append(fixed_line)
            else:
                fixed_lines.append(line)
        
        file_content = '\n'.join(fixed_lines)
        fixes_applied.append("Replaced tabs with spaces")
    
    # Fix 4: Ensure proper spacing after colons
    lines = file_content.split('\n')
    fixed_lines = []
    
    for line in lines:
        # Look for 'key:value' patterns without space after colon
        if ':' in line and not line.strip().startswith('#'):
            # Find colon positions
            parts = line.split(':')
            if len(parts) >= 2:
                # Check if there's no space after colon and there's content
                key_part = parts[0]
                value_part = ':'.join(parts[1:])  # Handle multiple colons
                
                # If value starts immediately after colon without space
                if value_part and not value_part.startswith(' ') and not value_part.startswith('\n'):
                    fixed_line = key_part + ': ' + value_part
                    fixed_lines.append(fixed_line)
                    if "Fixed colon spacing" not in fixes_applied:
                        fixes_applied.append("Fixed colon spacing")
                else:
                    fixed_lines.append(line)
            else:
                fixed_lines.append(line)
        else:
            fixed_lines.append(line)
    
    file_content = '\n'.join(fixed_lines)
    
    # Test if the fixed content is valid YAML
    try:
        yaml.safe_load(file_content)
        print("YAML is valid after fixes")
    except yaml.YAMLError as e:
        print(f"ERROR: YAML still invalid after auto-fixes: {e}")
        return False
    
    # Create backup of original file
    backup_file = f"{config_file}.backup"
    if os.path.exists(config_file):
        shutil.copy2(config_file, backup_file)
        print(f"Created backup: {backup_file}")
    
    # Write the fixed content
    try:
        with open(config_file, 'w', encoding='utf-8', newline='\n') as f:
            f.write(file_content)
        print(f"Fixed file saved as UTF-8")
        
        if fixes_applied:
            print("Applied fixes:")
            for fix in fixes_applied:
                print(f"  - {fix}")
        else:
            print("No fixes needed - file was already valid")
        
        return True
        
    except Exception as e:
        print(f"ERROR: Failed to write fixed file: {e}")
        # Restore backup if write failed
        if os.path.exists(backup_file):
            shutil.copy2(backup_file, config_file)
            print("Restored original file from backup")
        return False

def main():
    if len(sys.argv) != 2:
        print("Usage: python yaml-autofix.py <config-file>")
        sys.exit(1)
    
    config_file = sys.argv[1]
    
    if not os.path.exists(config_file):
        print(f"ERROR: File not found: {config_file}")
        sys.exit(1)
    
    success = auto_fix_yaml_file(config_file)
    
    if success:
        print("\nYAML file has been automatically fixed!")
        print("File should now work with the migration assistant")
    else:
        print("\nCould not automatically fix the YAML file")
        print("You may need to manually fix syntax errors or run the setup wizard")
    
    return 0 if success else 1

if __name__ == "__main__":
    exit(main())