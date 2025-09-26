#!/usr/bin/env python3
"""
YAML Config File Diagnostic Tool
Helps identify issues with manually edited YAML configuration files
"""

import sys
import yaml
import os
from pathlib import Path

def diagnose_yaml_file(config_file):
    """Diagnose YAML file issues and provide specific error messages"""
    print("🔍 YAML Configuration File Diagnostic")
    print("=" * 50)
    print(f"📁 File: {config_file}")
    
    # Check if file exists
    if not os.path.exists(config_file):
        print("❌ ERROR: File does not exist")
        return False
    
    # Check file size
    file_size = os.path.getsize(config_file)
    print(f"📏 File size: {file_size} bytes")
    
    if file_size == 0:
        print("❌ ERROR: File is empty")
        return False
    
    # Check file encoding
    encodings_to_try = ['utf-8', 'utf-8-sig', 'latin-1', 'cp1252']
    file_content = None
    successful_encoding = None
    
    for encoding in encodings_to_try:
        try:
            with open(config_file, 'r', encoding=encoding) as f:
                file_content = f.read()
            successful_encoding = encoding
            break
        except UnicodeDecodeError as e:
            print(f"⚠️  Encoding {encoding}: {e}")
            continue
    
    if file_content is None:
        print("❌ ERROR: Could not read file with any common encoding")
        return False
    
    print(f"✅ Successfully read with encoding: {successful_encoding}")
    
    # Check for BOM (Byte Order Mark)
    if file_content.startswith('\ufeff'):
        print("⚠️  WARNING: File has BOM (Byte Order Mark) - this can cause issues")
        file_content = file_content[1:]  # Remove BOM
    
    # Check line endings
    if '\r\n' in file_content:
        line_ending = "Windows (CRLF)"
    elif '\n' in file_content:
        line_ending = "Unix (LF)"
    elif '\r' in file_content:
        line_ending = "Mac Classic (CR)"
    else:
        line_ending = "No line endings found"
    
    print(f"📝 Line endings: {line_ending}")
    
    # Show first few lines for inspection
    lines = file_content.split('\n')[:10]
    print(f"\n📋 First {min(10, len(lines))} lines:")
    for i, line in enumerate(lines, 1):
        # Show invisible characters
        display_line = line.replace('\t', '→').replace(' ', '·')
        print(f"  {i:2d}: {display_line}")
    
    # Try to parse YAML
    print(f"\n🔧 YAML Parsing Test:")
    try:
        config_data = yaml.safe_load(file_content)
        print("✅ YAML parsing successful!")
        
        # Check structure
        if not isinstance(config_data, dict):
            print("⚠️  WARNING: Root should be a dictionary/object")
            return False
            
        # Check for required sections
        if 'variables' not in config_data:
            print("⚠️  WARNING: Missing 'variables' section")
        if 'secrets' not in config_data:
            print("⚠️  WARNING: Missing 'secrets' section")
            
        print(f"📊 Found {len(config_data)} top-level sections:")
        for key in config_data.keys():
            if isinstance(config_data[key], dict):
                count = len(config_data[key])
                print(f"   - {key}: {count} items")
            else:
                print(f"   - {key}: {type(config_data[key]).__name__}")
        
        return True
        
    except yaml.YAMLError as e:
        print(f"❌ YAML Parsing Error:")
        print(f"   {e}")
        
        # Try to give more specific advice
        error_str = str(e).lower()
        if 'tab' in error_str:
            print("\n💡 COMMON FIX: Replace all tab characters with spaces")
            print("   Most YAML parsers don't allow tabs for indentation")
        elif 'indent' in error_str:
            print("\n💡 COMMON FIX: Check your indentation")
            print("   YAML is very sensitive to indentation - use spaces, not tabs")
            print("   Each level should be indented by 2 or 4 spaces consistently")
        elif 'duplicate' in error_str:
            print("\n💡 COMMON FIX: Remove duplicate keys")
            print("   Each key can only appear once at the same level")
        elif 'mapping' in error_str or 'sequence' in error_str:
            print("\n💡 COMMON FIX: Check your YAML structure")
            print("   Make sure colons have spaces after them: 'key: value'")
            print("   Make sure lists use proper format: '- item'")
        
        return False
    
    except Exception as e:
        print(f"❌ Unexpected error: {e}")
        return False

def main():
    if len(sys.argv) != 2:
        print("Usage: python yaml-diagnostic.py <config-file>")
        print("\nExamples:")
        print("  python yaml-diagnostic.py config.yaml")
        print("  python yaml-diagnostic.py production.yaml")
        sys.exit(1)
    
    config_file = sys.argv[1]
    success = diagnose_yaml_file(config_file)
    
    print("\n" + "=" * 50)
    if success:
        print("🎉 Configuration file is valid!")
        print("✅ Should work with the migration assistant")
    else:
        print("💡 Fix the issues above and try again")
        print("🔧 Or run the setup wizard to generate a fresh config file")
    print("=" * 50)
    
    return 0 if success else 1

if __name__ == "__main__":
    exit(main())