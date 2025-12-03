# WARP.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Overview

This repository implements the **Azure NetApp Files Migration Assistant**, a cross-platform command-line tool that orchestrates ANF migrations via Bash and Python. The core pieces are:

- A Bash orchestrator (`anf_interactive.sh`) that drives the three migration phases (setup, peering, break/finalization) using Azure REST APIs.
- A Python interactive wizard (`setup_wizard.py`) that builds and validates the YAML configuration consumed by the Bash script.
- YAML tooling (`yaml-autofix.py`, `yaml-diagnostic.py`, `validate-yaml.py`, `debug_yaml.py`, `debug_config.py`) that makes config editing robust on Windows and other platforms.
- Windows-specific environment setup (`check-prerequisites.ps1`) to ensure Git Bash, Python, PyYAML, and curl are available and wired together correctly.
- Demo and diagnostic scripts (`demo_*.py`, `test_*.py`, `debug_validation.sh`, etc.) used for documentation, UX design, and troubleshooting.

The main user-facing workflow is:

1. Ensure prerequisites (Git Bash, Python, PyYAML, curl) are available.
2. Generate or update `config.yaml` via the Python setup wizard.
3. Run `anf_interactive.sh` to execute migration phases and/or monitoring.

## Core Commands

### Environment / prerequisites

**Windows (PowerShell):**

- Check and optionally auto-install prerequisites (Git Bash, Python, PyYAML, curl):

  ```powershell
  .\check-prerequisites.ps1
  ```

- Recommended Git Bash binary path used throughout:

  ```powershell
  "C:\Program Files\Git\bin\bash.exe"
  ```

If Python or PyYAML are missing, the prerequisite script can install them and refresh `PATH` without requiring a new PowerShell session.

### Configuration workflow

- Run the interactive setup wizard (default `config.yaml` in repo root):

  ```powershell
  # Any platform where Python is installed
  python3 setup_wizard.py
  ```

- Use a custom config file (e.g., per-environment):

  ```powershell
  python3 setup_wizard.py --config production.yaml
  python3 setup_wizard.py -c dev-config.yaml
  ```

The wizard:

- Optionally starts from `config.template.yaml` if no config exists.
- Validates UUIDs, Azure regions, service levels, protocols, IP addresses, and replication schedule.
- Collects ONTAP details (cluster/SVM/volume/peer IPs) and Azure ANF properties.
- Writes a `variables` / `secrets` structure to YAML and creates timestamped backups under `config_backups/` whenever overwriting an existing config.

### Running the migration workflows

On **Linux/macOS or Git Bash on Windows** (from repo root):

- Show interactive menu (all phases and tools):

  ```bash
  ./anf_interactive.sh
  ```

- Run specific phases directly:

  ```bash
  ./anf_interactive.sh setup     # Phase 1: configuration / wizard entry point
  ./anf_interactive.sh peering   # Phase 2: volume creation + cluster/SVM peering + start replication
  ./anf_interactive.sh break     # Phase 3: break replication & finalize migration
  ./anf_interactive.sh monitor   # Standalone replication monitoring
  ./anf_interactive.sh config    # Pretty-print current config.yaml values
  ./anf_interactive.sh token     # Fetch and cache an auth token only
  ./anf_interactive.sh diagnose  # YAML diagnostics via Python helpers
  ./anf_interactive.sh help      # Command overview and workflow docs
  ```

On **Windows PowerShell**, the same commands are typically wrapped via Git Bash, for example:

```powershell
& "C:\Program Files\Git\bin\bash.exe" -c "./anf_interactive.sh"
& "C:\Program Files\Git\bin\bash.exe" -c "./anf_interactive.sh peering"
& "C:\Program Files\Git\bin\bash.exe" -c "./anf_interactive.sh --config production.yaml break"
```

### Interaction and monitoring modes

These environment variables are read by `anf_interactive.sh` to change UX behavior:

- Control how much prompting occurs during Phase 2/3 (peering + break):

  ```bash
  export ANF_INTERACTION_MODE="minimal"  # Auto-continue most steps (experienced users)
  export ANF_INTERACTION_MODE="full"     # Step-by-step confirmations (default)
  ```

- Control how async operations and replication are monitored:

  ```bash
  export ANF_MONITORING_MODE="full"    # Always monitor async operations / replication in detail
  export ANF_MONITORING_MODE="quick"   # Only monitor critical operations (e.g., replication transfer)
  export ANF_MONITORING_MODE="custom"  # Ask each time whether to monitor
  ```

The standalone monitor (`./anf_interactive.sh monitor`) internally sets a special monitoring mode to run continuously until Ctrl+C.

### YAML validation and remediation ("tests" for configs)

