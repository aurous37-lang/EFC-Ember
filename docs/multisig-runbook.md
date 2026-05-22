# Multisig Launch Runbook

Use a Safe or equivalent multisig for long-lived factory ownership.

## Factory Ownership Handoff

1. Deploy `MaintenancePoolFactory` and `EmberFactory`.
2. Run `CheckFactoryDeployment` while `EXPECTED_FACTORY_OWNER` is still the
   deployer.
3. Set `NEW_FACTORY_OWNER` to the Safe address.
4. Run `StartFactoryOwnershipTransfer`.
5. From the Safe, submit `acceptOwnership()` to `EmberFactory`.
6. Execute the Safe transaction after the threshold signs.
7. Set `EXPECTED_FACTORY_OWNER` to the Safe and
   `EXPECTED_PENDING_FACTORY_OWNER` to zero.
8. Run `CheckFactoryDeployment` again.

## Safe Transaction Data

Target:

```text
<EmberFactory address>
```

Function:

```solidity
acceptOwnership()
```

Calldata:

```text
0x79ba5097
```

## Evidence Checklist

Save screenshots or exports for:

- Safe transaction summary before signing.
- Threshold signatures collected.
- Executed transaction receipt.
- Post-handoff `CheckFactoryDeployment` output.
- License seed transaction summary for each approved SPDX identifier.

Store public-safe artifacts under `deployments/<chain-id>-safe/`. Do not store
private keys, seed phrases, RPC credentials, or unpublished launch plans.

## Screenshot Templates

The SVG templates in `docs/assets/multisig-runbook/` give the expected evidence
shape for launch packages. Replace them with real Safe screenshots during the
actual deployment.
