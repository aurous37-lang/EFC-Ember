# ERC-EMBER: Burn-to-Bloom Token Standard

> **Author:** Material Synced LLC ([@Gh0stNaSmilee](https://x.com/Gh0stNaSmilee))
> **Status:** Draft v0.3
> **Created:** May 2026
> **Target chains:** Monad, Base, Ethereum, Arbitrum, BNB, and any EVM-equivalent network
> **License:** MIT
> **Changelog:** v0.3 (1) removes dormant sweep from the standard, (2) introduces redemption mode for quorum release so outstanding holders are paid rather than confiscated, (3) defines explicit release states (`released` / `slashed` / live) with grace-until-slashed release, (4) slashes only the reserved tranche instead of the whole balance, (5) freezes commitments and burns once the Ember Phase opens, (6) requires `MaintenancePool` to declare a governance mode at deployment, (7) moves OSI license enforcement out of the core and into the factory as a product policy, and (8) adds optional abandoned-capital recovery after one year of complete on-chain project inactivity, routing recoverable idle capital 90% to an Ember treasury for startup/software initiatives and 10% to the commission recipient while preserving holder redemption reserves. v0.2 introduced the source manifest, dual-trigger release, the optional maintenance pool, and the standard/factory split.

---

## TL;DR

A token standard where access tokens are **consumed on use**. When enough tokens have burned, the project's source code is **cryptographically released** to the community via a structured manifest. The developer is paid as the community uses the product. The contract terminates when the project becomes open source — and any holders who never burned are **paid out**, never confiscated.

The **standard itself is neutral and fee-free.** A separate distribution product — `EmberFactory` — provides a maintained deployment path, registry, indexer, license verification, and tooling in exchange for a disclosed 1.3% primary-sale fee routed to the configured standard-author address. That fee is not a perpetual royalty: it is paid only during active primary sales, and no ongoing standard-author payment stream exists after the contract closes. Developers who want raw EMBER without paying can deploy `EmberCore` directly. Developers who want the managed deployment workflow and services use the factory.

---

## Abstract

ERC-EMBER defines a token contract where:

1. A developer mints a fixed supply of access tokens proportional to their project's scale.
2. The community purchases tokens on a bonding curve in USDC.
3. Each use of the developer's app/platform burns the user's tokens.
4. When a release threshold is met (full burn, or quorum + timeout), a cryptographic commitment forces release of a structured source manifest.
5. The developer receives USDC proportional to burn progress, with a reserved portion gated on source release.
6. If release happens at quorum with tokens still outstanding, the unearned remainder is escrowed for **holder redemption** rather than handed to the developer or burned.
7. After release or slash, the contract becomes a permanent on-chain monument: no further primary revenue, all code public, only redemption claims remain.
8. **Optionally** — via the non-normative `IEmberRecovery` extension, off by default and outside neutral conformance — if a funded project becomes completely inactive for one year, idle USDC outside the remaining redemption reserve may be recovered: 90% to an Ember treasury intended to support startup and software ecosystem initiatives, and 10% to the commission recipient.

The reference package includes the neutral `IEmber` interface and `EmberCore` implementation, the optional `IEmberRecovery` extension, the `EmberFactory` distribution layer, and optional maintenance-pool infrastructure. The base spec carries no mandatory extraction and no balance confiscation; monetization lives primarily in the factory, while abandoned-capital recovery is disabled unless recovery recipients are configured at deployment.

---

## Motivation

Today a developer with an idea has three economic paths:

- **Closed source / SaaS:** charge forever, retain control, no community ownership.
- **Open source from day one:** no revenue, community ownership but no developer compensation.
- **VC-backed:** dilute equity, optimize for exit, often misaligned with users.

None of these reward the pattern most software actually wants: build the thing, get paid fairly for the work, then let the community take it from there.

ERC-EMBER encodes that pattern directly. The developer is paid by the people who get value from the product, capped at a fair amount the market discovers via a bonding curve. When that payment is complete and the access tokens are burned, the code belongs to the community. No subscriptions, no rug-pulls, no equity dilution, no perpetual rent extraction — and no mechanism that lets the system seize a user's holdings.

---

## Architecture Overview

ERC-EMBER is described in four layers. The first two are the neutral public standard. The third is Material Synced's distribution layer. The fourth is an optional community companion.

| Layer | Contract | Purpose | Fee | Who deploys |
|---|---|---|---|---|
| 1 | `IEmber.sol` | Interface only | None | Submitted as EIP |
| 2 | `EmberCore.sol` | Reference implementation | Configurable (default 0) with 5% absolute cap | Anyone, directly |
| 3 | `EmberFactory.sol` (+ `MaintenancePoolFactory.sol`) | Material Synced's distribution layer | 1.3% routed to the configured standard-author address | Devs who want services |
| 4 (optional) | `MaintenancePool.sol` | Post-bloom funding | None | Devs/communities that opt in |

The split matters. The EIP submission is layers 1-2: a clean, fee-free, neutral standard. Material Synced's business is layer 3: deploying maintained `EmberCore` instances with the fee wired in, plus a registry, indexer, web UI, fork lineage tracking, license verification, and customer support. Layer 4 is opt-in and exists only when a community chooses to fund it.

This mirrors the pattern of HTTP/Cloudflare, ERC-20/OpenZeppelin, and TCP-IP/Cisco: free underlying protocol, paid production implementation with services.

---

## Core Mechanic

```
┌─────────────┐   buy USDC   ┌──────────────┐   use app    ┌──────────────┐
│  Community  │ ───────────▶ │  EmberCore   │ ◀─────────── │   dApp logic │
└─────────────┘              │   contract   │   (burns)    └──────────────┘
                             └──────────────┘
                                    │
              ┌─────────── 98.7% USDC (vested by burn %) ────▶ Developer
              │
              ├─────────── 1.3% USDC (if deployed via factory) ▶ Material Synced
              │
              ├─── On release trigger ─▶ Source manifest revealed
              │                          Contract terminated
              │
              └─── Quorum release ─────▶ Outstanding holders redeem
                                         unearned remainder pro-rata
```

---

## Lifecycle

### 1. Deploy
The developer:
- Encrypts the project source code with a key `K`.
- Uploads the encrypted blob to IPFS or Arweave; records the CID.
- Assembles a **source manifest** (see next section) and records its hash on-chain.
- Computes `commitment = keccak256(K)`.
- Deploys `EmberCore` directly or via `EmberFactory`.

### 2. Active Sale Phase
- Buyers approve USDC and call `buy(amount)`.
- The bonding curve quotes a price; the configured fee (if any) routes immediately; the remainder stays in the contract.
- Tokens are standard ERC-20 transferable, so secondary markets work.

### 3. Production Updates (optional, during sale phase)
- The developer can append `SourceUpdate` entries: a new commitment, a new encrypted CID, and an updated manifest hash for each production deployment.
- Each update extends the chain of keys that must be revealed at release. This prevents the "ship v1 publicly, run v7 privately" attack.
- Updates are **frozen once the Ember Phase opens** (`releaseDeadline != 0`). The developer cannot append new commitments during the release window.

### 4. Burn Phase
- Users interact with the dApp.
- The dApp calls `useApp(user, amount)` which burns tokens from the user's balance.
- Developer vested claimable amount grows proportionally.

### 5. Release Triggers (dual path)
Either trigger opens the 30-day Ember Phase window. Opening the window **freezes burns and the developer's vested entitlement** and snapshots the redemption accounting:
- **Full burn path:** `totalBurned == INITIAL_SUPPLY`. Instant, automatic. No tokens remain outstanding, so no redemption pool forms.
- **Quorum + timeout path:** `totalBurned >= 80% of INITIAL_SUPPLY` AND `block.timestamp >= sellOutTimestamp + 730 days`. Anyone can call `forceEmberPhase()`. The unburned remainder enters **redemption mode** (see Anti-Deadlock).

> v0.3 removes the v0.2 "dormant sweep." ERC-EMBER never burns a user's balance for inactivity. Holders can be outvoted by time and quorum, and a disclosed abandoned-capital recovery path may terminate stale claims after one year of complete project inactivity, but no function zeroes a holder's token balance merely because the wallet went quiet.

### 6. Source Release (or Slash)
The neutral standard has two mutually exclusive terminal states: **release** and **slash**. (Deployments that enable the optional `IEmberRecovery` extension add a third settlement path — abandoned-capital recovery, §8; `abandonedRecovered` can terminate a still-live abandoned project, or later sweep stale leftovers after release/slash.)
- **Release (happy path):** Developer calls `release(string[] keys)` providing decryption keys for every committed version. The contract verifies each `keccak256(keys[i]) == commitments[i]`, reveals the keys on-chain, sets `released = true`, and fires `ContractTerminated`. The reserved portion of dev vesting unlocks. **Release is accepted any time before a slash occurs — even past the deadline.** The point is source liberation, not punishing lateness.
- **Slash (terminal):** If 30 days pass without release, anyone calls `slashReserve()`. This sets `slashed = true` and sends **only the reserved tranche** (snapshotted at Ember Phase open) to `0xdEaD`. The developer keeps what they already vested; the redemption pool is untouched. Once slashed, `release()` is no longer accepted through the main path.

### 7. Redemption (quorum releases only)
- When the Ember Phase opens with tokens still outstanding, those holders may call `redeem(amount)` to burn their tokens and claim a fixed pro-rata share of the redemption pool.
- The pool and supply are snapshotted at trigger, so the per-token rate is fixed and independent of whether the developer ultimately releases or is slashed.

### 8. Abandoned Capital Recovery

> **Optional, non-normative extension** (`IEmberRecovery`) — not part of neutral `IEmber` conformance, and off by default. Direct deployments disable it by configuring zero recipients; the factory wires it as product policy. A deployment advertises support via ERC-165 (`type(IEmberRecovery).interfaceId`).

- If a project has USDC in `EmberCore` and records **no on-chain project activity for 365 days**, anyone may call `recoverAbandonedCapital()`.
- Project activity means a buy, app burn, source update, Ember Phase trigger, source release, slash, redemption, or developer withdrawal. Ordinary token transfers do not count as project work.
- Recovery is disabled unless both a recovery treasury and commission recipient were configured at deployment.
- When recovery executes, recoverable idle capital is routed: **90% to the Ember treasury** and **10% to the commission recipient / standard author**.
- The intended purpose of the Ember treasury is to support startup and software ecosystem initiatives.
- Any unredeemed holder redemption reserve is excluded from abandoned-capital recovery and remains in the contract for `redeem()`.
- Recovery is terminal for project activity. It sets `abandonedRecovered = true`; buys, burns, source updates, releases, slashes, and developer withdrawals stop. Holder redemption remains available for the protected redemption reserve.
- This path should be disclosed clearly in UIs. It does not forcibly burn token balances or sweep the redemption reserve.

This mechanism prevents abandoned projects from leaving idle capital trapped forever. The treasury should be described as a startup/software ecosystem initiative fund, developer grant pool, or similar public-purpose treasury, not as venture capital, unless separate legal and governance work supports that framing.

### 9. Monument State
Post-termination, the contract has no further primary economic function. It holds:
- The full chain of revealed keys (if released).
- The IPFS/Arweave CIDs of every encrypted version.
- The source manifest commitments for verification.
- Any unclaimed redemption balance, claimable even if abandoned-capital recovery executes.
- If abandoned recovery executes, a terminal record of the treasury/commission routing for recoverable idle capital.
- A complete on-chain history of every buy, burn, fee payment, dev claim, and redemption.

---

## Source Manifest

A bare encrypted blob isn't a real release — a bad actor could encrypt a stripped, unbuildable, or outdated version and technically satisfy the commitment. The fix is binding the deployer to a structured manifest at deploy time.

### Manifest structure

```solidity
struct SourceManifest {
    bytes32 archiveHash;          // keccak256(encryptedArchiveBytes)
    bytes32 fileTreeMerkleRoot;   // Merkle root over {path, contentHash} leaves
    bytes32 lockfileHash;         // package-lock.json, Cargo.lock, pnpm-lock.yaml, etc.
    bytes32 buildArtifactHash;    // hash of reproducible build output (Docker image, WASM, binary)
    string  spdxLicense;          // SPDX identifier (MIT, Apache-2.0, GPL-3.0, etc.)
    string  manifestCID;          // IPFS/Arweave pointer to the manifest itself
}
```

### Properties

- **Buildability:** The lockfile hash and build artifact hash together let any community member verify that the released source can be built into the production binary. If reproducible builds fail, the slash mechanism applies (extended in a future revision to cover manifest fraud).
- **Legal reusability:** A non-empty SPDX license identifier is required at deploy. **The core does not enforce an on-chain OSI allowlist** — see License Enforcement below.
- **File integrity:** The Merkle root lets verifiers spot-check specific files without downloading the entire archive.
- **Production fidelity:** The build artifact hash binds the manifest to whatever was actually running in production at deployment time.

### Production updates

```solidity
struct SourceUpdate {
    bytes32 commitment;       // keccak256(newDecryptionKey)
    string  encryptedCID;     // IPFS/Arweave pointer to encrypted source
    bytes32 manifestHash;     // hash of an updated SourceManifest
    uint256 timestamp;
}

SourceUpdate[] public updates;

function updateSource(
    bytes32 newCommitment,
    string calldata newCID,
    bytes32 newManifestHash
) external onlyDeveloper {
    require(releaseDeadline == 0, "ember phase: frozen");
    require(newCommitment != bytes32(0), "no commitment");
    require(bytes(newCID).length > 0, "no CID");
    require(newManifestHash != bytes32(0), "no manifest hash");
    updates.push(SourceUpdate(newCommitment, newCID, newManifestHash, block.timestamp));
    emit SourceUpdated(updates.length, newCommitment, newCID);
}

function release(string[] calldata keys) external {
    require(keys.length == updates.length + 1, "key count mismatch");
    require(keccak256(bytes(keys[0])) == originalCommitment, "wrong genesis key");
    for (uint256 i = 0; i < updates.length; i++) {
        require(keccak256(bytes(keys[i+1])) == updates[i].commitment, "wrong update key");
    }
    // ...store all keys, emit events, terminate
}
```

The `releaseDeadline == 0` guard means the chain of commitments is sealed the moment the Ember Phase opens. The developer cannot append a new commitment during the window to complicate or block a valid release.

### License Enforcement

`EmberCore` requires a non-empty SPDX license identifier in the source manifest but **does not enforce an on-chain OSI allowlist.** The core enforces structural validity, not a legal-policy database — an OSI/SPDX allowlist changes over time, has edge cases, and is awkward on-chain because strings are expensive and update authority creates governance baggage.

Factory and registry implementations **MAY** enforce stricter license policies, including OSI-approved SPDX allowlists, before listing or deploying a project. Material Synced's `EmberFactory` enforces the OSI-approved SPDX allowlist as a product policy.

Direct deployments are **self-attested.** Interfaces, registries, and indexers **SHOULD** clearly display whether a deployment was factory-verified or self-attested. "Factory-verified OSI license" is part of the paid service's trust advantage.

---

## Anti-Deadlock Release

Requiring exact `totalBurned == INITIAL_SUPPLY` is brittle. Lost wallets, inactive holders, and hostile actors hoarding tokens can prevent release forever. v0.3 solves this with two paths and a redemption settlement — never by confiscating balances.

### Dual trigger

```solidity
uint256 public sellOutTimestamp;                       // set when last token leaves contract
uint256 public constant RELEASE_QUORUM_BPS = 8_000;    // 80%
uint256 public constant RELEASE_TIMEOUT    = 730 days; // 2 years post-sellout
uint256 public constant EMBER_WINDOW       = 30 days;

function forceEmberPhase() external {
    require(releaseDeadline == 0, "already triggered");
    bool fullBurn   = totalBurned == INITIAL_SUPPLY;
    bool quorumPath = (totalBurned * 10_000) / INITIAL_SUPPLY >= RELEASE_QUORUM_BPS
                      && sellOutTimestamp != 0
                      && block.timestamp >= sellOutTimestamp + RELEASE_TIMEOUT;
    require(fullBurn || quorumPath, "neither path met");
    _openEmberPhase();
}
```

The quorum path means a project can release with up to 20% of tokens still outstanding, provided two years have passed since the sale completed. Two years is enough that holders who genuinely cared have used the product; remaining tokens are presumed dormant or adversarial. Because the quorum path requires `sellOutTimestamp != 0`, there is no unsold inventory in the contract to contaminate the redemption math.

### Redemption mode

When the Ember Phase opens with tokens still outstanding, the unearned remainder of the raise is escrowed for those holders. The developer's entitlement freezes at the trigger; the leftover is **neither paid to the developer nor burned** — it is settled to the people who still hold tokens.

The pool and the eligible supply are snapshotted at trigger so the per-token rate is fixed:

```solidity
function _openEmberPhase() internal {
    triggerBurned   = totalBurned;
    releaseDeadline = block.timestamp + EMBER_WINDOW;

    // Developer's full proportional entitlement is fixed here.
    uint256 devEarned   = (totalRaised * triggerBurned) / INITIAL_SUPPLY;
    reservedAtTrigger   = (devEarned * RESERVED_PCT) / 100;

    // Everything the developer did NOT earn belongs to outstanding holders.
    redemptionPoolTotal   = totalRaised - devEarned;
    redemptionSupplyTotal = _totalSupply;          // unburned, user-held (contract holds 0 post-sellout)
    _touchProjectActivity();

    emit EmberPhase(releaseDeadline);
}

function redemptionQuote(uint256 amount) public view returns (uint256) {
    if (redemptionSupplyTotal == 0) return 0;
    return (redemptionPoolTotal * amount) / redemptionSupplyTotal;
}

function redeem(uint256 amount) external {
    require(releaseDeadline != 0, "ember phase not started");
    require(redemptionSupplyTotal > 0, "no redemption pool");
    require(amount > 0 && _balances[msg.sender] >= amount, "bad amount");
    uint256 payout = redemptionQuote(amount);
    _balances[msg.sender] -= amount;
    _totalSupply  -= amount;
    totalRedeemed += amount;
    redemptionPaid += payout;
    emit Transfer(msg.sender, address(0), amount);
    emit Redeemed(msg.sender, amount, payout);
    require(USDC.transfer(msg.sender, payout), "redeem xfer failed");
}

function redemptionReserveRemaining() public view returns (uint256) {
    if (redemptionSupplyTotal <= totalRedeemed) return 0;
    return redemptionQuote(redemptionSupplyTotal - totalRedeemed);
}
```

Worked example at the 80% quorum trigger:

- `devEarned = totalRaised × 0.8` — the developer's full proportional share (0.64 already vested as unreserved, plus 0.16 reserved, gated on release).
- `redemptionPoolTotal = totalRaised − 0.8·totalRaised = 0.2·totalRaised`.
- `redemptionSupplyTotal = 0.2·INITIAL_SUPPLY` (the unburned 20%).
- Each outstanding token redeems `totalRaised / INITIAL_SUPPLY` — exactly its proportional share of the raise.

The redemption pool is independent of the release/slash/recovery outcome: whether the developer reveals source, gets slashed, or abandoned-capital recovery later executes, the outstanding 20% remains reserved for holders. Rounding dust remains in the contract as part of the monument unless later recovered.

Redemption is pro-rata against the **net project raise**, not any individual buyer's cost basis. Under an ascending bonding curve, late buyers may have paid more per token than the redemption returns; redemption restores each outstanding token's equal share of the pooled raise, not what its current holder personally paid. This is a deliberate simplification — tracking per-token cost basis on-chain would be prohibitively expensive and would reward late speculation over early support.

Redemption claims remain open after the Ember Phase starts. Any redemption, developer withdrawal, release, slash, or other project action resets the inactivity clock; if abandoned-capital recovery later executes, only capital outside the remaining redemption reserve is recoverable.

### Abandoned capital recovery

This is an **optional extension**, exposed through the separate `IEmberRecovery` interface (see Layer 1), **not** part of neutral `IEmber` conformance. Because it routes a commission, it is deliberately excluded from the core standard; a deployment advertises support via ERC-165 (`type(IEmberRecovery).interfaceId`), and direct deployments disable it by configuring zero recipients.

```solidity
uint256 public constant ABANDONMENT_TIMEOUT = 365 days;
uint256 public lastProjectActivity;
bool public abandonedRecovered;
address public immutable recoveryTreasury;
address public immutable recoveryCommissionRecipient;

function recoverAbandonedCapital() external {
    require(!abandonedRecovered, "already recovered");
    require(recoveryTreasury != address(0) && recoveryCommissionRecipient != address(0), "recovery disabled");
    require(block.timestamp > lastProjectActivity + ABANDONMENT_TIMEOUT, "project active");

    uint256 balance = USDC.balanceOf(address(this));
    uint256 protectedRedemptionReserve = redemptionReserveRemaining();
    uint256 recoverable = balance > protectedRedemptionReserve ? balance - protectedRedemptionReserve : 0;
    require(recoverable > 0, "no recoverable capital");

    bool wasTerminated = released || slashed;
    abandonedRecovered = true;
    uint256 commissionAmount = (recoverable * 10) / 100;
    uint256 treasuryAmount = recoverable - commissionAmount;

    require(USDC.transfer(recoveryTreasury, treasuryAmount), "treasury xfer failed");
    require(USDC.transfer(recoveryCommissionRecipient, commissionAmount), "commission xfer failed");
    emit AbandonedCapitalRecovered(treasuryAmount, commissionAmount);
    if (!wasTerminated) {
        emit ContractTerminated(totalBurned, block.timestamp);
    }
}
```

This recovery rule applies to idle USDC outside the remaining holder redemption reserve, not token balances. After a full year with no on-chain evidence of work, usage, release, redemption, slash, or withdrawal, recoverable idle capital is no longer left stranded forever. Factory deployments wire the treasury and commission recipient; direct deployments may disable recovery by passing zero addresses for both recipients.

### Voluntary buyback

The developer (or anyone) can also offer to buy back outstanding tokens at a price they choose, using their own funds, to accelerate full burn. This isn't enforced in the contract; it's a social mechanism. Tokens bought back are burned by calling `useApp(self, amount)` from a deployed redemption contract during the active phase.

---

## Optional Maintenance Pool

The base EMBER contract carries no maintenance lever. Once released, primary revenue ends. This is the right default for a standard whose central promise is "the closed phase ends."

But many projects benefit from post-release maintenance funding: dependency updates, security patches, docs, hosting, moderation. ERC-EMBER provides this as a **separate, opt-in companion contract** with no default extraction and, critically, no control over the core.

> **MaintenancePool is optional community infrastructure. It has no authority over source release, burn accounting, dev vesting, or EMBER termination. Its governance model must be declared at deployment.**

### Properties

- **Separate contract.** `EmberCore` has zero awareness of `MaintenancePool`. The pool can never gate, delay, or condition a release.
- **No claim on leftover funds.** The pool has no access to the core's redemption pool, reserved tranche, or dev vesting. It is funded only by explicit tips and fork royalties.
- **Optional at deploy.** Developer decides whether to spawn one. Most projects won't.
- **Tip-jar pattern.** Anyone can fund the pool anytime. Buyers can elect to tip on top of their purchase via a separate transaction.
- **Declared governance.** The pool's electorate and authority are fixed at deploy via `GovernanceMode`, never left as ambiguous "holders."
- **Fork-lineage royalties.** Descendant forks can voluntarily route a small percentage back as recognition of upstream value.
- **Sunset mechanism.** If the pool sees no claims for 12 months, the declared governance can redistribute remaining funds pro-rata or close the pool entirely.

### Governance modes

The pool must declare exactly one mode at deployment. "Holders can vote" is never used unqualified, because tokens may be burned, redeemed, dormant, or outstanding.

| Mode | Electorate / authority |
|---|---|
| `Steward` | A single named address queues draws (always behind the pool timelock). |
| `Multisig` | A named multisig queues draws (always behind the pool timelock). |
| `DAO` | An external governance contract controls draws. |
| `ContributorVote` | Addresses that funded the pool vote, weighted by contribution. |
| `BurnReceiptVote` | Holders of burn receipts (see Open Questions) vote. |

### Reference structure

```solidity
contract MaintenancePool {
    enum GovernanceMode { Steward, Multisig, DAO, ContributorVote, BurnReceiptVote }
    enum ProposalType { Draw, GovernorChange, Sunset }

    struct Proposal {
        ProposalType ptype;
        address target;   // Draw/Sunset: recipient; GovernorChange: new governor
        uint256 amount;   // Draw only; ignored otherwise
        uint256 eta;      // earliest execution time = queue time + timelockDelay
        bool executed;
        bool canceled;
        string reason;
    }

    IERC20Token    public immutable USDC;
    address        public immutable emberToken;
    GovernanceMode public immutable governanceMode;  // declared at deploy, immutable
    uint256        public immutable timelockDelay;    // bounded [1 day, 30 days]

    address public governor;            // steward / multisig / DAO / external tally contract
    bool    public closed;              // terminal: set by an executed sunset
    uint256 public lastDrawTimestamp;   // sunset inactivity clock (reset only by an executed Draw)
    uint256 public proposalCount;       // proposal ids are 1-based
    mapping(uint256 => Proposal) public proposals;

    uint256 public constant MIN_TIMELOCK_DELAY = 1 days;
    uint256 public constant MAX_TIMELOCK_DELAY = 30 days;
    uint256 public constant SUNSET_INACTIVITY  = 365 days;

    event Tipped(address indexed from, uint256 amount, string memo);
    event ForkRoyalty(address indexed fromFork, uint256 amount);
    event Claimed(address indexed to, uint256 amount, string reason);
    event GovernorChanged(address indexed oldGovernor, address indexed newGovernor);
    event Sunset(address indexed recipient, uint256 amount, string reason);
    event ProposalQueued(
        uint256 indexed id, ProposalType ptype, address target, uint256 amount, uint256 eta, string reason
    );
    event ProposalExecuted(uint256 indexed id);
    event ProposalCanceled(uint256 indexed id);
    event PoolClosed();

    constructor(address _emberToken, address _governor, address _usdc, GovernanceMode _mode, uint256 _timelockDelay) {
        require(_emberToken != address(0) && _usdc != address(0), "bad params");
        require(_governor != address(0), "no governor");
        require(_timelockDelay >= MIN_TIMELOCK_DELAY && _timelockDelay <= MAX_TIMELOCK_DELAY, "bad delay");
        emberToken = _emberToken;
        USDC = IERC20Token(_usdc);
        governanceMode = _mode;
        governor = _governor;   // for ContributorVote/BurnReceiptVote, points at the tally contract
        timelockDelay = _timelockDelay;
        lastDrawTimestamp = block.timestamp;
    }

    modifier onlyGovernor() { require(msg.sender == governor, "not governor"); _; }
    modifier notClosed()    { require(!closed, "pool closed"); _; }

    // Funding stays instant and permissionless.
    function tip(uint256 amount, string calldata memo) external notClosed {
        require(amount > 0, "zero amount");
        require(USDC.transferFrom(msg.sender, address(this), amount), "tip failed");
        emit Tipped(msg.sender, amount, memo);
    }

    function payForkRoyalty(uint256 amount) external notClosed {
        require(amount > 0, "zero amount");
        require(USDC.transferFrom(msg.sender, address(this), amount), "royalty failed");
        emit ForkRoyalty(msg.sender, amount);
    }

    // Outflows and control changes are timelocked: queue -> delay -> execute.
    function queueDraw(uint256 amount, address to, string calldata reason)
        external onlyGovernor notClosed returns (uint256 id)
    {
        require(amount > 0, "zero amount");
        require(to != address(0), "zero recipient");
        id = _queue(ProposalType.Draw, to, amount, reason);
    }

    function queueGovernorChange(address newGovernor) external onlyGovernor notClosed returns (uint256 id) {
        require(newGovernor != address(0), "no governor");
        id = _queue(ProposalType.GovernorChange, newGovernor, 0, "");
    }

    function queueSunset(address recipient, string calldata reason)
        external onlyGovernor notClosed returns (uint256 id)
    {
        require(recipient != address(0), "zero recipient");
        require(_sunsetReady(), "still active");
        id = _queue(ProposalType.Sunset, recipient, 0, reason);
    }

    function _queue(ProposalType ptype, address target, uint256 amount, string memory reason)
        internal returns (uint256 id)
    {
        id = ++proposalCount;
        uint256 eta = block.timestamp + timelockDelay;
        proposals[id] = Proposal(ptype, target, amount, eta, false, false, reason);
        emit ProposalQueued(id, ptype, target, amount, eta, reason);
    }

    // Permissionless once eta is reached.
    function execute(uint256 id) external notClosed {
        require(id > 0 && id <= proposalCount, "unknown proposal");
        Proposal storage p = proposals[id];
        require(!p.executed, "executed");
        require(!p.canceled, "canceled");
        require(block.timestamp >= p.eta, "timelock");
        p.executed = true;

        if (p.ptype == ProposalType.Draw) {
            require(USDC.balanceOf(address(this)) >= p.amount, "insufficient");
            lastDrawTimestamp = block.timestamp;
            emit Claimed(p.target, p.amount, p.reason);
            require(USDC.transfer(p.target, p.amount), "claim failed");
        } else if (p.ptype == ProposalType.GovernorChange) {
            emit GovernorChanged(governor, p.target);
            governor = p.target;
        } else {
            require(_sunsetReady(), "still active"); // re-validate at execution
            closed = true;
            uint256 bal = USDC.balanceOf(address(this));
            emit Sunset(p.target, bal, p.reason);
            emit PoolClosed();
            if (bal > 0) require(USDC.transfer(p.target, bal), "sunset failed");
        }
        emit ProposalExecuted(id);
    }

    // Allowed any time while not executed/canceled, including after eta.
    function cancel(uint256 id) external onlyGovernor {
        require(id > 0 && id <= proposalCount, "unknown proposal");
        Proposal storage p = proposals[id];
        require(!p.executed, "executed");
        require(!p.canceled, "canceled");
        p.canceled = true;
        emit ProposalCanceled(id);
    }

    function _sunsetReady() internal view returns (bool) {
        return block.timestamp > lastDrawTimestamp + SUNSET_INACTIVITY;
    }
}
```

The `Steward`, `Multisig`, and `DAO` modes are fully implemented: every outflow and control change is timelocked (queue → `timelockDelay` → permissionless execute, with governor cancel), funding stays instant, and sunset is a terminal drain-and-close re-validated at execution. `ContributorVote` and `BurnReceiptVote` set `governor` to an external tally contract (out of scope here); `BurnReceiptVote` additionally depends on burn-receipt NFTs, still an open question. There is deliberately no guardian/veto: the timelock gives visibility and reaction time, not prevention against a compromised single governor. The sunset clock (`lastDrawTimestamp`) is reset only by an executed draw — not by tips — so a tip into a winding-down pool can be swept at sunset.

To keep `EmberFactory` under the EIP-170 runtime-size limit, the factory does not embed `MaintenancePool`'s creation bytecode directly. Pool deployment is delegated to a stateless `MaintenancePoolFactory` (a permissionless CREATE wrapper with no state or authority), whose address is passed to the `EmberFactory` constructor:

```solidity
contract MaintenancePoolFactory {
    event PoolCreated(address indexed pool, address indexed emberToken, address governor);

    function create(
        address emberToken,
        address governor,
        address usdc,
        MaintenancePool.GovernanceMode mode,
        uint256 timelockDelay
    ) external returns (address pool) {
        pool = address(new MaintenancePool(emberToken, governor, usdc, mode, timelockDelay));
        emit PoolCreated(pool, emberToken, governor);
    }
}
```

---

## Layer 1: `IEmber.sol` (Interface)

This is the surface area intended for public standards review and EIP submission. The interface and the burn → Ember Phase → release/slash/termination lifecycle are **normative**; pricing curve, sale mechanics, storage backend, fee/treasury policy, and maintenance funding are **implementation-defined**. `IEmber` extends **ERC-165** so deployments can advertise conformance. Abandoned-capital recovery is **not** part of this neutral interface — it is an optional extension (`IEmberRecovery`, below).

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./IERC165.sol";

/// @title IEmber — ERC-EMBER interface (Layer 1, neutral standard)
/// @notice Neutral, fee-free, confiscation-free surface for the burn-to-bloom
///         standard. The interface and the burn → Ember Phase → release/slash/
///         termination lifecycle are normative; pricing curve, sale mechanics,
///         storage backend, fee/treasury policy, and maintenance funding are
///         implementation-defined. Optional abandoned-capital recovery is NOT
///         part of this interface — see the `IEmberRecovery` extension.
interface IEmber is IERC165 {
    // === Source manifest ===
    struct SourceManifest {
        bytes32 archiveHash;
        bytes32 fileTreeMerkleRoot;
        bytes32 lockfileHash;
        bytes32 buildArtifactHash;
        string  spdxLicense;
        string  manifestCID;
    }

    // === Events ===
    event TokensBurnedForUse(address indexed user, uint256 amount, uint256 totalBurned);
    event SourceUpdated(uint256 indexed version, bytes32 commitment, string encryptedCID);
    event EmberPhase(uint256 deadline);
    event SourceReleased(string[] decryptionKeys);
    event ContractTerminated(uint256 finalBurned, uint256 timestamp);
    event Redeemed(address indexed holder, uint256 tokens, uint256 usdc);
    event ReserveSlashed(uint256 usdcAmount);

    // === Read functions ===
    function INITIAL_SUPPLY() external view returns (uint256);
    function totalBurned() external view returns (uint256);
    function released() external view returns (bool);
    function slashed() external view returns (bool);
    function terminated() external view returns (bool);
    function manifest() external view returns (SourceManifest memory);
    function sellOutTimestamp() external view returns (uint256);
    function releaseDeadline() external view returns (uint256);
    function devClaimable() external view returns (uint256);
    function redemptionQuote(uint256 amount) external view returns (uint256);

    // === State-changing functions ===
    function buy(uint256 amount) external;
    function useApp(address user, uint256 amount) external returns (bool);
    function forceEmberPhase() external;
    function release(string[] calldata decryptionKeys) external;
    function slashReserve() external;
    function redeem(uint256 amount) external;
    function withdrawDev() external;
}
```

Any contract claiming EMBER compatibility implements this interface (and ERC-20) and advertises `type(IEmber).interfaceId` via ERC-165. The standard makes no claims about pricing curves, fee structures, treasuries, or distribution — those are implementation details.

### Optional extension: `IEmberRecovery.sol`

Abandoned-capital recovery routes a commission, so it is deliberately kept **out of core conformance** to preserve the neutral standard. It lives in a separate optional interface. A deployment that implements it advertises `type(IEmberRecovery).interfaceId` via ERC-165; one that doesn't is still fully EMBER-conformant. Direct deployments disable recovery (zero recipients); the factory MAY wire it as product policy.

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IEmberRecovery — OPTIONAL abandoned-capital recovery extension
/// @notice NOT part of the neutral ERC-EMBER standard (`IEmber`). This is an
///         optional extension: if a deployment configures a recovery treasury and
///         commission recipient, idle USDC can be swept after a long inactivity
///         window. Direct deployments disable it by configuring no recipients;
///         distribution factories MAY wire it as product policy. Treasury and
///         commission routing are deliberately kept OUT of core ERC conformance.
interface IEmberRecovery {
    event AbandonedCapitalRecovered(uint256 treasuryAmount, uint256 commissionAmount);

    function abandonedRecovered() external view returns (bool);
    function lastProjectActivity() external view returns (uint256);
    function recoveryTreasury() external view returns (address);
    function recoveryCommissionRecipient() external view returns (address);
    function recoverAbandonedCapital() external;
}
```

---

## Layer 2: `EmberCore.sol` (Reference Implementation)

The reference implementation. Fee-free by default. Anyone can deploy directly. Accepts optional fee parameters (capped at 5%) for use by factories or other distribution layers.

> **Canonical source:** the compiling, test-backed contracts live in `contracts/src/`. The blocks below are kept in sync with them but the `.sol` files are authoritative. `EmberCore` implements the neutral `IEmber` (which extends ERC-165) **plus** the optional `IEmberRecovery` extension; public state variables that implement an interface getter carry `override`, and `manifest()` is an explicit getter over a private `_manifest` (a struct auto-getter would silently drop its `string` members).

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./IEmber.sol";
import "./IEmberRecovery.sol";
import "./IERC20Token.sol";

/// @title EmberCore — Reference Implementation of ERC-EMBER (Layer 2)
/// @notice Burn-to-bloom token. The closed-source phase ends when enough tokens
///         have burned. The standard never confiscates balances: on a quorum
///         release with tokens still outstanding, those holders redeem their
///         proportional share of the unearned remainder.
/// @notice Fee-neutral by default. A fee recipient + bps may be set at deploy
///         (capped at 5%) for use by distribution factories.
/// @notice If recovery recipients are configured, one year of complete on-chain
///         project inactivity allows recoverable idle USDC to be routed 90% to
///         a startup/software initiatives treasury and 10% to the commission
///         recipient.
/// @dev    Extracted from ERC-EMBER-v0.3.md. Differences from the spec sketch
///         are compile-correctness only: `override` on public state variables
///         that implement IEmber getters, and an explicit `manifest()` getter
///         (struct auto-getters omit `string` members).
contract EmberCore is IEmber, IEmberRecovery {
    // === Identity ===
    string public name;
    string public symbol;
    uint8  public constant decimals = 0;

    // === Supply ===
    uint256 public immutable override INITIAL_SUPPLY;
    uint256 public override totalBurned;
    uint256 public totalRedeemed;
    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    // === Release mechanics ===
    address public immutable developer;
    address public immutable dApp;
    bytes32 public immutable originalCommitment;
    string  public originalEncryptedCID;
    SourceManifest private _manifest;
    SourceUpdate[] public updates;
    string[] public revealedKeys;
    bool public override released;
    bool public override slashed;
    bool public override abandonedRecovered;
    uint256 public override sellOutTimestamp;
    uint256 public override releaseDeadline;
    uint256 public override lastProjectActivity;

    // === Redemption snapshot (set when Ember Phase opens) ===
    uint256 public triggerBurned;
    uint256 public reservedAtTrigger;
    uint256 public redemptionPoolTotal;
    uint256 public redemptionSupplyTotal;
    uint256 public redemptionPaid;

    struct SourceUpdate {
        bytes32 commitment;
        string  encryptedCID;
        bytes32 manifestHash;
        uint256 timestamp;
    }

    // === Constants ===
    uint256 public constant RELEASE_QUORUM_BPS = 8_000;
    uint256 public constant RELEASE_TIMEOUT    = 730 days;
    uint256 public constant EMBER_WINDOW       = 30 days;
    uint256 public constant ABANDONMENT_TIMEOUT = 365 days;
    uint256 public constant RESERVED_PCT       = 20;
    uint256 public constant MAX_FEE_BPS        = 500;

    // === Economics ===
    IERC20Token public immutable USDC;
    uint256 public immutable basePrice;
    uint256 public immutable slope;
    uint256 public tokensSold;
    uint256 public totalRaised;
    uint256 public devClaimed;

    // === Optional fee (set by factory; zero for direct deployment) ===
    address public immutable feeRecipient;
    uint256 public immutable feeBps;
    uint256 public totalFeesPaid;

    // === Abandoned capital recovery (disabled when both are zero) ===
    address public immutable override recoveryTreasury;
    address public immutable override recoveryCommissionRecipient;

    // === Events (not in IEmber) ===
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event TokensPurchased(address indexed buyer, uint256 amount, uint256 usdcCost, uint256 fee);
    event DevWithdrew(uint256 usdcAmount);
    event FeePaid(uint256 usdcAmount);

    modifier onlyDeveloper() {
        require(msg.sender == developer, "not developer");
        _;
    }

    modifier notAbandoned() {
        require(!abandonedRecovered, "abandoned");
        _;
    }

    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _initialSupply,
        address _developer,
        address _dApp,
        bytes32 _originalCommitment,
        string  memory _originalEncryptedCID,
        SourceManifest memory _srcManifest,
        address _usdc,
        uint256 _basePrice,
        uint256 _slope,
        address _feeRecipient,
        uint256 _feeBps,
        address _recoveryTreasury,
        address _recoveryCommissionRecipient
    ) {
        require(_initialSupply > 0 && _developer != address(0) && _dApp != address(0), "bad params");
        require(_originalCommitment != bytes32(0), "no commitment");
        require(_usdc != address(0), "no USDC");
        require(_feeBps <= MAX_FEE_BPS, "fee exceeds cap");
        require(_feeBps == 0 || _feeRecipient != address(0), "no fee recipient");
        require(
            (_recoveryTreasury == address(0) && _recoveryCommissionRecipient == address(0))
                || (_recoveryTreasury != address(0) && _recoveryCommissionRecipient != address(0)),
            "bad recovery recipients"
        );
        // Structural validity only. OSI allowlist enforcement, if any, lives in the factory/registry.
        require(bytes(_srcManifest.spdxLicense).length > 0, "no license");
        require(_srcManifest.archiveHash != bytes32(0), "no archive hash");
        require(_basePrice > 0 || _slope > 0, "no price");

        name = _name;
        symbol = _symbol;
        INITIAL_SUPPLY = _initialSupply;
        _totalSupply = _initialSupply;
        _balances[address(this)] = _initialSupply;
        emit Transfer(address(0), address(this), _initialSupply);

        developer = _developer;
        dApp = _dApp;
        originalCommitment = _originalCommitment;
        originalEncryptedCID = _originalEncryptedCID;
        _manifest = _srcManifest;
        USDC = IERC20Token(_usdc);
        basePrice = _basePrice;
        slope = _slope;
        feeRecipient = _feeRecipient;
        feeBps = _feeBps;
        recoveryTreasury = _recoveryTreasury;
        recoveryCommissionRecipient = _recoveryCommissionRecipient;
        lastProjectActivity = block.timestamp;
    }

    // ---------- Manifest getter (explicit; struct auto-getter drops strings) ----------
    function manifest() external view override returns (SourceManifest memory) {
        return _manifest;
    }

    // ---------- Bonding curve ----------
    function quote(uint256 amount) public view returns (uint256) {
        uint256 a = tokensSold;
        uint256 b = a + amount;
        return basePrice * amount + (slope * (b * b - a * a)) / 2;
    }

    function buy(uint256 amount) external override notAbandoned {
        require(amount > 0 && _balances[address(this)] >= amount, "sold out");
        uint256 cost = quote(amount);
        require(USDC.transferFrom(msg.sender, address(this), cost), "USDC pull failed");

        uint256 fee = feeBps > 0 ? (cost * feeBps) / 10_000 : 0;
        uint256 toProject = cost - fee;

        tokensSold    += amount;
        totalRaised   += toProject;
        totalFeesPaid += fee;

        if (fee > 0) {
            require(USDC.transfer(feeRecipient, fee), "fee xfer failed");
            emit FeePaid(fee);
        }

        _transfer(address(this), msg.sender, amount);
        if (_balances[address(this)] == 0 && sellOutTimestamp == 0) {
            sellOutTimestamp = block.timestamp;
        }
        _touchProjectActivity();
        emit TokensPurchased(msg.sender, amount, cost, fee);
    }

    // ---------- Burn on use ----------
    function useApp(address user, uint256 amount) external override notAbandoned returns (bool) {
        require(msg.sender == dApp, "only dApp");
        require(releaseDeadline == 0, "ember phase: burns frozen");
        require(_balances[user] >= amount && amount > 0, "bad burn");
        _balances[user] -= amount;
        _totalSupply   -= amount;
        totalBurned    += amount;
        emit Transfer(user, address(0), amount);
        emit TokensBurnedForUse(user, amount, totalBurned);
        _touchProjectActivity();
        if (totalBurned == INITIAL_SUPPLY) {
            _openEmberPhase();
        }
        return true;
    }

    // ---------- Production updates ----------
    function updateSource(
        bytes32 newCommitment,
        string calldata newCID,
        bytes32 newManifestHash
    ) external onlyDeveloper notAbandoned {
        require(releaseDeadline == 0, "ember phase: frozen");
        require(newCommitment != bytes32(0), "no commitment");
        require(bytes(newCID).length > 0, "no CID");
        require(newManifestHash != bytes32(0), "no manifest hash");
        updates.push(SourceUpdate(newCommitment, newCID, newManifestHash, block.timestamp));
        _touchProjectActivity();
        emit SourceUpdated(updates.length, newCommitment, newCID);
    }

    // ---------- Dual-path release trigger ----------
    function forceEmberPhase() external override notAbandoned {
        require(releaseDeadline == 0, "already triggered");
        bool fullBurn = totalBurned == INITIAL_SUPPLY;
        bool quorumPath = (totalBurned * 10_000) / INITIAL_SUPPLY >= RELEASE_QUORUM_BPS
                          && sellOutTimestamp != 0
                          // 2-year post-sellout timeout; seconds of validator drift are immaterial.
                          // forge-lint: disable-next-line(block-timestamp)
                          && block.timestamp >= sellOutTimestamp + RELEASE_TIMEOUT;
        require(fullBurn || quorumPath, "neither path met");
        _openEmberPhase();
    }

    // ---------- Open Ember Phase: freeze + snapshot redemption ----------
    function _openEmberPhase() internal {
        triggerBurned   = totalBurned;
        releaseDeadline = block.timestamp + EMBER_WINDOW;

        uint256 devEarned     = (totalRaised * triggerBurned) / INITIAL_SUPPLY;
        reservedAtTrigger     = (devEarned * RESERVED_PCT) / 100;
        redemptionPoolTotal   = totalRaised - devEarned;
        redemptionSupplyTotal = _totalSupply; // remaining unburned, user-held tokens
        _touchProjectActivity();

        emit EmberPhase(releaseDeadline);
    }

    // ---------- Source release ----------
    function release(string[] calldata decryptionKeys) external override notAbandoned {
        require(!released && !slashed, "terminal");
        require(releaseDeadline != 0, "ember phase not started");
        require(decryptionKeys.length == updates.length + 1, "key count mismatch");
        require(keccak256(bytes(decryptionKeys[0])) == originalCommitment, "wrong genesis key");
        for (uint256 i = 0; i < updates.length; i++) {
            require(keccak256(bytes(decryptionKeys[i + 1])) == updates[i].commitment, "wrong update key");
        }
        released = true;
        _touchProjectActivity();
        for (uint256 i = 0; i < decryptionKeys.length; i++) {
            revealedKeys.push(decryptionKeys[i]);
        }
        emit SourceReleased(decryptionKeys);
        emit ContractTerminated(totalBurned, block.timestamp);
    }

    // ---------- Redemption (quorum releases) ----------
    function redemptionQuote(uint256 amount) public view override returns (uint256) {
        if (redemptionSupplyTotal == 0) return 0;
        return (redemptionPoolTotal * amount) / redemptionSupplyTotal;
    }

    function redeem(uint256 amount) external override {
        require(releaseDeadline != 0, "ember phase not started");
        require(redemptionSupplyTotal > 0, "no redemption pool");
        require(amount > 0 && _balances[msg.sender] >= amount, "bad amount");
        uint256 payout = redemptionQuote(amount);
        _balances[msg.sender] -= amount;
        _totalSupply  -= amount;
        totalRedeemed += amount;
        redemptionPaid += payout;
        _touchProjectActivity();
        emit Transfer(msg.sender, address(0), amount);
        emit Redeemed(msg.sender, amount, payout);
        require(USDC.transfer(msg.sender, payout), "redeem xfer failed");
    }

    function redemptionReserveRemaining() public view returns (uint256) {
        if (redemptionSupplyTotal <= totalRedeemed) return 0;
        return redemptionQuote(redemptionSupplyTotal - totalRedeemed);
    }

    // ---------- Dev vesting ----------
    function devClaimable() public view override returns (uint256) {
        // Burn progress freezes at the trigger once the Ember Phase opens.
        uint256 burned = releaseDeadline == 0 ? totalBurned : triggerBurned;
        uint256 progress = (burned * 1e18) / INITIAL_SUPPLY;
        uint256 unreserved = (totalRaised * progress * (100 - RESERVED_PCT)) / (100 * 1e18);
        uint256 reserved   = released
            ? (totalRaised * progress * RESERVED_PCT) / (100 * 1e18)
            : 0;
        uint256 vested = unreserved + reserved;
        return vested > devClaimed ? vested - devClaimed : 0;
    }

    function withdrawDev() external override onlyDeveloper notAbandoned {
        uint256 amt = devClaimable();
        require(amt > 0, "nothing");
        devClaimed += amt;
        _touchProjectActivity();
        require(USDC.transfer(developer, amt), "dev xfer failed");
        emit DevWithdrew(amt);
    }

    // ---------- Slash (reserved tranche only) ----------
    function slashReserve() external override notAbandoned {
        require(!released && !slashed, "terminal");
        require(releaseDeadline != 0, "not slashable");
        // 30-day ember window; validator timestamp drift cannot meaningfully shift it.
        // forge-lint: disable-next-line(block-timestamp)
        require(block.timestamp > releaseDeadline, "still in window");
        slashed = true;
        _touchProjectActivity();
        if (reservedAtTrigger > 0) {
            require(USDC.transfer(address(0xdEaD), reservedAtTrigger), "slash xfer failed");
            emit ReserveSlashed(reservedAtTrigger);
        }
        emit ContractTerminated(totalBurned, block.timestamp);
    }

    // ---------- Abandoned capital recovery ----------
    function recoverAbandonedCapital() external override {
        require(!abandonedRecovered, "already recovered");
        require(recoveryTreasury != address(0) && recoveryCommissionRecipient != address(0), "recovery disabled");
        // 1-year inactivity gate; seconds of validator drift are immaterial.
        // forge-lint: disable-next-line(block-timestamp)
        require(block.timestamp > lastProjectActivity + ABANDONMENT_TIMEOUT, "project active");

        uint256 balance = USDC.balanceOf(address(this));
        uint256 protectedRedemptionReserve = redemptionReserveRemaining();
        uint256 recoverable = balance > protectedRedemptionReserve ? balance - protectedRedemptionReserve : 0;
        require(recoverable > 0, "no recoverable capital");

        bool wasTerminated = released || slashed;
        abandonedRecovered = true;
        uint256 commissionAmount = (recoverable * 10) / 100;
        uint256 treasuryAmount = recoverable - commissionAmount;

        require(USDC.transfer(recoveryTreasury, treasuryAmount), "treasury xfer failed");
        require(USDC.transfer(recoveryCommissionRecipient, commissionAmount), "commission xfer failed");
        emit AbandonedCapitalRecovered(treasuryAmount, commissionAmount);
        if (!wasTerminated) {
            emit ContractTerminated(totalBurned, block.timestamp);
        }
    }

    // ---------- View helpers ----------
    function terminated() external view override returns (bool) { return released || slashed || abandonedRecovered; }

    // ---------- ERC-165 ----------
    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return interfaceId == type(IERC165).interfaceId
            || interfaceId == type(IEmber).interfaceId
            || interfaceId == type(IEmberRecovery).interfaceId;
    }
    function updateCount() external view returns (uint256) { return updates.length; }
    function revealedKeyCount() external view returns (uint256) { return revealedKeys.length; }

    // ---------- ERC20 surface ----------
    function totalSupply() external view returns (uint256) { return _totalSupply; }
    function balanceOf(address a) external view returns (uint256) { return _balances[a]; }
    function allowance(address o, address s) external view returns (uint256) { return _allowances[o][s]; }
    function approve(address s, uint256 v) external returns (bool) {
        _allowances[msg.sender][s] = v;
        emit Approval(msg.sender, s, v);
        return true;
    }
    function transfer(address to, uint256 v) external returns (bool) { _transfer(msg.sender, to, v); return true; }
    function transferFrom(address f, address t, uint256 v) external returns (bool) {
        uint256 a = _allowances[f][msg.sender];
        require(a >= v, "allowance");
        if (a != type(uint256).max) _allowances[f][msg.sender] = a - v;
        _transfer(f, t, v);
        return true;
    }
    function _transfer(address f, address t, uint256 v) internal {
        require(f != address(0) && t != address(0), "zero address");
        require(_balances[f] >= v, "balance");
        unchecked { _balances[f] -= v; _balances[t] += v; }
        emit Transfer(f, t, v);
    }

    function _touchProjectActivity() internal {
        lastProjectActivity = block.timestamp;
    }
}
```

This is the artifact the EIP cites. It is neutral, test-backed bytecode anyone can deploy with zero fee and recovery disabled — and with no path that lets the system seize a holder's token balance.

---

## Layer 3: `EmberFactory.sol` (Material Synced's Product)

The factory deploys `EmberCore` instances with Material Synced's fee parameters wired in, enforces the OSI license allowlist as a product policy, and registers them in an indexer-backed catalog. This is where the business is.

### What the factory provides

1. **Maintained deployment path** — Material Synced can coordinate reviews, audits, and release provenance for factory deployments.
2. **License verification** — factory-enforced OSI-approved SPDX allowlist; deployments are labeled "factory-verified" vs. "self-attested."
3. **Registry listing** — every deployment is indexed with metadata for discovery.
4. **Indexer + analytics** — historical burn rates, sale velocity, redemption activity, fork lineage.
5. **Web interface** — buyer-facing UI for token purchase, dev dashboard, claim and redemption flows.
6. **Customer support** — for both devs and buyers.
7. **Marketing reach** — featured project slots, social distribution.
8. **Fork lineage tracking** — when an EMBER project blooms and gets forked, the registry records the parent → child relationship and notifies the upstream community.

In exchange, the factory deploys `EmberCore` with `feeRecipient = STANDARD_AUTHOR` and `feeBps = 130` (1.3%). This is a primary-sale fee only, not a perpetual royalty: after the EMBER contract closes through release, slash, or abandoned recovery, no ongoing standard-author payment stream remains. The factory also wires abandoned-capital recovery to `RECOVERY_TREASURY` (90%, intended for startup/software ecosystem initiatives) and `STANDARD_AUTHOR` (10% one-time recovery commission).

### Factory contract

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./EmberCore.sol";
import "./MaintenancePool.sol";
import "./MaintenancePoolFactory.sol";
import "./IEmber.sol";
import "./IERC20Token.sol";

/// @title EmberFactory — Material Synced's monetized distribution (Layer 3)
/// @notice Deploys EmberCore with the 1.3% fee wired in, enforces an OSI-approved
///         SPDX allowlist as a product policy, and registers deployments.
contract EmberFactory {
    address public immutable STANDARD_AUTHOR;
    address public immutable RECOVERY_TREASURY;
    MaintenancePoolFactory public immutable POOL_FACTORY;
    uint256 public constant FACTORY_FEE_BPS = 130; // 1.3%

    address public owner;
    address public pendingOwner;
    // Product policy: OSI-approved SPDX allowlist keyed by keccak256(identifier).
    mapping(bytes32 => bool) public approvedLicense;

    struct DeploymentInfo {
        address developer;
        uint256 deployedAt;
        address maintenancePool;  // address(0) if none
        bytes32 parentDeployment; // for fork lineage; 0 if original
        bool    licenseVerified;
    }

    address[] public deployments;
    mapping(address => DeploymentInfo) public info;
    mapping(address => address[]) public devProjects;

    event Deployed(
        address indexed token,
        address indexed developer,
        address maintenancePool,
        bytes32 parentDeployment,
        bool licenseVerified
    );
    event LicenseApprovalSet(bytes32 indexed licenseHash, bool approved);
    event OwnershipTransferStarted(address indexed oldOwner, address indexed pendingOwner);
    event OwnershipTransferred(address indexed oldOwner, address indexed newOwner);

    modifier onlyOwner() { require(msg.sender == owner, "not owner"); _; }

    constructor(address standardAuthor, address recoveryTreasury, address poolFactory) {
        require(standardAuthor != address(0), "no standard author");
        require(recoveryTreasury != address(0), "no recovery treasury");
        require(poolFactory != address(0), "no pool factory");
        STANDARD_AUTHOR = standardAuthor;
        RECOVERY_TREASURY = recoveryTreasury;
        POOL_FACTORY = MaintenancePoolFactory(poolFactory);
        owner = msg.sender;
    }

    /// @notice Material Synced curates the OSI-approved SPDX allowlist off-chain
    ///         and mirrors it here. Product policy, not part of the standard.
    function setLicenseApproval(string calldata spdx, bool approved) external onlyOwner {
        bytes32 h = keccak256(bytes(spdx));
        approvedLicense[h] = approved;
        emit LicenseApprovalSet(h, approved);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "no owner");
        pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner, newOwner);
    }

    function acceptOwnership() external {
        require(msg.sender == pendingOwner, "not pending owner");
        address oldOwner = owner;
        owner = msg.sender;
        pendingOwner = address(0);
        emit OwnershipTransferred(oldOwner, msg.sender);
    }

    function deploy(
        string memory name,
        string memory symbol,
        uint256 initialSupply,
        address dApp,
        bytes32 originalCommitment,
        string memory originalEncryptedCID,
        IEmber.SourceManifest memory srcManifest,
        address usdc,
        uint256 basePrice,
        uint256 slope,
        bool spawnMaintenancePool,
        MaintenancePool.GovernanceMode poolMode,
        address poolGovernor,
        uint256 poolTimelockDelay,
        bytes32 parentDeployment
    ) external returns (address ember, address pool) {
        // Product policy: factory deployments must carry an OSI-approved license.
        require(approvedLicense[keccak256(bytes(srcManifest.spdxLicense))], "license not OSI-approved");
        // Product policy: the sale token must be 6-decimal USDC (the bonding curve assumes 6 decimals).
        require(IERC20Token(usdc).decimals() == 6, "USDC decimals");

        ember = address(new EmberCore(
            name,
            symbol,
            initialSupply,
            msg.sender,
            dApp,
            originalCommitment,
            originalEncryptedCID,
            srcManifest,
            usdc,
            basePrice,
            slope,
            STANDARD_AUTHOR,
            FACTORY_FEE_BPS,
            RECOVERY_TREASURY,
            STANDARD_AUTHOR
        ));

        if (spawnMaintenancePool) {
            pool = POOL_FACTORY.create(ember, poolGovernor, usdc, poolMode, poolTimelockDelay);
        }

        deployments.push(ember);
        info[ember] = DeploymentInfo({
            developer: msg.sender,
            deployedAt: block.timestamp,
            maintenancePool: pool,
            parentDeployment: parentDeployment,
            licenseVerified: true
        });
        devProjects[msg.sender].push(ember);

        emit Deployed(ember, msg.sender, pool, parentDeployment, true);
    }

    function deploymentCount() external view returns (uint256) {
        return deployments.length;
    }

    function projectsByDeveloper(address dev) external view returns (address[] memory) {
        return devProjects[dev];
    }
}
```