These Python scripts are used heavily by the Bash orchestrator and are useful standalone when developing or debugging:

- Basic YAML validity check (exit code only, used by `validate_config` in Bash):

  ```bash
  python validate-yaml.py config.yaml
  ```

- Diagnose common Windows YAML issues (encoding, BOM, line endings, indentation):

  ```bash
  python yaml-diagnostic.py config.yaml
  ```

- Auto-remediate encoding/indentation/colon-spacing issues and re-validate:

  ```bash
  python yaml-autofix.py config.yaml
  ```

- Deep-dive diagnostics while developing parsing logic (prints structure and key checks):

  ```bash
  python debug_yaml.py config.yaml
  python debug_config.py config.yaml
  ```

These are the closest thing to a "test suite" in this repo; new features that touch YAML parsing or config structure should be validated against at least `validate-yaml.py` and, where relevant, `yaml-diagnostic.py` / `yaml-autofix.py`.

### Config access / path tests

The `test_*.py` helpers are small, focused scripts used to reproduce and debug config resolution and YAML reading behaviors across platforms:

- Inspect how the current process locates and reads `config.yaml`:

  ```bash
  python test_config.py
  ```

- Verify that a given config exposes expected keys via the same logic used in Bash:

  ```bash
  python test_config_value.py config3.yaml
  ```

- Confirm that Windows / Git Bash path normalization works correctly when reading configs:

  ```bash
  python test_path.py config3.yaml
  ```

These scripts are safe to modify or extend when investigating cross-platform file-handling issues.

## Architecture and Code Structure

### Configuration model (YAML)

- All runtime configuration is centralized in a YAML file (`config.yaml` by default), with two top-level keys:
  - `variables`: non-secret inputs (Azure IDs, region, NetApp account/pool, volume name/size, protocol, subnet ID, replication schedule, ONTAP identifiers, etc.).
  - `secrets`: currently the service principal secret used for Azure authentication.
- Example structures live in `config.template.yaml` and `config3.yaml`; these are the authoritative references for what the Bash / Python code expects.
- The Bash layer never parses YAML directly; instead, it shells out to Python (`get_config_value`) to read both `variables` and `secrets` and substitute them into REST endpoints and JSON payload templates.

### Python setup wizard and helpers

`setup_wizard.py` is the primary entry point for creating and editing configs:

- Encapsulates logic in `ANFSetupWizard`, which:
  - Loads an existing config if present; otherwise offers to start from `config.template.yaml`.
  - Groups prompts into logical sections: Azure basics, service principal, NetApp resources, migration settings, optional settings.
  - Performs strong validation (UUIDs, region names, service levels, protocol strings, replication schedule, IP formats).
  - Handles complex fields like `source_peer_addresses` (single IP vs JSON list) and `target_zones` (Availability Zones) while keeping the on-disk representation compatible with Azure API payloads.
- Before overwriting an existing config file, it creates a timestamped backup under `config_backups/`.
- At the end of the wizard, it prints a summary (region, resource group, account/pool, volume size, QoS, replication schedule, ONTAP source details, peer addresses) so changes can be reviewed before saving.

Other Python helpers support this workflow:

- `validate-yaml.py` provides a bare-bones parse-check used by Bash to decide whether a config is usable.
- `yaml-diagnostic.py` and `yaml-autofix.py` encode most of the Windows-specific YAML handling knowledge (encodings, BOM, CRLF vs LF, tabs vs spaces, colon spacing); Bash will automatically attempt remediation if parsing fails.
- `debug_yaml.py` and `debug_config.py` are deeper inspection tools used mainly during development to understand YAML layout and field-level issues.

### Bash migration engine (`anf_interactive.sh`)

`anf_interactive.sh` is the central orchestrator for all migration behavior:

- **Runtime environment detection**
  - Detects an appropriate Python command (`python3`, `python`, or `py`) and bails early if Python/PyYAML are unavailable.
  - Uses `$SCRIPT_DIR` and a `--config/-c/--config=...` flag implementation to support multiple config files regardless of the current working directory.

- **Config access and display**
  - `get_config_value` is implemented as an inline Python one-liner that:
    - Handles Git Bash on Windows path conversion.
    - Tries multiple encodings and strips BOM.
    - Merges `variables` and `secrets` before returning a single value.
  - `show_config` aggregates high-level Azure, NetApp, ONTAP, and replication settings into a readable summary, including volume size in GiB, QoS mode, zones, large-volume flag, subnet ID, and redacted secret status.

- **Interaction model**
  - `confirm_step` centralizes the per-step UX: a single prompt with `[C]ontinue / [w]ait / [r]e-run / [q]uit`, with auto-continue in `ANF_INTERACTION_MODE=minimal`.
  - `ask_user_choice` implements yes/no questions with explicit defaults and colored output.

