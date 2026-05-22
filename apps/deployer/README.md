# ERC-EMBER Deployer App

Wallet-only launch console for ERC-EMBER factory and project deployments.

The app does not handle private keys. It uses the connected wallet for:

- `MaintenancePoolFactory` deployment;
- `EmberFactory` deployment;
- factory wiring checks;
- SPDX allowlist seeding/checking;
- canonical USDC checking;
- factory ownership transfer start;
- project deployment through `EmberFactory.deploy`;
- factory registry loading.

## Build

From the repo root, compile contracts first:

```bash
cd contracts
forge build --force
```

Then build the app:

```bash
cd ../apps/deployer
npm ci
npm run build
```

The app generates `src/generated/contracts.ts` from `contracts/out/`.

## Run

```bash
npm run dev
```

Use the Foundry scripts in `contracts/script/` as the canonical launch path. The
browser app is an operator convenience layer over the same contract calls.