### Why direct deployment doesn't break this

A competitor could deploy `EmberCore` directly with `feeRecipient = 0`. That's fine — the standard explicitly allows it. What they don't get:

- Review, audit, and release-provenance reputation
- Factory-verified OSI license labeling
- Registry listing and discoverability
- The indexer and dashboard
- The web buyer UI
- Customer support
- Fork lineage tracking

The 1.3% buys adoption velocity and credibility. The direct-deploy path saves $13 per $1,000 raised but gives up the factory's distribution services. Standard distribution economics.

---

## Pricing Calibration

Token has 0 decimals; USDC has 6 decimals (1 USDC = 1,000,000 base units). All bonding curve parameters are in USDC base units.

### Flat-price example
- `INITIAL_SUPPLY = 1_000_000`
- `basePrice = 10_000` → $0.01 per token
- `slope = 0`
- Gross raise = $10,000
- Factory fee (1.3%) = $130, Dev pool = $9,870

### Linear-ascending example (price doubles over the curve)
- `INITIAL_SUPPLY = 1_000_000`
- `basePrice = 10_000`
- `slope = 10`
- Final per-token price = $0.02
- Gross raise ≈ $15,000
- Factory fee ≈ $195, Dev pool ≈ $14,805

### Quorum-release settlement example
- Gross raise (net of fee) `totalRaised = $9,870`
- Quorum trigger at 80% burned
- Developer entitlement frozen at `0.8 × $9,870 = $7,896` (of which `$1,579.20` reserved, gated on release)
- Redemption pool = `$9,870 − $7,896 = $1,974`, split across the outstanding 200,000 tokens → `$0.00987` per token (each token's proportional share of the raise)

### Per-chain USDC addresses
| Chain | USDC address |
|---|---|
| Monad | (set per Monad mainnet deployment) |
| Base | `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` |
| Ethereum | `0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48` |
| Arbitrum | `0xaf88d065e77c8cC2239327C5EDb3A432268e5831` |

### Per-project network revenue (factory-deployed)
| Projects deployed | Gross at $300k avg | Factory revenue (1.3%) |
|---|---|---|
| 10 | $3M | $39,000 |
| 100 | $30M | $390,000 |
| 1,000 | $300M | $3.9M |
| 10,000 | $3B | $39M |

---

## Comparison to Existing Standards

| Property | Clanker (v3) | Bankr | ERC-EMBER (factory) | ERC-EMBER (direct) |
|---|---|---|---|---|
| Fee model | 1% per swap, forever | 1.2% per swap, forever | 1.3% on primary sale | 0% |
| Fee recipient | Protocol + creator + interface | Protocol + creator + LLM | Material Synced | None |
| Source release | Closed | Closed | Manifest + dual trigger | Manifest + dual trigger |
| Terminates? | No | No | Yes | Yes |
| Confiscates idle holders? | n/a | n/a | No (redeemed) | No (redeemed) |
| Token utility | Speculation | Speculation | Access + ownership | Access + ownership |
| Open standard? | Proprietary | Proprietary | Yes (`IEmber`) | Yes (`IEmber`) |

Clanker and Bankr monetize speculation perpetually. EMBER monetizes utility and exits when utility is fulfilled. The fee-free direct-deploy path is a real option for projects that don't want the factory's services.

---

## Path to Adoption

The four-layer architecture clarifies the path significantly. Material Synced submits **layers 1-2 only** to the EIP process. Layer 3 launches as a product. Layer 4 is community infrastructure.

### Formal track (EIP submission of `IEmber` + `EmberCore`)

1. **Public standards pre-discussion** — required before formal submission. The standard being fee-free and confiscation-free at this layer removes the two most common objections.
2. **Draft per EIP-1** with motivation, specification, rationale, backwards compatibility, reference implementation (`EmberCore`), and security considerations (manifest commitment, dual triggers, redemption settlement, slash mechanics).
3. **PR to `github.com/ethereum/ercs`** — note the ERC repo split from the main EIPs repo.
4. **Status progression:** Draft → Review → Last Call (~14 day window) → Final.

### Adoption track (what actually matters)

1. **Publish `IEmber` + `EmberCore` on GitHub** — MIT-licensed, with Foundry tests and a clear audit path before production use.
2. **Deploy 2-3 live EMBER projects via the factory** — Real mainnet activity is more persuasive than a forum proposal.
3. **Write the EIP after** — with deployment data and live adoption in the rationale section.
4. **Launch `EmberFactory` as a product** — separately marketed as Material Synced's distribution layer with paid services.
5. **Partner with the Monad Foundation** — get listed in ecosystem standards, blogged about, featured. A Monad-endorsed standard with Base deployments compounds faster than waiting on EIP Final status.

### EVM-equivalence note

`EmberCore` and `EmberFactory` work on every EVM chain (Monad, Base, Ethereum, Arbitrum, BNB) without modification. One implementation target, every chain.

---

## Security Considerations

- **No balance confiscation.** v0.3 removes dormant sweep; no function can zero out a holder's token balance. Abandoned-capital recovery can terminate stale project activity after one year of complete project inactivity, but it does not burn holder balances or sweep the remaining redemption reserve.
- **Frozen accounting at trigger.** `_openEmberPhase()` snapshots dev entitlement, the reserved tranche, and the redemption pool/supply. Burns (`useApp`) and commitment appends (`updateSource`) are blocked thereafter, so the snapshot cannot be moved.
- **Reserved-only slash.** `slashReserve()` burns exactly `reservedAtTrigger`, never the contract's whole balance, protecting the redemption pool and unclaimed dev unreserved vesting.
- **Solvency.** At any point after trigger before abandoned recovery, contract balance `= totalRaised − devClaimed − redemptionPaid − (slashed ? reservedAtTrigger : 0)`. Dev claims cap at `devEarned`; redemption claims cap at `redemptionPoolTotal`; these are disjoint, so the contract is always solvent for outstanding claims. If abandoned recovery executes, the redemption quote for still-unredeemed tokens is protected and remains available to holders.
- **Terminal and settlement states.** `released` and `slashed` are mutually exclusive release outcomes. `abandonedRecovered` is a settlement flag that can either terminate a live abandoned project or sweep stale leftovers after release/slash. `release()` and `slashReserve()` both require `!released && !slashed && !abandonedRecovered`, preventing release/slash after recovery. Late release is accepted until a slash or abandonment recovery actually occurs.
- **Redemption rate is fixed.** Both numerator (`redemptionPoolTotal`) and denominator (`redemptionSupplyTotal`) are snapshots, so redeeming early vs. late yields the same per-token payout and there is no race.
- **Abandoned recovery is activity-gated.** Buy, burn, update, trigger, release, slash, redeem, and developer withdrawal reset `lastProjectActivity`; ordinary token transfers do not. Recovery is disabled unless both recovery recipients are configured at deploy, and only USDC outside the remaining redemption reserve is recoverable.

---

## Open Design Questions

1. **Encrypted source storage redundancy** — IPFS pinning is the soft spot. Arweave + Filecoin redundancy preferred. Should the manifest commit to multiple CIDs across providers?
2. **Reproducible build verification** — should the contract include a way for verifiers to challenge that the released source rebuilds to the committed `buildArtifactHash`, with bond-and-slash?
3. **Bonding curve shape** — Linear is simple. Logistic curves or Uniswap V3-LP-as-curve give different price discovery. Should `IEmber` mandate a specific shape, or leave it implementation-defined?
4. **Burner receipts** — Should burning tokens mint a soulbound NFT receipt? Useful for governance in successor DAOs and as the electorate for `MaintenancePool`'s `BurnReceiptVote` mode.
5. **Permit2 / EIP-2612** — Single-tx buy flow on chains where USDC supports gasless approvals.
6. **Recovery governance** — should the Ember startup/software initiatives treasury be a multisig, DAO, foundation wallet, or grant program contract?
7. **Redemption dust** — integer division leaves small unclaimable residue. Acceptable as monument dust, or sweep through abandoned-capital recovery after a long timeout?
8. **MaintenancePool tally contracts** — reference implementations for `ContributorVote` and `BurnReceiptVote`, including snapshotting and quorum rules.

---

## Next Pieces

### Foundry test suite
Full coverage of:
- Bonding curve math (overflow safety, rounding behavior)
- Buy/burn/release flows including multi-version key chains
- Dual-trigger forceEmberPhase paths (full burn, quorum + timeout)
- Redemption math: snapshot correctness, fixed-rate payout, solvency, dust
- Freeze invariants: `useApp` and `updateSource` revert once `releaseDeadline != 0`
- Slash mechanics: reserved-tranche-only burn, redemption pool untouched, `slashed` state
- Late release accepted before slash, rejected after
- Fee routing for factory-deployed vs direct deployments
- Manifest validation (empty license, zero hashes)
- Factory license allowlist enforcement and `licenseVerified` labeling

### Audit
Before mainnet deployment with real funds, audit from OpenZeppelin, Trail of Bits, or Spearbit covering bonding curve math, USDC integration, vesting calculations, manifest commitments, dual triggers, redemption accounting, and slash mechanism.

### EIP draft document
Formal ERC-XXXX writeup for public standards discussion, covering only `IEmber` + `EmberCore`. The factory is mentioned only as one possible implementation.

### Factory infrastructure
- Indexer (Ponder or Subgraph) covering all deployments, including redemption activity
- Registry frontend at `ember.materialsynced.com` with factory-verified vs. self-attested labels
- Developer dashboard for managing source updates and claiming vested USDC
- Buyer-facing token purchase UI with one-click approve + buy, plus a redemption claim flow
- Fork lineage explorer

### MaintenancePool tally contracts
Timelock governance for `Steward`, `Multisig`, and `DAO` is implemented in `MaintenancePool` (queue → delay → execute, with terminal sunset). Remaining work: external tally contracts for `ContributorVote` (contribution-weighted) and `BurnReceiptVote` (pending burn-receipt NFTs), plus any per-mode sunset-vote wiring layered on top of the existing timelock.

---

## Appendix: Glossary

- **Ember Phase** — The 30-day window between release trigger and required source reveal. Opening it freezes burns, freezes dev vesting, and snapshots the redemption accounting.
- **Bloom** — The act of releasing the source code chain via `release(keys[])`.
- **Source Manifest** — Structured commitment binding the deployer to a specific buildable, licensed source archive.
- **Source Commitment** — `keccak256(decryptionKey)` recorded immutably at deploy and at every production update.
- **Reserved Portion** — 20% of the developer's vested entitlement, snapshotted at trigger and locked until `release()` is called with valid keys for all versions.
- **Slash** — Permanent burn of the reserved tranche (only) if the release deadline passes without a valid reveal. Sets the `slashed` terminal state.
- **Redemption Mode** — On a quorum release with tokens outstanding, holders burn their tokens to claim a fixed pro-rata share of the unearned remainder. Replaces the v0.2 dormant sweep.
- **Redemption Pool** — `totalRaised − devEarnedAtTrigger`, escrowed for outstanding holders.
- **Abandoned Capital Recovery** — After 365 days of no project activity, recoverable USDC outside the remaining redemption reserve can be routed 90% to the Ember treasury for startup/software ecosystem initiatives and 10% to the commission recipient, if recovery was configured at deploy.
- **Dual Trigger** — Release path that opens via either full burn or quorum-plus-timeout.
- **Terminal / Settlement States** — `released` (valid reveal) and `slashed` (deadline passed, reserve burned) are mutually exclusive release outcomes. `abandonedRecovered` records idle-capital recovery and may occur by itself or after release/slash.
- **Monument State** — The contract's terminal condition: no further primary economic activity, outstanding redemption claims against any protected redemption reserve, plus full on-chain history.
- **Factory-Verified / Self-Attested** — Whether a deployment's license was checked against the factory's OSI allowlist or asserted by a direct deployer.
- **Factory-Deployed** — An `EmberCore` instance created via `EmberFactory`, with 1.3% routing to Material Synced.
- **Direct-Deployed** — An `EmberCore` instance created without the factory, with zero fee.

---

## References

- Ethereum Improvement Proposals: https://eips.ethereum.org
- EIP-1 (process meta-doc): https://eips.ethereum.org/EIPS/eip-1
- ERC submissions repo: https://github.com/ethereum/ercs
- Public standards discussion: not yet opened
- SPDX license list: https://spdx.org/licenses/
- OSI-approved licenses: https://opensource.org/licenses
- Clanker (1% per-swap fee model, Base): https://www.clanker.world
- Bankr (1.2% per-swap fee model, Base/Solana): https://bankr.bot
- Monad documentation: https://docs.monad.xyz

---

*Drafted for Material Synced LLC. The `IEmber` interface and `EmberCore` reference implementation are intended for EIP submission. `EmberFactory` and `MaintenancePool` are Material Synced products and community infrastructure respectively.*
