# ERC-EMBER

ERC-EMBER is a draft "burn-to-bloom" token standard for software access.
Users buy ERC-20 access tokens, the application burns those tokens when users
consume the product, and burn progress creates the economic pressure for the
developer to reveal committed source code and terminate the contract.

The current draft is **v0.3**. The EIP track is scoped to the neutral standard:
`IEmber` plus the `EmberCore` reference implementation. Product policy, factory
fees, abandoned-capital recovery, maintenance funding, and deployment services
are kept outside core ERC conformance.

## Why this exists

Most software projects choose between closed-source rent, open-source with weak
funding, or venture-backed incentives. ERC-EMBER explores a different lifecycle:

1. A developer deploys a fixed-supply access token.
2. Users buy access tokens and burn them when they use the app.
3. The developer earns stablecoin as real usage happens.
4. Once the release threshold is reached, source release unlocks a reserved
   tranche; otherwise that reserve can be slashed.
5. Outstanding holders on a quorum release redeem pro-rata instead of having
   balances confiscated.

The important invariant is simple: **holder token balances are never seized for
inactivity**. Deadlock is handled through quorum redemption, not dormant sweeps.

## Repository map

```text
.
├── ERC-EMBER-v0.3.md              Current long-form spec and design rationale
├── ERC-EMBER-v0.2.md              Historical draft
├── ERC-EMBER.md                   Historical v0.1 draft
├── contracts/
│   ├── src/
│   │   ├── IEmber.sol             Neutral ERC interface, ERC-165 aware
│   │   ├── IEmberRecovery.sol     Optional non-normative recovery extension
│   │   ├── EmberCore.sol          Reference implementation
│   │   ├── EmberFactory.sol       Non-normative deployment layer
│   │   ├── MaintenancePool.sol    Optional companion funding pool
│   │   └── MaintenancePoolFactory.sol  Stateless pool deployer (size split)
│   └── test/                      Foundry tests
├── eip/
│   └── erc-ember-eip-draft.md     EIP-1-formatted draft
├── LICENSE-CC0                    CC0 pointer for the EIP document
└── ProEmber.png                   Visual reference asset
```

The Solidity files in `contracts/src/` are canonical. When contract behavior
changes, keep `ERC-EMBER-v0.3.md` and the EIP draft in sync with the `.sol`
files.

## Standard scope

Core ERC conformance is:

- ERC-20 behavior;
- ERC-165 interface detection;
- `IEmber`;
- burn-on-use accounting;
- source commitment and key reveal;
- Ember Phase trigger, freeze, and accounting snapshot;
- mutually exclusive `released` and `slashed` terminal states;
- redemption for outstanding holders on quorum release.

Outside core conformance:

- bonding curve shape;
- stablecoin choice;
- encrypted storage backend;
- factory and registry policy;
- fees and treasury routing;
- abandoned-capital recovery;
- post-release maintenance funding.

`IEmberRecovery` exists as an optional extension in the reference
implementation. It is deliberately not part of neutral `IEmber`.

## Economic disclosure

The neutral `EmberCore` standard does not require a protocol fee. The reference
distribution layer, `EmberFactory`, does have explicit economics:

- Factory-created contracts route a **1.3% primary-sale fee** to the configured
  `standardAuthor` address. This is the standard author's cut for maintaining the
  reference implementation, deployment tooling, registry/indexer support, and
  related ecosystem work.
- If abandoned-capital recovery is enabled, it applies only to recoverable idle
  USDC outside any remaining holder redemption reserve. That recovered amount is
  routed **90% to `recoveryTreasury`** and **10% to `standardAuthor`**.
- The intended purpose of `recoveryTreasury` is to support startup and software
  ecosystem initiatives. Holders' outstanding redemption reserves are preserved
  and remain claimable.
- The factory fee is not a perpetual royalty. It is paid only during active
  primary sales; once an EMBER contract closes into release, slash, or abandoned
  recovery, there is no ongoing payment stream to the standard author. This
  matches the project's philosophy that software funding should end when the
  contract's job is complete.

Developers who do not want the factory economics can deploy `EmberCore`
directly, with recovery disabled.

## Build and test

Install Foundry first:

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

Then install test dependencies and run the suite:

```bash
cd contracts
git clone --branch v1.16.1 --depth 1 https://github.com/foundry-rs/forge-std lib/forge-std
forge build --force
forge test -vvv
forge build --sizes
```

`forge build --sizes` is part of the normal verification flow because
`EmberFactory` is the main bytecode-size risk.

`contracts/foundry.toml` uses `via_ir = true`; without it, the current
`EmberCore`/`EmberFactory` build hits Solidity's stack-too-deep limit.

## EIP status

The draft lives in `eip/erc-ember-eip-draft.md`.

The intended submission covers layers 1-2 only: `IEmber` and `EmberCore`.
`EmberFactory`, `MaintenancePool`, and `IEmberRecovery` are included in the repo
for implementation context, but they are not core ERC conformance.

## Security notes

This code is a draft reference implementation and has not been audited. Known
review areas include stablecoin assumptions, source availability, off-chain
reproducible-build verification, trusted dApp burn authorization, redemption
accounting, factory bytecode size, and optional recovery governance.
`MaintenancePool` timelocks every outflow and governor change (queue → delay →
execute) for the `Steward`, `Multisig`, and `DAO` modes; the `ContributorVote` and
`BurnReceiptVote` modes still depend on external tally contracts that are not yet
implemented. There is no guardian/veto: the timelock provides visibility, not
prevention against a compromised governor.

Production factory deployments must pass real, non-zero `standardAuthor`,
`recoveryTreasury`, and `maintenancePoolFactory` addresses to the `EmberFactory`
constructor (deploy `MaintenancePoolFactory` first). `EmberFactory.deploy` enforces
that the sale token is 6-decimal USDC; `EmberCore` itself stays neutral about
stablecoin decimals.
