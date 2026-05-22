# ERC-EMBER Foundry Suite

This directory contains the Solidity reference implementation and Foundry tests
for ERC-EMBER v0.3.

## Layout

```text
contracts/
├── foundry.toml
├── remappings.txt
├── src/
│   ├── IERC165.sol
│   ├── IERC20Token.sol
│   ├── IEmber.sol
│   ├── IEmberRecovery.sol
│   ├── EmberCore.sol
│   ├── EmberFactory.sol
│   ├── MaintenancePool.sol
│   └── MaintenancePoolFactory.sol
├── script/
│   ├── DeployFactory.s.sol
│   ├── DeployProject.s.sol
│   ├── CheckProjectDeployment.s.sol
│   ├── CheckFactoryDeployment.s.sol
│   ├── CheckCanonicalUSDC.s.sol
│   ├── CheckLicenseApproval.s.sol
│   ├── AcceptFactoryOwnership.s.sol
│   ├── SeedLicenseApproval.s.sol
│   └── StartFactoryOwnershipTransfer.s.sol
└── test/
    ├── EmberCore.t.sol
    ├── EmberFactoryPool.t.sol
    ├── MaintenancePool.t.sol
    └── mocks/MockUSDC.sol
```

`IEmber.sol` is the neutral ERC surface. `IEmberRecovery.sol` is an optional
extension, not part of core ERC conformance. `EmberFactory.sol`,
`MaintenancePool.sol`, and `MaintenancePoolFactory.sol` are included as
non-normative implementation layers.

## Setup

Install Foundry if needed:

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

Install the test dependency:

```bash
cd contracts
forge install --root . foundry-rs/forge-std
```

`lib/` is ignored by git, so a fresh clone should run the install command before
building.

## Commands

```bash
forge build --force
forge test -vvv
forge build --sizes
```

`foundry.toml` enables `via_ir = true`. Keep it enabled unless the contracts are
refactored enough to avoid Solidity's stack-too-deep limit.

## Deployment checklist

Before deploying `EmberFactory`, decide the real production recipients:

- `standardAuthor`: receives the 1.3% factory fee and the 10% recovery commission.
- `recoveryTreasury`: receives the 90% abandoned-capital recovery treasury share.

These routes are intentionally explicit. Contracts created through
`EmberFactory` send a 1.3% primary-sale fee to `standardAuthor`; direct
`EmberCore` deployments do not. If abandoned-capital recovery is configured and a
project becomes recoverable after the inactivity window, only idle USDC outside
the protected holder redemption reserve is swept. Of that recoverable amount,
90% goes to `recoveryTreasury` to support startup and software ecosystem
initiatives, and 10% goes to `standardAuthor` as the recovery commission.
The factory fee is not recurring: it is collected only during active primary
sales. Once an EMBER contract closes into release, slash, or abandoned recovery,
there is no ongoing standard-author payment stream.

`EmberFactory` spawns maintenance pools through an external `MaintenancePoolFactory`
(this keeps `EmberFactory` under the EIP-170 size limit), so deploy that first and
pass its address to the `EmberFactory` constructor. The launch scripts in
`script/` automate this sequence and the project deploy path; see
`../docs/launch-deployer.md`.

Deploy only after `forge fmt --check`, `forge build --force`, `forge test -vvv`,
and `forge build --sizes` pass:

```bash
forge script script/DeployFactory.s.sol:DeployFactory \
  --rpc-url "$RPC_URL" \
  --broadcast \
  --verify
```

After deployment, seed the OSI license allowlist with `setLicenseApproval`
before accepting product deployments. The checked-in
`script/SeedLicenseApproval.s.sol` script seeds one SPDX identifier per run.
`deploy(...)` enforces that the `usdc` sale token reports `decimals() == 6` (the
bonding curve assumes 6 decimals); `EmberCore` itself is neutral about decimals.
When a product opts into a maintenance pool, `deploy(...)` takes a
`poolTimelockDelay` (seconds, bounded to [1 day, 30 days]; recommended 7 days for
production, 1 day for testnet).

## Current verification

- `forge build --force`: compiler successful, zero warnings
- `forge test`: 47 passed, 0 failed
- `forge build --sizes`: `EmberFactory` runtime size 20,154 bytes (4,422 below the
  EIP-170 24,576-byte limit); `MaintenancePoolFactory` 7,376 bytes;
  `MaintenancePool` 6,495 bytes; `EmberCore` 12,552 bytes
- `forge coverage --ir-minimum`: 86.22% lines / 87.99% statements

## Test coverage

`EmberCore.t.sol` covers:

- full-burn release with no redemption pool;
- zero-price constructor rejection;
- quorum trigger and redemption-pool snapshotting;
- freeze invariants after the Ember Phase opens;
- bounded redemption payouts;
- abandoned-capital recovery preservation of outstanding redemption reserves;
- fuzzed quorum settlement solvency for non-round supplies/prices;
- ERC-20 zero-address transfer rejection;
- reserved-tranche-only slash;
- late release before slash;
- release rejection after slash;
- optional abandoned-capital recovery;
- ERC-165 detection for `IERC165`, `IEmber`, and `IEmberRecovery`.

`EmberFactoryPool.t.sol` covers:

- factory license allowlist ownership;
- two-step factory ownership transfer;
- approved and rejected deployments;
- non-6-decimal sale-token rejection (factory USDC policy);
- production recipient and pool-factory constructor validation;
- factory wiring of fee and recovery recipients;
- optional maintenance-pool deployment via `MaintenancePoolFactory`, including the
  wired timelock delay.

`MaintenancePool.t.sol` covers:

- timelock-delay constructor bounds and zero-param rejection;
- queue → delay → execute lifecycle with permissionless execution;
- execution guards (before-eta, double-execute, unknown id, insufficient balance);
- cancel before and after eta, and governor-only queue/cancel;
- timelocked governor rotation;
- instant tips / fork royalties and zero-value rejection;
- sunset inactivity gate, execution-time re-validation, full sweep, and terminal close;
- proposal event emission.

## Notes

The tests use `MockUSDC` with 6 decimals and a flat bonding curve so the
accounting is exact and easy to inspect. Re-run `forge build --sizes` after any
change that grows `EmberFactory`; factory size is the main bytecode-size risk.

CI (`.github/workflows/foundry.yml`) runs `forge fmt --check`, `forge build`,
`forge test`, and `forge build --sizes` (an EIP-170 size gate). Coverage is run
locally with `forge coverage --ir-minimum` — it is kept out of CI because plain
`forge coverage` disables `via_ir` and hits Solidity's stack-too-deep limit.

`MaintenancePool` is optional companion infrastructure. Every outflow and governor
change is timelocked (queue → delay → execute); funding stays instant; sunset is a
terminal drain-and-close available after 12 months of inactivity. The `Steward`,
`Multisig`, and `DAO` modes are fully implemented; `ContributorVote` /
`BurnReceiptVote` point `governor` at an external tally contract (out of scope).
There is no guardian/veto by design — the timelock gives visibility, not prevention
against a compromised governor.
