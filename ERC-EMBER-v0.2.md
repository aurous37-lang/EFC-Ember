# ERC-EMBER: Burn-to-Bloom Token Standard

> **Archived draft:** This v0.2 document is retained for history only. Use
> `ERC-EMBER-v0.3.md` and `contracts/src/` as the current canonical reference.

> **Author:** Material Synced LLC ([@Gh0stNaSmilee](https://x.com/Gh0stNaSmilee))
> **Status:** Draft v0.2
> **Created:** May 2026
> **Target chains:** Monad, Base, Ethereum, Arbitrum, BNB, and any EVM-equivalent network
> **License:** MIT
> **Changelog:** v0.2 introduces (1) source manifest commitments, (2) dual-trigger release mechanics, (3) optional maintenance pool, and (4) clean separation between the neutral standard and the monetized factory.

---

## TL;DR

A token standard where access tokens are **consumed on use**. When enough tokens have burned, the project's source code is **cryptographically released** to the community via a structured manifest. The developer is paid as the community uses the product. The contract terminates when the project becomes open source.

The **standard itself is neutral and fee-free.** A separate distribution product — `EmberFactory` — provides a maintained deployment path, a registry, indexer, and tooling in exchange for a 1.3% sale fee. Developers who want raw EMBER without paying can deploy `EmberCore` directly. Developers who want the managed deployment workflow and services use the factory.

---

## Abstract

ERC-EMBER defines a token contract where:

1. A developer mints a fixed supply of access tokens proportional to their project's scale.
2. The community purchases tokens on a bonding curve in USDC.
3. Each use of the developer's app/platform burns the user's tokens.
4. When a release threshold is met (full burn, or quorum + timeout), a cryptographic commitment forces release of a structured source manifest.
5. The developer receives USDC proportional to burn progress, with a reserved portion gated on source release.
6. After release, the contract becomes a permanent on-chain monument: no further revenue, all code public.

The standard is implemented as three artifacts (`IEmber`, `EmberCore`, `EmberFactory`) plus one optional companion (`MaintenancePool`). The base spec carries no extraction; monetization lives only in the factory, which competes on services.

---

## Motivation

Today a developer with an idea has three economic paths:

- **Closed source / SaaS:** charge forever, retain control, no community ownership.
- **Open source from day one:** no revenue, community ownership but no developer compensation.
- **VC-backed:** dilute equity, optimize for exit, often misaligned with users.

None of these reward the pattern most software actually wants: build the thing, get paid fairly for the work, then let the community take it from there.

ERC-EMBER encodes that pattern directly. The developer is paid by the people who get value from the product, capped at a fair amount the market discovers via a bonding curve. When that payment is complete and the access tokens are burned, the code belongs to the community. No subscriptions, no rug-pulls, no equity dilution, no perpetual rent extraction.

---

## Architecture Overview

ERC-EMBER is delivered as four contracts. The first two are the neutral public standard. The third is Material Synced's monetized distribution. The fourth is an optional community companion.

| Layer | Contract | Purpose | Fee | Who deploys |
|---|---|---|---|---|
| 1 | `IEmber.sol` | Interface only | None | Submitted as EIP |
| 2 | `EmberCore.sol` | Reference implementation | Configurable (default 0) with 5% absolute cap | Anyone, directly |
| 3 | `EmberFactory.sol` | Material Synced's product | 1.3% routed to MS | Devs who want services |
| 4 (optional) | `MaintenancePool.sol` | Post-bloom funding | None | Devs/communities that opt in |

The split matters. The EIP submission is layers 1-2: a clean, fee-free, neutral standard. Material Synced's business is layer 3: deploying maintained `EmberCore` instances with the fee wired in, plus a registry, indexer, web UI, fork lineage tracking, and customer support. Layer 4 is opt-in and exists only when a community chooses to fund it.

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
              └─── On release trigger ─▶ Source manifest revealed
                                         Contract terminated
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

### 4. Burn Phase
- Users interact with the dApp.
- The dApp calls `useApp(user, amount)` which burns tokens from the user's balance.
- Developer vested claimable amount grows proportionally.

### 5. Release Triggers (dual path)
Either trigger opens the 30-day ember phase window:
- **Full burn path:** `totalBurned == INITIAL_SUPPLY`. Instant.
- **Quorum + timeout path:** `totalBurned >= 80% of INITIAL_SUPPLY` AND `block.timestamp >= sellOutTimestamp + 730 days`. Anyone can call `forceEmberPhase()`.

Plus a separate anti-deadlock safety valve:
- **Dormant sweep:** Tokens in wallets with no on-chain activity for 3+ years can be burned by anyone via `sweepDormant(address[] calldata dead)` with proof of inactivity.

### 6. Source Release (or Slash)
- **Happy path:** Developer calls `release(string[] keys)` providing decryption keys for every committed version. Contract verifies each `keccak256(keys[i]) == commitments[i]`. Reveals the keys on-chain. `ContractTerminated` fires. Reserved portion of dev vesting unlocks.
- **Slash path:** If 30 days pass without release, anyone calls `slashReserve()`. Reserved USDC is sent to `0xdEaD` and burned. Developer keeps what they already claimed (proportional to burn progress) but loses the reserve.

### 7. Monument State
Post-release, the contract has no further economic function. It holds:
- The full chain of revealed keys.
- The IPFS/Arweave CIDs of every encrypted version.
- The source manifest commitments for verification.
- A complete on-chain history of every buy, burn, fee payment, and dev claim.

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
    string  spdxLicense;          // SPDX-approved identifier (MIT, Apache-2.0, GPL-3.0, etc.)
    string  manifestCID;          // IPFS/Arweave pointer to the manifest itself
}
```

### Properties

- **Buildability:** The lockfile hash and build artifact hash together let any community member verify that the released source can be built into the production binary. If reproducible builds fail, the slash mechanism applies (extended in v0.3 to cover manifest fraud).
- **Legal reusability:** SPDX license is mandatory and must be from the OSI-approved list. Required at deploy. Custom proprietary licenses are rejected by the constructor.
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
    require(!released, "already released");
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

This eliminates the gap between what was deployed at genesis and what's actually running today. The chain of commitments must be revealed in full.

---

## Anti-Deadlock Release

Requiring exact `totalBurned == INITIAL_SUPPLY` is brittle. Lost wallets, inactive holders, and hostile actors hoarding tokens can prevent release forever. The fix is multiple paths.

### Dual trigger

```solidity
uint256 public sellOutTimestamp;                       // set when last token leaves contract
uint256 public constant RELEASE_QUORUM_BPS = 8_000;    // 80%
uint256 public constant RELEASE_TIMEOUT    = 730 days; // 2 years post-sellout

function forceEmberPhase() external {
    require(releaseDeadline == 0, "already triggered");
    bool fullBurn   = totalBurned == INITIAL_SUPPLY;
    bool quorumPath = (totalBurned * 10_000) / INITIAL_SUPPLY >= RELEASE_QUORUM_BPS
                      && sellOutTimestamp != 0
                      && block.timestamp >= sellOutTimestamp + RELEASE_TIMEOUT;
    require(fullBurn || quorumPath, "neither path met");
    releaseDeadline = block.timestamp + 30 days;
    emit EmberPhase(releaseDeadline);
}
```

The quorum path means a project can release with up to 20% of tokens still outstanding, provided two years have passed since the sale completed. Two years is enough that holders who genuinely cared have used the product; remaining tokens are presumed dormant or adversarial.

### Dormant sweep

```solidity
uint256 public constant DORMANCY_THRESHOLD = 1095 days; // 3 years

function sweepDormant(address[] calldata wallets) external {
    for (uint256 i = 0; i < wallets.length; i++) {
        require(_balances[wallets[i]] > 0, "no balance");
        require(_lastActivity[wallets[i]] + DORMANCY_THRESHOLD < block.timestamp, "not dormant");
        uint256 swept = _balances[wallets[i]];
        _balances[wallets[i]] = 0;
        _totalSupply -= swept;
        totalBurned  += swept;
        emit Transfer(wallets[i], address(0), swept);
        emit DormantSwept(wallets[i], swept);
    }
}
```

Activity is tracked via `_lastActivity[address]` updated on every transfer/approve/balance change. Three years of no on-chain activity is strong evidence the wallet is dead. The sweep doesn't compensate the holder — that's the cost of complete inactivity — but it doesn't transfer their funds to anyone either. Pure burn.

### Voluntary buyback

The developer (or anyone) can also offer to buy back outstanding tokens at a price they choose, using their own funds, to accelerate release. This isn't enforced in the contract; it's a social mechanism. Tokens bought back are burned by calling `useApp(self, amount)` from a deployed redemption contract.

---

## Optional Maintenance Pool

The base EMBER contract carries no maintenance lever. Once released, revenue ends. This is the right default for a standard whose central promise is "the closed phase ends."

But many projects benefit from post-release maintenance funding: dependency updates, security patches, docs, hosting, moderation. ERC-EMBER provides this as a **separate, opt-in companion contract** with no default extraction.

### Properties

- **Separate contract.** `EmberCore` has zero awareness of `MaintenancePool`.
- **Optional at deploy.** Developer decides whether to spawn one. Most projects won't.
- **Tip-jar pattern.** Anyone can fund the pool anytime. Buyers can elect to tip on top of their purchase via a separate transaction.
- **Transparent stewardship.** Steward (multisig, DAO, individual) draws funds with on-chain reason strings.
- **Fork-lineage royalties.** Descendant forks can voluntarily route a small percentage back as recognition of upstream value.
- **Sunset mechanism.** If the pool sees no claims for 12 months, holders can vote to redistribute remaining funds pro-rata or close the pool entirely.

### Reference structure

```solidity
contract MaintenancePool {
    IERC20Token public immutable USDC;
    address     public immutable emberToken;
    address     public steward;
    uint256     public lastClaimTimestamp;

    event Tipped(address indexed from, uint256 amount, string memo);
    event Claimed(address indexed to, uint256 amount, string reason);
    event ForkRoyalty(address indexed fromFork, uint256 amount);
    event StewardChanged(address indexed oldSteward, address indexed newSteward);
    event Sunset(uint256 redistributedAmount);

    modifier onlySteward() { require(msg.sender == steward, "not steward"); _; }

    function tip(uint256 amount, string calldata memo) external {
        require(USDC.transferFrom(msg.sender, address(this), amount), "tip failed");
        emit Tipped(msg.sender, amount, memo);
    }

    function claim(uint256 amount, address to, string calldata reason) external onlySteward {
        lastClaimTimestamp = block.timestamp;
        require(USDC.transfer(to, amount), "claim failed");
        emit Claimed(to, amount, reason);
    }

    function payForkRoyalty(uint256 amount) external {
        require(USDC.transferFrom(msg.sender, address(this), amount), "royalty failed");
        emit ForkRoyalty(msg.sender, amount);
    }

    function changeSteward(address newSteward) external onlySteward {
        emit StewardChanged(steward, newSteward);
        steward = newSteward;
    }

    function proposeSunset() external {
        require(block.timestamp > lastClaimTimestamp + 365 days, "still active");
        // ... governance vote logic
    }
}
```

This is a sketch; full implementation includes governance for steward changes and sunset votes.

---

## Layer 1: `IEmber.sol` (Interface)

This is the surface area intended for public standards review and EIP submission. Pure spec, no extraction, no implementation choices baked in.

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IEmber {
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
    event DormantSwept(address indexed wallet, uint256 amount);

    // === Read functions ===
    function INITIAL_SUPPLY() external view returns (uint256);
    function totalBurned() external view returns (uint256);
    function released() external view returns (bool);
    function terminated() external view returns (bool);
    function manifest() external view returns (SourceManifest memory);
    function sellOutTimestamp() external view returns (uint256);
    function releaseDeadline() external view returns (uint256);
    function devClaimable() external view returns (uint256);

    // === State-changing functions ===
    function buy(uint256 amount) external;
    function useApp(address user, uint256 amount) external returns (bool);
    function forceEmberPhase() external;
    function release(string[] calldata decryptionKeys) external;
    function slashReserve() external;
    function sweepDormant(address[] calldata wallets) external;
    function withdrawDev() external;
}
```

Any contract claiming EMBER compatibility implements this interface. The standard makes no claims about pricing curves, fee structures, or distribution — those are implementation details.

---

## Layer 2: `EmberCore.sol` (Reference Implementation)

The reference implementation. Fee-free by default. Anyone can deploy directly. Accepts optional fee parameters (capped at 5%) for use by factories or other distribution layers.

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./IEmber.sol";

interface IERC20Token {
    function transfer(address to, uint256 v) external returns (bool);
    function transferFrom(address f, address t, uint256 v) external returns (bool);
    function balanceOf(address a) external view returns (uint256);
    function decimals() external view returns (uint8);
}

/// @title EmberCore — Reference Implementation of ERC-EMBER
/// @notice Burn-to-bloom token contract. The closed-source phase ends when
///         enough tokens have burned. Source release is bound to a structured
///         manifest with reproducible build hashes and SPDX licensing.
/// @notice This implementation is fee-neutral by default. A fee recipient and
///         basis points may be set at deploy (capped at 5%) for use by
///         distribution factories. Direct deployment with no fee is fully
///         supported and is the recommended path for community-built projects.
contract EmberCore is IEmber {
    // === Identity ===
    string public name;
    string public symbol;
    uint8  public constant decimals = 0;

    // === Supply ===
    uint256 public immutable INITIAL_SUPPLY;
    uint256 public totalBurned;
    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    mapping(address => uint256) private _lastActivity;

    // === Release mechanics ===
    address public immutable developer;
    address public immutable dApp;
    bytes32 public immutable originalCommitment;
    string  public originalEncryptedCID;
    SourceManifest public manifest;
    SourceUpdate[] public updates;
    string[] public revealedKeys;
    bool public released;
    uint256 public sellOutTimestamp;
    uint256 public releaseDeadline;

    struct SourceUpdate {
        bytes32 commitment;
        string  encryptedCID;
        bytes32 manifestHash;
        uint256 timestamp;
    }

    // === Constants ===
    uint256 public constant RELEASE_QUORUM_BPS = 8_000;
    uint256 public constant RELEASE_TIMEOUT    = 730 days;
    uint256 public constant DORMANCY_THRESHOLD = 1095 days;
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

    // === Events ===
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event TokensPurchased(address indexed buyer, uint256 amount, uint256 usdcCost, uint256 fee);
    event DevWithdrew(uint256 usdcAmount);
    event FeePaid(uint256 usdcAmount);
    event ReserveSlashed(uint256 usdcAmount);

    modifier onlyDeveloper() {
        require(msg.sender == developer, "not developer");
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
        SourceManifest memory _manifest,
        address _usdc,
        uint256 _basePrice,
        uint256 _slope,
        address _feeRecipient,
        uint256 _feeBps
    ) {
        require(_initialSupply > 0 && _developer != address(0) && _dApp != address(0), "bad params");
        require(_originalCommitment != bytes32(0), "no commitment");
        require(_usdc != address(0), "no USDC");
        require(_feeBps <= MAX_FEE_BPS, "fee exceeds cap");
        require(_feeBps == 0 || _feeRecipient != address(0), "no fee recipient");
        require(bytes(_manifest.spdxLicense).length > 0, "no license");
        require(_manifest.archiveHash != bytes32(0), "no archive hash");

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
        manifest = _manifest;
        USDC = IERC20Token(_usdc);
        basePrice = _basePrice;
        slope = _slope;
        feeRecipient = _feeRecipient;
        feeBps = _feeBps;
    }

    // ---------- Bonding curve ----------
    function quote(uint256 amount) public view returns (uint256) {
        uint256 a = tokensSold;
        uint256 b = a + amount;
        return basePrice * amount + (slope * (b*b - a*a)) / 2;
    }

    function buy(uint256 amount) external override {
        require(amount > 0 && _balances[address(this)] >= amount, "sold out");
        uint256 cost = quote(amount);
        require(USDC.transferFrom(msg.sender, address(this), cost), "USDC pull failed");

        uint256 fee = feeBps > 0 ? (cost * feeBps) / 10_000 : 0;
        uint256 toProject = cost - fee;

        tokensSold      += amount;
        totalRaised     += toProject;
        totalFeesPaid   += fee;

        if (fee > 0) {
            require(USDC.transfer(feeRecipient, fee), "fee xfer failed");
            emit FeePaid(fee);
        }

        _transfer(address(this), msg.sender, amount);
        if (_balances[address(this)] == 0 && sellOutTimestamp == 0) {
            sellOutTimestamp = block.timestamp;
        }
        emit TokensPurchased(msg.sender, amount, cost, fee);
    }

    // ---------- Burn on use ----------
    function useApp(address user, uint256 amount) external override returns (bool) {
        require(msg.sender == dApp, "only dApp");
        require(_balances[user] >= amount && amount > 0, "bad burn");
        _balances[user] -= amount;
        _totalSupply   -= amount;
        totalBurned    += amount;
        _lastActivity[user] = block.timestamp;
        emit Transfer(user, address(0), amount);
        emit TokensBurnedForUse(user, amount, totalBurned);
        if (totalBurned == INITIAL_SUPPLY && releaseDeadline == 0) {
            releaseDeadline = block.timestamp + 30 days;
            emit EmberPhase(releaseDeadline);
        }
        return true;
    }

    // ---------- Production updates ----------
    function updateSource(
        bytes32 newCommitment,
        string calldata newCID,
        bytes32 newManifestHash
    ) external onlyDeveloper {
        require(!released, "already released");
        require(newCommitment != bytes32(0), "no commitment");
        updates.push(SourceUpdate(newCommitment, newCID, newManifestHash, block.timestamp));
        emit SourceUpdated(updates.length, newCommitment, newCID);
    }

    // ---------- Dual-path release trigger ----------
    function forceEmberPhase() external override {
        require(releaseDeadline == 0, "already triggered");
        bool fullBurn = totalBurned == INITIAL_SUPPLY;
        bool quorumPath = (totalBurned * 10_000) / INITIAL_SUPPLY >= RELEASE_QUORUM_BPS
                          && sellOutTimestamp != 0
                          && block.timestamp >= sellOutTimestamp + RELEASE_TIMEOUT;
        require(fullBurn || quorumPath, "neither path met");
        releaseDeadline = block.timestamp + 30 days;
        emit EmberPhase(releaseDeadline);
    }

    // ---------- Source release ----------
    function release(string[] calldata decryptionKeys) external override {
        require(!released, "already released");
        require(releaseDeadline != 0, "ember phase not started");
        require(decryptionKeys.length == updates.length + 1, "key count mismatch");
        require(keccak256(bytes(decryptionKeys[0])) == originalCommitment, "wrong genesis key");
        for (uint256 i = 0; i < updates.length; i++) {
            require(keccak256(bytes(decryptionKeys[i+1])) == updates[i].commitment, "wrong update key");
        }
        released = true;
        for (uint256 i = 0; i < decryptionKeys.length; i++) {
            revealedKeys.push(decryptionKeys[i]);
        }
        emit SourceReleased(decryptionKeys);
        emit ContractTerminated(totalBurned, block.timestamp);
    }

    // ---------- Dormant sweep ----------
    function sweepDormant(address[] calldata wallets) external override {
        for (uint256 i = 0; i < wallets.length; i++) {
            address w = wallets[i];
            require(_balances[w] > 0, "no balance");
            require(_lastActivity[w] + DORMANCY_THRESHOLD < block.timestamp, "not dormant");
            uint256 swept = _balances[w];
            _balances[w] = 0;
            _totalSupply -= swept;
            totalBurned  += swept;
            emit Transfer(w, address(0), swept);
            emit DormantSwept(w, swept);
        }
    }

    // ---------- Dev vesting ----------
    function devClaimable() public view override returns (uint256) {
        uint256 progress = (totalBurned * 1e18) / INITIAL_SUPPLY;
        uint256 unreserved = (totalRaised * progress * (100 - RESERVED_PCT)) / (100 * 1e18);
        uint256 reserved   = released
            ? (totalRaised * progress * RESERVED_PCT) / (100 * 1e18)
            : 0;
        uint256 vested = unreserved + reserved;
        return vested > devClaimed ? vested - devClaimed : 0;
    }

    function withdrawDev() external override onlyDeveloper {
        uint256 amt = devClaimable();
        require(amt > 0, "nothing");
        devClaimed += amt;
        require(USDC.transfer(developer, amt), "dev xfer failed");
        emit DevWithdrew(amt);
    }

    // ---------- Slash ----------
    function slashReserve() external override {
        require(releaseDeadline != 0 && !released, "not slashable");
        require(block.timestamp > releaseDeadline, "still in window");
        uint256 bal = USDC.balanceOf(address(this));
        if (bal > 0) {
            require(USDC.transfer(address(0xdEaD), bal), "slash xfer failed");
            emit ReserveSlashed(bal);
        }
    }

    // ---------- View helpers ----------
    function terminated() external view override returns (bool) { return released; }
    function updateCount() external view returns (uint256) { return updates.length; }
    function revealedKeyCount() external view returns (uint256) { return revealedKeys.length; }

    // ---------- ERC20 surface ----------
    function totalSupply() external view returns (uint256) { return _totalSupply; }
    function balanceOf(address a) external view returns (uint256) { return _balances[a]; }
    function allowance(address o, address s) external view returns (uint256) { return _allowances[o][s]; }
    function approve(address s, uint256 v) external returns (bool) {
        _allowances[msg.sender][s] = v;
        _lastActivity[msg.sender] = block.timestamp;
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
        require(_balances[f] >= v, "balance");
        unchecked { _balances[f] -= v; _balances[t] += v; }
        _lastActivity[f] = block.timestamp;
        _lastActivity[t] = block.timestamp;
        emit Transfer(f, t, v);
    }
}
```

This is the artifact the EIP cites. It is free, neutral, test-backed bytecode anyone can deploy without paying anyone.

---

## Layer 3: `EmberFactory.sol` (Material Synced's Product)

The factory deploys `EmberCore` instances with Material Synced's fee parameters wired in, and registers them in an indexer-backed catalog. This is where the business is.

### What the factory provides

1. **Maintained deployment path** — Material Synced can coordinate reviews, audits, and release provenance for factory deployments.
2. **Registry listing** — every deployment is indexed with metadata for discovery.
3. **Indexer + analytics** — historical burn rates, sale velocity, fork lineage.
4. **Web interface** — buyer-facing UI for token purchase, dev dashboard, claim flow.
5. **Customer support** — for both devs and buyers.
6. **Marketing reach** — featured project slots, social distribution.
7. **Fork lineage tracking** — when an EMBER project blooms and gets forked, the registry records the parent → child relationship and notifies the upstream community.

In exchange, the factory deploys `EmberCore` with `feeRecipient = STANDARD_AUTHOR` and `feeBps = 130` (1.3%).

### Factory contract

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./EmberCore.sol";
import "./MaintenancePool.sol";
import "./IEmber.sol";

contract EmberFactory {
    address public constant STANDARD_AUTHOR = 0x0000000000000000000000000000000000000001;
    uint256 public constant FACTORY_FEE_BPS = 130; // 1.3%

    struct DeploymentInfo {
        address developer;
        uint256 deployedAt;
        address maintenancePool; // address(0) if none
        bytes32 parentDeployment; // for fork lineage; 0 if original
    }

    address[] public deployments;
    mapping(address => DeploymentInfo) public info;
    mapping(address => address[]) public devProjects;

    event Deployed(
        address indexed token,
        address indexed developer,
        address maintenancePool,
        bytes32 parentDeployment
    );

    function deploy(
        string memory name,
        string memory symbol,
        uint256 initialSupply,
        address dApp,
        bytes32 originalCommitment,
        string memory originalEncryptedCID,
        IEmber.SourceManifest memory manifest,
        address usdc,
        uint256 basePrice,
        uint256 slope,
        bool spawnMaintenancePool,
        bytes32 parentDeployment
    ) external returns (address ember, address pool) {
        ember = address(new EmberCore(
            name,
            symbol,
            initialSupply,
            msg.sender,
            dApp,
            originalCommitment,
            originalEncryptedCID,
            manifest,
            usdc,
            basePrice,
            slope,
            STANDARD_AUTHOR,
            FACTORY_FEE_BPS
        ));

        if (spawnMaintenancePool) {
            pool = address(new MaintenancePool(ember, msg.sender, usdc));
        }

        deployments.push(ember);
        info[ember] = DeploymentInfo({
            developer: msg.sender,
            deployedAt: block.timestamp,
            maintenancePool: pool,
            parentDeployment: parentDeployment
        });
        devProjects[msg.sender].push(ember);

        emit Deployed(ember, msg.sender, pool, parentDeployment);
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
| Token utility | Speculation | Speculation | Access + ownership | Access + ownership |
| Open standard? | Proprietary | Proprietary | Yes (`IEmber`) | Yes (`IEmber`) |

Clanker and Bankr monetize speculation perpetually. EMBER monetizes utility and exits when utility is fulfilled. The fee-free direct-deploy path is a real option for projects that don't want the factory's services.

---

## Path to Adoption

The four-layer architecture clarifies the path significantly. Material Synced submits **layers 1-2 only** to the EIP process. Layer 3 launches as a product. Layer 4 is community infrastructure.

### Formal track (EIP submission of `IEmber` + `EmberCore`)

1. **Public standards pre-discussion** — required before formal submission. The standard being fee-free at this layer removes the most common objection.
2. **Draft per EIP-1** with motivation, specification, rationale, backwards compatibility, reference implementation (`EmberCore`), and security considerations (manifest commitment, dual triggers, dormant sweep, slash mechanics).
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

## Open Design Questions

1. **Encrypted source storage redundancy** — IPFS pinning is the soft spot. Arweave + Filecoin redundancy preferred. Should the manifest commit to multiple CIDs across providers?
2. **Reproducible build verification** — should the contract include a way for verifiers to challenge that the released source rebuilds to the committed `buildArtifactHash`, with bond-and-slash?
3. **Bonding curve shape** — Linear is simple. Logistic curves or Uniswap V3-LP-as-curve give different price discovery. Should `IEmber` mandate a specific shape, or leave it implementation-defined?
4. **Burner receipts** — Should burning tokens mint a soulbound NFT receipt? Useful for governance in successor DAOs.
5. **Permit2 / EIP-2612** — Single-tx buy flow on chains where USDC supports gasless approvals.
6. **MaintenancePool governance** — multisig vs DAO vs individual steward, with what voting mechanics for sunsets?

---

## Next Pieces

### Foundry test suite
Full coverage of:
- Bonding curve math (overflow safety, rounding behavior)
- Buy/burn/release flows including multi-version key chains
- Dual-trigger forceEmberPhase paths (full burn, quorum + timeout)
- Dormant sweep with mocked time progression
- Slash mechanics on missed release
- Fee routing for factory-deployed vs direct deployments
- Manifest validation (empty license, zero hashes)

### Audit
Before mainnet deployment with real funds, audit from OpenZeppelin, Trail of Bits, or Spearbit covering bonding curve math, USDC integration, vesting calculations, manifest commitments, dual triggers, dormant sweep, and slash mechanism.

### EIP draft document
Formal ERC-XXXX writeup for public standards discussion, covering only `IEmber` + `EmberCore`. The factory is mentioned only as one possible implementation.

### Factory infrastructure
- Indexer (Ponder or Subgraph) covering all deployments
- Registry frontend at `ember.materialsynced.com`
- Developer dashboard for managing source updates and claiming vested USDC
- Buyer-facing token purchase UI with one-click approve + buy flow
- Fork lineage explorer

### MaintenancePool reference contract
Full implementation with governance for steward changes, sunset votes, and fork-royalty accounting.

---

## Appendix: Glossary

- **Ember Phase** — The 30-day window between release trigger and required source reveal.
- **Bloom** — The act of releasing the source code chain via `release(keys[])`.
- **Source Manifest** — Structured commitment binding the deployer to a specific buildable, OSI-licensed source archive.
- **Source Commitment** — `keccak256(decryptionKey)` recorded immutably at deploy and at every production update.
- **Production Update** — A new commitment and CID appended during the active phase, extending the chain of keys that must be revealed.
- **Reserved Portion** — 20% of developer vesting, locked until `release()` is called with valid keys for all versions.
- **Slash** — Permanent burn of the reserved portion if release deadline passes without valid reveal.
- **Dormant Sweep** — Burn of tokens in wallets inactive for 3+ years.
- **Dual Trigger** — Release path that opens via either full burn or quorum-plus-timeout.
- **Monument State** — The contract's terminal state after release: no further economic activity, but full on-chain history preserved.
- **Factory-Deployed** — An `EmberCore` instance created via `EmberFactory`, with 1.3% routing to Material Synced.
- **Direct-Deployed** — An `EmberCore` instance created without the factory, with zero fee.

---

## References

- Ethereum Improvement Proposals: https://eips.ethereum.org
- EIP-1 (process meta-doc): https://eips.ethereum.org/EIPS/eip-1
- ERC submissions repo: https://github.com/ethereum/ercs
- Public standards discussion: not yet opened
- SPDX license list: https://spdx.org/licenses/
- Clanker (1% per-swap fee model, Base): https://www.clanker.world
- Bankr (1.2% per-swap fee model, Base/Solana): https://bankr.bot
- Monad documentation: https://docs.monad.xyz

---

*Drafted for Material Synced LLC. The `IEmber` interface and `EmberCore` reference implementation are intended for EIP submission. `EmberFactory` and `MaintenancePool` are Material Synced products and community infrastructure respectively.*