- **REST abstraction and templating**
  - `execute_api_call` wraps Azure REST interactions:
    - Ensures a token is present (via `get_token`), then builds the full URL using `azure_api_base_url` and `azure_api_version`.
    - Uses Python to substitute config values (`{{key}}`) into URLs and JSON bodies, with special handling for `source_peer_addresses` and lists.
    - Logs headers and bodies to `anf_migration_interactive.log`, pretty-printing JSON responses where possible.
    - Detects async operations via headers (`azure-asyncoperation`, `location`) and optionally invokes `monitor_async_operation` based on `ANF_MONITORING_MODE` and the current step.
  - `get_volume_payload` builds the JSON payload for volume creation, branching on protocol (SMB vs NFS) and QoS mode (auto vs manual) to maintain correct shapes for Azure.

- **Async monitoring and ONTAP coordination**
  - `monitor_async_operation` repeatedly polls an async URL, pretty-prints status/progress, and captures the final JSON in a temporary file and `.last_async_response` for consumption by later steps.
  - It parses Azure-provided fields like `clusterPeeringCommand`, `passphrase`, and `SvmPeeringCommand` from the async response and prints turn-key ONTAP CLI commands plus contextual instructions (where to run them, how to use peer addresses from config, etc.).
  - After the user confirms ONTAP-side commands are complete, it guides them into the long-running replication phase and optionally offers to start replication monitoring.

- **Replication monitoring**
  - `monitor_replication_status` talks to the Azure Monitor metrics API for a migration volume, computing:
    - Total transferred bytes and progress, displayed in human-readable units.
    - Average transfer rate (MB/s, Mbps) from a baseline, using Python to avoid shell `bc` dependencies.
    - Human-readable elapsed time.
  - It runs in a loop until a configured max number of checks, printing friendly, colorized output and allowing cancellation via Ctrl+C.
  - `list_replication_volumes` and `run_replication_monitor_standalone` discover replication volumes across capacity pools and pick a default to monitor, enabling the `monitor` command to function independently of the main migration flow.

- **Validation and self-healing**
  - `check_dependencies` ensures `curl`, Python, and PyYAML are present before running workflows.
  - `validate_config` gates all major workflows:
    - Verifies that `CONFIG_FILE` exists.
    - Runs `validate-yaml.py` and, if it fails, attempts `yaml-autofix.py` and re-validation, emitting detailed remediation suggestions if still invalid.
    - On success, calls `show_config` to give the user a final sanity check.

- **Menu and phase orchestration**
  - The main menu (defined later in the script) wires everything together into discrete options:
    - Run setup wizard.
    - Run peering workflow.
    - Run break/finalization workflow.
    - Monitor replication.
    - Show config, diagnose YAML, fetch token, and show help.

### Windows prerequisites and integration (`check-prerequisites.ps1`)

This script encodes most of the platform assumptions for Windows developers:

- Locates Git Bash at `C:\Program Files\Git\bin\bash.exe` and checks its version.
- Attempts multiple Python entry points (`python3`, `python`, `py`), detecting and working around Windows Store stubs.
- Optionally auto-downloads and installs a specific Python build, adds it to `PATH`, and verifies it without requiring a new PowerShell session.
- Verifies PyYAML is importable and offers to install it via `pip` if missing.
- Ensures a real `curl.exe` is present (not just the PowerShell alias), which is important because the Bash script calls `curl` directly.
- Validates that Git Bash can invoke Python and import PyYAML, which is critical for the Bash/Python/YAML pipeline used during migration.

### Demo and support scripts

The remaining scripts support documentation, UX design, and troubleshooting; they are not part of the main runtime but are valuable context for future changes:

- `demo_prompting.py`, `demo_phase3_interaction.py`, `demo_replication_monitor.py`, `demo_standalone_monitor.py` mirror sample terminal sessions for the updated confirmation model, interaction modes, and monitoring views.
- `debug_validation.sh`, `new_show_config.sh`, and `show_config_temp.sh` are experimental shells used while iterating on how config display and YAML parsing behave under Git Bash/Windows; they provide working examples of smaller, isolated pieces of the main script.
- `config3.yaml` is a fully-populated sample config used to exercise YAML tooling and helper scripts.
- `test_config.py`, `test_config_value.py`, and `test_path.py` are small, single-purpose Python scripts that probe how configs are located and parsed, and how values align with what `anf_interactive.sh` expects.

When refactoring or extending the migration flows, consider these demo and diagnostic scripts as living documentation of the intended UX and data flows between Azure, ONTAP, and the configuration layer.
