# ERC-EMBER Formal Verification Pack

This directory contains launch-facing formal verification artifacts.

Local status:

- Foundry fuzz/invariant tests are runnable in this repo.
- Halmos is installed locally and `EmberCoreHalmosTest` is the local symbolic
  smoke suite.
- Certora CLI is installed locally. Native Windows execution reaches Solidity
  compilation, then fails inside Certora's Java preprocessor/path handling.
  WSL/Linux execution reaches the Certora cloud-auth boundary and requires
  `CERTORAKEY`.

## Certora

Primary target:

```bash
certoraRun formal/certora/conf/embercore.conf
```

Set the API key first:

```bash
export CERTORAKEY=<certora-api-key>
```

On this Windows/WSL setup, use a Linux-only PATH with the user-local JDK and
Python scripts:

```bash
export PATH="$HOME/.local/jdks/jdk-21.0.11+10/bin:$HOME/.local/bin:$PATH"
```

The spec focuses on invariants that matter for launch:

- terminal states are mutually exclusive;
- total burned never exceeds initial supply;
- redemption accounting never pays beyond the snapshotted pool;
- factory fee cap remains bounded;
- recovery reserve protection remains non-negative and bounded.

The spec is deliberately conservative. It should be expanded by the external
auditor if they choose a different threat model or verification backend.

## Halmos

Run from `contracts/`:

```bash
HALMOS_ALLOW_DOWNLOAD=1 halmos --root . --match-contract EmberCoreHalmosTest --solver yices --solver-timeout-assertion 30s --width 32 --depth 0
```

On PowerShell:

```powershell
$env:HALMOS_ALLOW_DOWNLOAD='1'
halmos --root . --match-contract EmberCoreHalmosTest --solver yices --solver-timeout-assertion 30s --width 32 --depth 0
```

On WSL, ensure `forge` is available in PATH. A user-local symlink to the Windows
Foundry binary works:

```bash
ln -sf /mnt/c/Users/Me/.foundry/bin/forge.exe ~/.local/bin/forge
```
