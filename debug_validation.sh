#!/bin/bash
# Test script to debug the validation issue

CONFIG_FILE="/c/GitHub/Migration-Assistant/config.yaml"

# Test Python command detection
if python3 --version >/dev/null 2>&1; then
    PYTHON_CMD="python3"
elif python --version >/dev/null 2>&1; then
    PYTHON_CMD="python"
elif py --version >/dev/null 2>&1; then
    PYTHON_CMD="py"
else
    PYTHON_CMD="python"
fi

echo "Python command detected: $PYTHON_CMD"
echo "Config file path: $CONFIG_FILE"
echo "Config file exists: $(test -f "$CONFIG_FILE" && echo "YES" || echo "NO")"

# Test the exact command from the validation function
echo ""
echo "Testing YAML parsing..."
if $PYTHON_CMD -c "import yaml; yaml.safe_load(open('$CONFIG_FILE'))" 2>/dev/null; then
    echo "✅ YAML parsing successful"
else
    echo "❌ YAML parsing failed"
    echo "Error output:"
    $PYTHON_CMD -c "import yaml; yaml.safe_load(open('$CONFIG_FILE'))" 2>&1
fi