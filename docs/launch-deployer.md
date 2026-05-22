# ERC-EMBER Launch Deployer

This repo now has Foundry scripts for the launch path:

1. Deploy `MaintenancePoolFactory`.
2. Deploy `EmberFactory` wired to the pool factory.
3. Check the factory wiring.
4. Seed the SPDX allowlist.
5. Check the SPDX allowlist state.
6. Check the canonical USDC address.
7. Hand factory ownership to the operations owner or multisig.
8. Deploy ERC-EMBER projects through the factory.
9. Check the deployed project wiring.

The scripts are intentionally thin wrappers around the contracts. They do not
custody funds, store keys, or bypass contract validation.

The optional browser console in `apps/deployer/` covers the same launch actions
with a connected wallet and includes a registry view over factory deployments.

## Prerequisites

- Foundry installed.
- Node.js/npm installed for the optional deployer app.
- A funded deployer account for the target chain.
- Real production addresses for:
  - `STANDARD_AUTHOR`: receives the 1.3% factory fee and 10% recovery commission.
  - `RECOVERY_TREASURY`: receives the 90% abandoned-capital recovery treasury share.
- A verified 6-decimal USDC-compatible token address for the target chain.

Create a local `.env` from `.env.example` and fill in real values. Do not commit
`.env`. Set `EXPECTED_CHAIN_ID` before every dry-run or broadcast; every script
reverts if the connected RPC is on a different chain.

## Verify Before Broadcast

Run from `contracts/`:

```bash
forge fmt --check
forge build --force
forge test -vvv
forge build --sizes
```

Dry-run scripts before broadcasting:

```bash
forge script script/DeployFactory.s.sol:DeployFactory --rpc-url "$RPC_URL"
forge script script/CheckFactoryDeployment.s.sol:CheckFactoryDeployment --rpc-url "$RPC_URL"
forge script script/SeedLicenseApproval.s.sol:SeedLicenseApproval --rpc-url "$RPC_URL"
forge script script/CheckLicenseApproval.s.sol:CheckLicenseApproval --rpc-url "$RPC_URL"
forge script script/CheckCanonicalUSDC.s.sol:CheckCanonicalUSDC --rpc-url "$RPC_URL"
forge script script/DeployProject.s.sol:DeployProject --rpc-url "$RPC_URL"
forge script script/CheckProjectDeployment.s.sol:CheckProjectDeployment --rpc-url "$RPC_URL"
```

## Deploy Factory

```bash
forge script script/DeployFactory.s.sol:DeployFactory \
  --rpc-url "$RPC_URL" \
  --broadcast \
  --verify
```

Record both emitted deployment addresses from the broadcast output:

- `MaintenancePoolFactory`
- `EmberFactory`

Set `EMBER_FACTORY` in `.env` to the deployed `EmberFactory` address before the
next steps. Set `MAINTENANCE_POOL_FACTORY` to the deployed pool factory address.
For public launch records, add a non-secret JSON file under `deployments/` using
the schema in `deployments/README.md`.

## Check Factory Wiring

Set `EXPECTED_FACTORY_OWNER` to the current factory owner, then run:

```bash
forge script script/CheckFactoryDeployment.s.sol:CheckFactoryDeployment \
  --rpc-url "$RPC_URL"
```

This checks the deployed factory's `STANDARD_AUTHOR`, `RECOVERY_TREASURY`,
`POOL_FACTORY`, `owner()`, and `pendingOwner()` values against your environment.

## Seed License Approval

Seed one SPDX identifier at a time:

```bash
SPDX_LICENSE=MIT LICENSE_APPROVED=true forge script script/SeedLicenseApproval.s.sol:SeedLicenseApproval \
  --rpc-url "$RPC_URL" \
  --broadcast
```

Repeat for every license the launch operator has approved. The factory rejects
project deployments whose `SourceManifest.spdxLicense` is not approved.

Check the seeded state:

```bash
forge script script/CheckLicenseApproval.s.sol:CheckLicenseApproval \
  --rpc-url "$RPC_URL"
```

## Check Canonical USDC

Set both `USDC` and `CANONICAL_USDC` to the launch-approved sale-token address
for `EXPECTED_CHAIN_ID`, then run:

```bash
forge script script/CheckCanonicalUSDC.s.sol:CheckCanonicalUSDC \
  --rpc-url "$RPC_URL"
```

