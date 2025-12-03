# WARP.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Overview

This repo contains the **Azure NetApp Files Migration Assistant**, a cross-platform CLI for orchestrating ANF volume migrations using:
- A **Bash orchestrator** (`anf_interactive.sh`) that drives the migration workflow and calls Azure REST APIs.
- A **Python setup wizard** (`setup_wizard.py`) and YAML helper tools for managing a structured `config.yaml` with `variables` and `secrets`.

The tool is **config-driven** and **phase-based**:
- **Phase 1 – Setup:** Collect and validate Azure and ONTAP parameters, generate/maintain `config.yaml`.
- **Phase 2 – Peering:** Create the destination ANF volume, set up cluster + SVM peering, start replication.
- **Phase 3 – Break & Finalize:** Run the final replication transfer, break the replication, and finalize the cutover.

## Common Commands & Workflows

All commands below assume the current working directory is the repo root and a suitable Python 3 + PyYAML environment is available.

### Core workflows

- **Interactive menu (default entrypoint):**
  - `./anf_interactive.sh`
  - Same as: `./anf_interactive.sh menu`

- **Run the setup wizard (Phase 1 – configuration):**
  - `python3 setup_wizard.py` (uses `config.yaml` by default)
  - Or via the Bash entrypoint: `./anf_interactive.sh setup`
  - Use a custom config file: `python3 setup_wizard.py --config production.yaml`

- **Peering & initial sync (Phase 2):**
  - `./anf_interactive.sh peering`
    - Prompts for interaction level (minimal vs full) and drives:
      - Authentication (Azure AD token)
      - Volume creation (ANF Migration volume)
      - Cluster peering (ON-TAP commands + Azure API)
      - SVM peering and replication authorization
    - Optionally starts a short live replication monitor at the end.

- **Break replication & finalize (Phase 3):**
  - `./anf_interactive.sh break`
    - Refreshes auth token
    - Triggers final replication transfer
    - Breaks the replication relationship
    - Finalizes external replication and prints post-migration steps

- **Standalone replication monitoring:**
  - `./anf_interactive.sh monitor`
    - Discovers existing migration volumes
    - Lets you select a volume and continuously monitor replication metrics (transfer, progress, average rate).

- **Configuration inspection & diagnostics:**
  - Show effective config values: `./anf_interactive.sh config`
  - Diagnose YAML issues with nice output: `./anf_interactive.sh diagnose`
  - Fetch an auth token only (and cache in `.token`): `./anf_interactive.sh token`

- **Custom config files for multi-env setups:**
  - `./anf_interactive.sh --config production.yaml peering`
  - `./anf_interactive.sh -c test-config.yaml monitor`
  - `./anf_interactive.sh --config=staging.yaml menu`

### YAML validation & auto-remediation tools

These Python utilities are used internally by `anf_interactive.sh` but can also be invoked directly during development:

- **Quick validity check (exit code only):**
  - `python3 validate-yaml.py config.yaml`

- **Detailed diagnostics for hand-edited YAML:**
  - `python3 yaml-diagnostic.py config.yaml`
    - Detects encoding, line endings, BOM, missing sections, and common syntax problems.

- **Automatic remediation of common Windows editing issues:**
  - `python3 yaml-autofix.py config.yaml`
    - Fixes BOM, CRLF → LF, tab indentation, and `key:value` spacing; writes a backup beside the original.

- **Low-level debugging helpers (ad hoc “tests” for config handling):**
  - `python3 debug_yaml.py config.yaml` – deep inspection of YAML structure and encoding.
  - `python3 debug_config.py config.yaml` – load and print `variables` / `secrets` sections.
  - `python3 test_config.py` – verify `config.yaml` is discoverable from current working directory.
  - `python3 test_config_value.py config.yaml` – print key config values resolved the same way as the Bash script.
  - `python3 test_path.py config.yaml` – exercise path normalization and YAML loading.

> Note: There is no dedicated unit-test suite (pytest, nose, etc.) in this repo. Validation is performed via the above helper scripts plus end‑to‑end runs of the interactive workflows.

