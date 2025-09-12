@echo off
echo Testing Python and PyYAML installation on Windows...
echo.

echo Checking Python version:
python --version
if errorlevel 1 (
    echo ❌ Python not found or not in PATH
    echo Please install Python from https://python.org
    goto :end
)

echo.
echo Checking PyYAML installation:
python -c "import yaml; print('✅ PyYAML version:', yaml.__version__)"
if errorlevel 1 (
    echo ❌ PyYAML not installed
    echo.
    echo To install PyYAML, run:
    echo   pip install PyYAML
    echo.
    echo If that fails, try:
    echo   pip install --user PyYAML
    echo   python -m pip install PyYAML
    goto :end
)

echo.
echo ✅ All dependencies are installed correctly!
echo You can now run the ANF Migration Assistant.

:end
pause