This rejects zero addresses, non-contract addresses, non-canonical addresses,
and tokens that do not report `decimals() == 6`.

## Transfer Factory Ownership

If the deployer key should not retain allowlist authority, start the two-step
handoff:

```bash
NEW_FACTORY_OWNER=0x... forge script script/StartFactoryOwnershipTransfer.s.sol:StartFactoryOwnershipTransfer \
  --rpc-url "$RPC_URL" \
  --broadcast
```

The `NEW_FACTORY_OWNER` address must then call `acceptOwnership()` on
`EmberFactory`. For EOA owners, this repo includes:

```bash
NEW_FACTORY_OWNER_PRIVATE_KEY=0x... forge script script/AcceptFactoryOwnership.s.sol:AcceptFactoryOwnership \
  --rpc-url "$RPC_URL" \
  --broadcast
```

For Safe or multisig owners, execute `acceptOwnership()` from the multisig
interface instead. After acceptance, set `EXPECTED_FACTORY_OWNER` to that address,
set `EXPECTED_PENDING_FACTORY_OWNER` to zero, and re-run `CheckFactoryDeployment`.

## Deploy A Project

Set all project deployment variables in `.env`, then run:

```bash
forge script script/DeployProject.s.sol:DeployProject \
  --rpc-url "$RPC_URL" \
  --broadcast \
  --verify
```

`DeployProject` uses `PROJECT_DEPLOYER_PRIVATE_KEY`, not the operator
`DEPLOYER_PRIVATE_KEY`. That signer becomes the immutable `EmberCore.developer`
and controls developer withdrawals, so it must be the intended project revenue
wallet. The script requires `PROJECT_DEVELOPER` to equal the address derived from
`PROJECT_DEPLOYER_PRIVATE_KEY`.

`INITIAL_SUPPLY` is whole-token units because EMBER uses `decimals = 0`.
`BASE_PRICE` and `SLOPE` are denominated in the USDC token's smallest unit. For
6-decimal USDC, `BASE_PRICE=10000` means $0.01 per EMBER token.

The deploy script rejects placeholder provenance fields for launch: commitment,
encrypted CID, all manifest hashes, and manifest CID must be populated.
It also checks that `SPDX_LICENSE` is already approved on the factory and that
`USDC` matches `CANONICAL_USDC` and reports 6 decimals.

For `POOL_MODE`, use:

- `0`: `Steward`
- `1`: `Multisig`
- `2`: `DAO`
- `3`: `ContributorVote`
- `4`: `BurnReceiptVote`

Only use `ContributorVote` or `BurnReceiptVote` when the external tally contract
is actually deployed and set as `POOL_GOVERNOR`. Those tally contracts are not
part of the current implementation.

After deployment, set:

- `EMBER_PROJECT` to the deployed `EmberCore` address.
- `PROJECT_DEVELOPER` to the address derived from `PROJECT_DEPLOYER_PRIVATE_KEY`.
- `EMBER_PROJECT_MAINTENANCE_POOL` to the deployed pool address, or zero if no
  pool was spawned.

Then run:

```bash
forge script script/CheckProjectDeployment.s.sol:CheckProjectDeployment \
  --rpc-url "$RPC_URL"
```

This validates core parameters, factory registry data, source manifest data,
fee/recovery wiring, and optional maintenance-pool configuration.

## Launch Checklist

- The target USDC address reports `decimals() == 6`.
- `USDC` matches the launch-approved `CANONICAL_USDC` address for
  `EXPECTED_CHAIN_ID`.
- `STANDARD_AUTHOR`, `RECOVERY_TREASURY`, `DAPP`, and any `POOL_GOVERNOR` are
  real non-zero production addresses.
- `PROJECT_DEPLOYER_PRIVATE_KEY` belongs to the intended immutable project
  developer/revenue wallet.
- Factory ownership is controlled by the intended operations wallet or multisig.
- The allowlist contains only license identifiers intentionally accepted for
  launch.
- Project source hashes, encrypted CID, manifest CID, and commitment are computed
  from the actual release artifact.
- `POOL_TIMELOCK_DELAY` is between 1 day and 30 days. Use 7 days for production
  unless there is a documented reason to shorten it.
- Public docs describe ERC-EMBER as a reference/proposed protocol, not as a
  finalized Ethereum ERC standard.