### Environment variables that affect behavior

These are honored primarily by `anf_interactive.sh` during peering and monitoring workflows:

- **`ANF_INTERACTION_MODE`** (used by `peering` and `break`):
  - `minimal` – auto-continue through most steps; still prompts for critical ONTAP commands.
  - `full` (default) – shows step descriptions and prompts (`c/w/r/q`) before each operation.

- **`ANF_MONITORING_MODE`** (used when operations are asynchronous and for replication monitoring):
  - `full` – monitor all async operations and volume status.
  - `quick` – only monitor critical long-running operations (e.g., replication transfer).
  - `custom` – prompt the user per operation whether to monitor.
  - `true` – special internal value used by the standalone monitor to suppress interactive prompts.

You can set these in the shell before invoking the workflows, e.g.:
- `export ANF_INTERACTION_MODE="minimal"`
- `export ANF_MONITORING_MODE="quick"`

### Logs and artifacts

- **Interactive workflow log:** `anf_migration_interactive.log` (created in repo root).
- **YAML backups:** `config_backups/` – timestamped copies created by `setup_wizard.py` when saving.
- **Token cache:** `.token` – Azure AD access token used by `curl` calls (regenerated as needed).
- **Last async response:** `.last_async_response` – final JSON body from the most recent monitored async operation.

## Architecture & Code Structure

### Configuration-centric design

- Core configuration is stored in **YAML** files (`config.yaml` by default, but `--config` allows alternatives).
- The structure follows the pattern introduced in `MIGRATION_GUIDE.md`:
  - `secrets:` – sensitive values (e.g., `azure_app_secret`).
  - `variables:` – all other parameters (Azure subscription, ANF account/pool/volume, ONTAP cluster & SVM, replication settings, QoS, zones, etc.).
- `MIGRATION_GUIDE.md` documents the mapping from legacy keys to the new snake_case names and the split between `variables` and `secrets`. Any new logic should adhere to this naming convention.

### Python setup wizard (`setup_wizard.py`)

- Encapsulated in the `ANFSetupWizard` class, which:
  - Optionally loads an existing `config.yaml` or uses `config.template.yaml` as a starting point.
  - Interactively collects:
    - Azure tenant/subscription IDs (UUID-validated), region, resource group.
    - Service principal (`azure_app_id`, `azure_app_secret`) and auth/management endpoints.
    - ANF account, capacity pool, subnet, service level, QoS, and availability zone.
    - Source ONTAP cluster, SVM, volume, and **multiple peer addresses** (with validation and JSON-array handling).
  - Validates common fields (UUIDs, Azure regions, protocol types, replication schedules, IPs, numeric sizes).
  - Converts GiB input to byte-based thresholds for `usageThreshold`.
  - Backs up any existing config into `config_backups/` before overwriting.
  - Prints a concise summary of the resulting configuration.
- The wizard is the **authoritative path** for producing configs that `anf_interactive.sh` expects; any new fields should ideally be plumbed through here.

### Bash orchestrator (`anf_interactive.sh`)

This is the primary runtime entrypoint and contains most of the operational logic.

Key responsibilities:

- **Config & dependency handling**
  - Detects an appropriate `python` command (`python3`, `python`, or `py`) and uses it for all YAML/JSON work.
  - `check_dependencies` ensures `curl`, Python, and `PyYAML` are present.
  - `get_config_value` reads from `config.yaml` using PyYAML, merging `variables` and `secrets` into a single key space. It has special-case logic to support Windows Git-Bash paths.
  - `validate_config` runs `validate-yaml.py` first, then (if needed) `yaml-autofix.py` followed by another validation pass. On failure it prints remediation guidance and suggests running `setup`.

- **Menu & CLI surface**
  - Main entry: `anf_interactive.sh [--config FILE] [menu|setup|peering|break|monitor|config|diagnose|token|help]`.
  - `show_main_menu` / `run_main_menu` implement the numbered TUI described in `README.md`.
  - `show_help` prints a detailed, phase-oriented usage summary; rely on this if you add commands.

