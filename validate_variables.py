#!/usr/bin/env python3
"""
Validate that all required variables for ANF Migration Assistant are present in config.yaml
"""
import yaml
import sys
import re
from pathlib import Path

def extract_variables_from_scripts():
    """Extract all {{variable}} references from script files"""
    script_dir = Path('.')
    variables = set()
    
    # Find all shell script files
    script_files = list(script_dir.glob('*.sh'))
    
    for script_file in script_files:
        try:
            with open(script_file, 'r') as f:
                content = f.read()
                # Find all {{variable}} patterns
                matches = re.findall(r'\{\{([^}]+)\}\}', content)
                for match in matches:
                    # Skip template syntax like {{' + key + '}}
                    if "'" not in match and '"' not in match and '+' not in match:
                        variables.add(match)
        except Exception as e:
            print(f"Warning: Could not read {script_file}: {e}")
    
    return variables

def load_config_variables():
    """Load all variables from config.yaml"""
    try:
        with open('config.yaml', 'r') as f:
            config = yaml.safe_load(f)
            variables = config.get('variables', {})
            secrets = config.get('secrets', {})
            return {**variables, **secrets}
    except Exception as e:
        print(f"Error loading config.yaml: {e}")
        return {}

def main():
    print("🔍 ANF Migration Assistant - Variable Validation")
    print("=" * 50)
    
    # Extract variables from scripts
    script_variables = extract_variables_from_scripts()
    print(f"Found {len(script_variables)} unique variables in scripts")
    
    # Load config variables
    config_variables = load_config_variables()
    print(f"Found {len(config_variables)} variables in config.yaml")
    
    print("\n📋 Variable Analysis:")
    print("-" * 30)
    
    missing_variables = []
    present_variables = []
    
    for var in sorted(script_variables):
        if var in config_variables:
            value = config_variables[var]
            # Hide sensitive values
            if 'password' in var.lower() or 'secret' in var.lower() or 'key' in var.lower():
                display_value = "***HIDDEN***"
            else:
                display_value = str(value)[:50] + ("..." if len(str(value)) > 50 else "")
            
            print(f"✅ {var}: {display_value}")
            present_variables.append(var)
        else:
            print(f"❌ {var}: MISSING")
            missing_variables.append(var)
    
    print(f"\n📊 Summary:")
    print(f"✅ Present: {len(present_variables)}")
    print(f"❌ Missing: {len(missing_variables)}")
    
    if missing_variables:
        print(f"\n🚨 Missing Variables:")
        for var in missing_variables:
            print(f"   - {var}")
            
        print(f"\n💡 To fix missing variables:")
        print(f"   1. Run: ./setup_wizard.py")
        print(f"   2. Or manually add them to config.yaml")
        
        return 1
    else:
        print(f"\n🎉 All variables are present!")
        return 0

if __name__ == "__main__":
    sys.exit(main())