- **HTTP / Azure API layer**
  - Uses `curl` for all REST calls to both the ANF resource provider and Azure Monitor (metrics).
  - `get_token` and `get_token_interactive` obtain and cache Azure AD tokens based on config values.
  - `execute_api_call` performs a single REST call with:
    - URL and JSON body templating via Python (substituting `{{variable_name}}` from config, with special handling for `source_peer_addresses`).
    - Per-step logging to `anf_migration_interactive.log`.
    - Pretty-printed JSON responses when possible.
    - Handling of async operations (`azure-asyncoperation` and `location` headers) by delegating to `monitor_async_operation` or, for volume creation, to `check_volume_status`.
  - `execute_api_call_silent` is a non-interactive variant used for internal checks (e.g., detecting existing cluster peering).

- **Async operation management**
  - `monitor_async_operation` polls async status URLs, parses JSON `status` / `percentComplete` / error fields, and:
    - Stores the final response to a temp file and `.last_async_response`.
    - Exposes helpers `get_last_async_response_data`, `get_async_response_field`, and `show_async_response_data` for subsequent steps.
  - `check_volume_status` polls the ANF volume resource to confirm provisioning completion and surfaces key fields (state, fileSystemId, mount targets).

- **Peering & replication workflows**
  - `get_volume_payload` dynamically builds the JSON body for volume creation based on protocol (SMB vs NFSv3) and QoS mode (Auto vs manual throughput), embedding replication config derived from the `variables` section.
  - `run_peering_setup` composes the full Phase 2 workflow:
    - Auth token retrieval.
    - Volume creation (`create_volume`).
    - Optional reuse of existing cluster peering via `check_existing_cluster_peering` (uses a silent check against current pool volumes).
    - Cluster peering (`peer_request`) and SVM peering authorization (`authorize_replication`), including extraction of ONTAP CLI commands and passphrases from async responses and presenting them with human-readable instructions.
    - Optional, time-bounded replication monitoring after SVM peering.
  - `run_break_replication` encapsulates Phase 3:
    - User confirmation with strong warnings.
    - Final replication transfer (`performReplicationTransfer`).
    - Break replication (`breakReplication`).
    - Finalize replication (`finalizeExternalReplication`).

- **Monitoring & metrics**
  - `monitor_replication_status` queries Azure Monitor for key metrics (e.g. `VolumeReplicationTotalTransfer`, `VolumeReplicationTotalProgress`), then:
    - Prints human-readable sizes and last update times.
    - Computes average transfer rates and cumulative progress over the monitoring window.
    - Uses long-running loops (with Ctrl+C escape) suitable for observability rather than short tests.
  - `run_replication_monitor_standalone` wires discovery (`list_replication_volumes`) + monitoring into the `monitor` CLI command.

### Helper / demo scripts

These files are **not** directly called by the main workflow but document behavior and serve as examples:

- `demo_prompting.py` – demonstrates the consolidated `confirm_step` prompt UX.
- `demo_replication_monitor.py` – simulates realistic replication monitor output and transfer-rate calculations.
- `demo_standalone_monitor.py` – demo of the standalone monitor UX and options.

They can be run directly with `python3 <script>.py` for reference when modifying prompts or monitoring output.

## Important Documentation Files

- `README.md` is the canonical user-facing guide and already documents:
  - OS-specific prerequisites (Python 3, PyYAML, curl, Bash; Windows specifics like Git Bash and `check-prerequisites.ps1`).
  - End-to-end usage across all three phases and the standalone monitoring workflow.
  - Configuration fields and environment-variable–driven interaction/monitoring modes.
  - YAML auto-remediation behavior and logging locations.
- `PREREQUISITES.md` expands on system, Azure, and ONTAP prerequisites, including the exact YAML keys expected in `config.yaml`.
- `MIGRATION_GUIDE.md` explains the migration from legacy config keys to the current snake_case schema and the `variables`/`secrets` split; use this when updating configs or supporting older files.

When changing the CLI surface, config schema, or workflow phases, update these docs first, then adjust `setup_wizard.py` and `anf_interactive.sh` to remain consistent.
