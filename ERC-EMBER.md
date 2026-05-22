# ERC-EMBER: Burn-to-Bloom Token Standard

> **Archived draft:** This v0.1 document is retained for history only. Use
> `ERC-EMBER-v0.3.md` and `contracts/src/` as the current canonical reference.

> **Author:** Material Synced LLC ([@Gh0stNaSmilee](https://x.com/Gh0stNaSmilee))
> **Status:** Draft v0.1
> **Created:** May 2026
> **Target chains:** Monad, Base, Ethereum, Arbitrum, BNB, and any EVM-equivalent network
> **License:** MIT

---

## TL;DR

A token standard where access tokens are **consumed on use**. When all tokens have burned, the project's source code is **cryptographically released** to the community. The developer is paid as the community uses the product; the standard author takes a small one-shot fee on primary sale. Both revenue streams terminate when the project becomes open source. The contract becomes a permanent on-chain monument.

---

## Abstract

ERC-EMBER defines a token contract where:

1. A developer mints a fixed supply of access tokens proportional to their project's scale.
2. The community purchases tokens on a bonding curve in USDC.
3. Each use of the developer's app/platform burns the user's tokens.
4. When every token has burned, a cryptographic commitment forces release of the source code.
5. The developer receives USDC proportional to burn progress (with a reserved portion gated on source release).
6. The standard author receives a 1.3% fee on primary sales, which also terminates with the project's lifecycle.
7. After release, the contract becomes a monument: revenue ends, code is public, the community is free to fork.

The result aligns three parties — developer, community, and standard author — around a single outcome: liberate the code.

---

## Motivation

Today a developer with an idea has three economic paths:

- **Closed source / SaaS:** charge forever, retain control, no community ownership.
- **Open source from day one:** no revenue, community ownership but no developer compensation.
- **VC-backed:** dilute equity, optimize for exit, often misaligned with users.

None of these reward the pattern most software actually wants: build the thing, get paid fairly for the work, and then let the community take it from there.

ERC-EMBER encodes that pattern directly. The developer is paid by the people who get value from the product, capped at a fair amount determined by the market. When that payment is complete, the code belongs to the community. No subscriptions, no rug-pulls, no equity dilution, no perpetual rent extraction.

---

## Core Mechanic

```
┌─────────────┐   buy USDC   ┌──────────────┐   use app    ┌──────────────┐
│  Community  │ ───────────▶ │  EmberToken  │ ◀─────────── │   dApp logic │
└─────────────┘              │   contract   │   (burns)    └──────────────┘
                             └──────────────┘
                                    │
                                    ├── 1.3% USDC ────▶ Standard Author
                                    ├── 98.7% USDC ───▶ Dev (vested by burn %)
                                    └── On full burn ─▶ Source key revealed
                                                         Contract terminated
```

---

## Lifecycle

### 1. Deploy
The developer:
- Encrypts the project source code with a key `K`.
- Uploads the encrypted blob to IPFS or Arweave; records the CID.
- Computes `commitment = keccak256(K)`.
- Deploys `EmberToken` with: initial supply, dApp address, USDC address, base price, slope, encrypted source CID, and the commitment hash.

### 2. Active Sale Phase
- Buyers approve USDC and call `buy(amount)`.
- The bonding curve quotes a price; 1.3% routes to the standard author immediately; 98.7% remains in the contract.
- Tokens transfer to the buyer.
- Anyone can resell tokens on a secondary market (standard ERC-20 transferability) until they're burned.

### 3. Burn Phase
- Users interact with the dApp.
- The dApp calls `useApp(user, amount)` which burns `amount` tokens from the user's balance.
- As `totalBurned` grows, the developer's vested claimable amount grows proportionally.

### 4. Ember Phase (30-day window)
- When `totalBurned == INITIAL_SUPPLY`, the contract emits `EmberPhase(deadline)`.
- The developer has 30 days to reveal the decryption key.

### 5. Source Release (or Slash)
- **Happy path:** Dev calls `release(key)`. Contract verifies `keccak256(key) == sourceCommitment` and stores the key on-chain. The encrypted blob can now be decrypted by anyone. `ContractTerminated` fires. The 20% reserved portion of dev's vesting unlocks.
- **Slash path:** If the deadline passes without release, anyone can call `slashReserve()`. The reserved 20% (held in USDC) is sent to `0xdEaD` and burned. The dev keeps what they already claimed (proportional to burn) but loses the reserve.

### 6. Monument State
Post-release, the contract has no further economic function. It holds:
- The revealed key (publicly readable).
- The IPFS/Arweave CID of the encrypted source.
- A complete on-chain history of every buy, burn, fee payment, and dev claim.

---

## Symmetric Fee Model

The standard's central design choice: **all revenue streams terminate when the project becomes open source.**

| Party | Earns From | Caps At | Ends When |
|---|---|---|---|
| Developer | Burn progress against `totalRaised` | `totalRaised` (98.7% of gross) | Source released and dev claims final tranche |
| Standard Author | 1.3% of each primary sale | `1.3% × totalRaised` | All tokens sold (no more `buy()` calls possible) |
| Community | Access during closed-source phase | Use of product + eventual ownership of code | Free to fork forever |

This symmetry is intentional. The standard author has no perpetual claim against the project. Once the bonding curve sells out, the author's revenue from that project is finished. The contract becomes a monument with no further extraction.

This makes the standard honest:
- A developer adopting EMBER knows exactly what the lifetime cost of using the standard will be (1.3% of gross sale).
- A community member knows the dev's incentive aligns with shipping value, and the standard author's incentive aligns with broad adoption (not parasitic capture of any single project).
- A forker who modifies the spec gains nothing structural — there's no perpetual fee to strip.

---

## Standard Author Fee: Defense & Math

The 1.3% fee is small enough to be tolerated and clear enough to be defensible.

### Per-project revenue

| Gross raise | Author revenue | Dev vesting pool |
|---|---|---|
| $50,000 | $650 | $49,350 |
| $300,000 | $3,900 | $296,100 |
| $1,000,000 | $13,000 | $987,000 |
| $5,000,000 | $65,000 | $4,935,000 |

### Network-level revenue (assuming $300k average raise)

| Projects deployed | Annual author revenue |
|---|---|
| 10 | $39,000 |
| 100 | $390,000 |
| 1,000 | $3.9M |
| 10,000 | $39M |

The thesis is volume × adoption, not any single project. Defensibility comes from the `BloomFactory` + `EmberRegistry` infrastructure (see "Next Pieces" below), not from the fee line in the contract.

---

## Comparison to Existing Launchers

| Property | Clanker (v3) | Bankr (Base) | ERC-EMBER |
|---|---|---|---|
| Fee model | 1% per swap, forever | 1.2% per swap, forever | 1.3% on primary sale only |
| Fee recipient | Protocol + creator + interface | Protocol + creator + LLM gateway | Standard author only |
| Terminates? | No (perpetual swap fee) | No (perpetual swap fee) | **Yes** — ends with project release |
| Source code | Closed | Closed | **Released to community on full burn** |
| Token utility | Speculation | Speculation | Access + eventual code ownership |
| Aligned incentive | Trading volume | Trading volume | Product utility |

Clanker and Bankr capture perpetual swap fees because they monetize speculation. ERC-EMBER monetizes utility, and exits when utility is fulfilled. Different products, different ethics.

---

## Reference Implementation

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IERC20Token {
    function transfer(address to, uint256 v) external returns (bool);
    function transferFrom(address f, address t, uint256 v) external returns (bool);
    function balanceOf(address a) external view returns (uint256);
    function decimals() external view returns (uint8);
}

/// @title ERC-EMBER: Burn-to-Bloom Token Standard (USDC-denominated)
/// @notice Access tokens are flames consumed in use. When the fire burns out,
///         only embers remain — the source code, released to the community.
/// @notice The standard author fee (1.3%) is collected only during the
///         primary sale phase. When all tokens are sold, both the
///         developer's vesting and the author's fee stream terminate.
///         When the last token burns and the source is released, the
///         contract becomes a permanent on-chain monument — no further
///         revenue flows to any party. The project belongs to the community.
contract EmberToken {
    // === Identity ===
    string public name;
    string public symbol;
    uint8  public constant decimals = 0;          // countable access units

    // === Supply ===
    uint256 public immutable INITIAL_SUPPLY;
    uint256 public totalBurned;
    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    // === Release mechanics ===
    address public immutable developer;
    address public immutable dApp;
    bytes32 public immutable sourceCommitment;
    string  public encryptedSourceCID;
    string  public revealedKey;
    bool    public released;
    uint256 public releaseDeadline;

    // === Economics (denominated in USDC base units, 6 decimals) ===
    IERC20Token public immutable USDC;
    uint256 public immutable basePrice;           // USDC-units per token at n=0
    uint256 public immutable slope;               // p(n) = basePrice + slope*n
    uint256 public tokensSold;
    uint256 public totalRaised;                   // net of author fee
    uint256 public devClaimed;
    uint256 public constant RESERVED_PCT = 20;

    // === Standard author fee (immutable, baked in) ===
    /// @dev Historical illustrative address; current factory uses constructor args.
    address public constant STANDARD_AUTHOR = 0x0000000000000000000000000000000000000001;
    uint256 public constant AUTHOR_FEE_BPS  = 130;    // 1.3%
    uint256 public totalAuthorFees;

    // === Events ===
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event TokensPurchased(address indexed buyer, uint256 amount, uint256 usdcCost, uint256 authorFee);
    event TokensBurnedForUse(address indexed user, uint256 amount, uint256 totalBurned);
    event EmberPhase(uint256 deadline);
    event SourceReleased(string decryptionKey);
    event ContractTerminated(uint256 totalRaised, uint256 totalAuthorFees, uint256 finalBurned, uint256 timestamp);
    event DevWithdrew(uint256 usdcAmount);
    event AuthorFeePaid(uint256 usdcAmount);
    event ReserveSlashed(uint256 usdcAmount);

    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _initialSupply,
        address _developer,
        address _dApp,
        bytes32 _sourceCommitment,
        string  memory _encryptedSourceCID,
        address _usdc,
        uint256 _basePrice,
        uint256 _slope
    ) {
        require(_initialSupply > 0 && _developer != address(0) && _dApp != address(0), "bad params");
        require(_sourceCommitment != bytes32(0), "no commitment");
        require(_usdc != address(0), "no USDC");
        name = _name; symbol = _symbol;
        INITIAL_SUPPLY = _initialSupply;
        _totalSupply = _initialSupply;
        _balances[address(this)] = _initialSupply;
        emit Transfer(address(0), address(this), _initialSupply);
        developer = _developer;
        dApp = _dApp;
        sourceCommitment = _sourceCommitment;
        encryptedSourceCID = _encryptedSourceCID;
        USDC = IERC20Token(_usdc);
        basePrice = _basePrice;
        slope = _slope;
    }

    // ---------- Bonding curve sale (USDC) ----------
    function quote(uint256 amount) public view returns (uint256) {
        uint256 a = tokensSold;
        uint256 b = a + amount;
        return basePrice * amount + (slope * (b*b - a*a)) / 2;
    }

    /// @notice Buyer must `USDC.approve(this, cost)` first.
    function buy(uint256 amount) external {
        require(amount > 0 && _balances[address(this)] >= amount, "sold out");
        uint256 cost = quote(amount);

        require(USDC.transferFrom(msg.sender, address(this), cost), "USDC pull failed");

        uint256 authorFee = (cost * AUTHOR_FEE_BPS) / 10_000;
        uint256 toProject = cost - authorFee;

        tokensSold      += amount;
        totalRaised     += toProject;
        totalAuthorFees += authorFee;

        require(USDC.transfer(STANDARD_AUTHOR, authorFee), "fee xfer failed");
        emit AuthorFeePaid(authorFee);

        _transfer(address(this), msg.sender, amount);
        emit TokensPurchased(msg.sender, amount, cost, authorFee);
    }

    // ---------- Burn on use ----------
    function useApp(address user, uint256 amount) external returns (bool) {
        require(msg.sender == dApp, "only dApp");
        require(_balances[user] >= amount && amount > 0, "bad burn");
        _balances[user] -= amount;
        _totalSupply   -= amount;
        totalBurned    += amount;
        emit Transfer(user, address(0), amount);
        emit TokensBurnedForUse(user, amount, totalBurned);
        if (totalBurned == INITIAL_SUPPLY && releaseDeadline == 0) {
            releaseDeadline = block.timestamp + 30 days;
            emit EmberPhase(releaseDeadline);
        }
        return true;
    }

    // ---------- Source release ----------
    function release(string calldata decryptionKey) external {
        require(!released && totalBurned == INITIAL_SUPPLY, "not eligible");
        require(keccak256(bytes(decryptionKey)) == sourceCommitment, "wrong key");
        released = true;
        revealedKey = decryptionKey;
        emit SourceReleased(decryptionKey);
        emit ContractTerminated(totalRaised, totalAuthorFees, totalBurned, block.timestamp);
    }

    // ---------- Dev vesting (USDC) ----------
    function devClaimable() public view returns (uint256) {
        uint256 progress = (totalBurned * 1e18) / INITIAL_SUPPLY;
        uint256 unreserved = (totalRaised * progress * (100 - RESERVED_PCT)) / (100 * 1e18);
        uint256 reserved   = released
            ? (totalRaised * progress * RESERVED_PCT) / (100 * 1e18)
            : 0;
        uint256 vested = unreserved + reserved;
        return vested > devClaimed ? vested - devClaimed : 0;
    }

    function withdrawDev() external {
        require(msg.sender == developer, "not dev");
        uint256 amt = devClaimable();
        require(amt > 0, "nothing");
        devClaimed += amt;
        require(USDC.transfer(developer, amt), "dev xfer failed");
        emit DevWithdrew(amt);
    }

    // ---------- Slash reserve if dev never reveals ----------
    function slashReserve() external {
        require(totalBurned == INITIAL_SUPPLY && !released, "not slashable");
        require(block.timestamp > releaseDeadline, "still in window");
        uint256 bal = USDC.balanceOf(address(this));
        if (bal > 0) {
            require(USDC.transfer(address(0xdEaD), bal), "slash xfer failed");
            emit ReserveSlashed(bal);
        }
    }

    // ---------- Terminal state view ----------
    function terminated() external view returns (bool) {
        return released;
    }

    // ---------- ERC20 surface ----------
    function totalSupply() external view returns (uint256) { return _totalSupply; }
    function balanceOf(address a) external view returns (uint256) { return _balances[a]; }
    function allowance(address o, address s) external view returns (uint256) { return _allowances[o][s]; }
    function approve(address s, uint256 v) external returns (bool) { _allowances[msg.sender][s] = v; emit Approval(msg.sender, s, v); return true; }
    function transfer(address to, uint256 v) external returns (bool) { _transfer(msg.sender, to, v); return true; }
    function transferFrom(address f, address t, uint256 v) external returns (bool) {
        uint256 a = _allowances[f][msg.sender];
        require(a >= v, "allowance");
        if (a != type(uint256).max) _allowances[f][msg.sender] = a - v;
        _transfer(f, t, v); return true;
    }
    function _transfer(address f, address t, uint256 v) internal {
        require(_balances[f] >= v, "balance");
        unchecked { _balances[f] -= v; _balances[t] += v; }
        emit Transfer(f, t, v);
    }
}
```

## Pricing Calibration

Token has 0 decimals (countable); USDC has 6 decimals (1 USDC = 1,000,000 base units). All bonding curve parameters use USDC base units.

### Flat-price example
- `INITIAL_SUPPLY = 1_000_000`
- `basePrice = 10_000` → $0.01 per token
- `slope = 0`
- Gross raise = $10,000
- Author fee = $130, Dev pool = $9,870

### Linear-ascending example (price doubles by end of sale)
- `INITIAL_SUPPLY = 1_000_000`
- `basePrice = 10_000` → starts at $0.01
- `slope = 10` → ends at $0.02 ($0.01 + 10 × 1,000,000 / 1,000,000)
- Gross raise ≈ $15,000 (average price ≈ $0.015)
- Author fee ≈ $195, Dev pool ≈ $14,805

### Per-chain USDC addresses (set in constructor)
| Chain | USDC address |
|---|---|
| Monad | (set per Monad mainnet deployment) |
| Base | `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` |
| Ethereum | `0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48` |
| Arbitrum | `0xaf88d065e77c8cC2239327C5EDb3A432268e5831` |

---

## Path to Adoption

There is no gatekeeping "approval" body. EIP editors check formatting only — the community decides what becomes a real standard via adoption. The practical path:

### Formal track (Ethereum EIP)
1. **Public standards pre-discussion** — required before any PR.
2. **Draft the spec** following EIP-1 template (motivation, specification, rationale, backwards compatibility, reference implementation, security considerations).
3. **Submit PR** to `github.com/ethereum/ercs` (not the legacy `ethereum/EIPs` repo — ERCs were split out).
4. **Status progression:** Draft → Review → Last Call (~14 day window) → Final. 6 months of inactivity = auto-Stagnant.

### Adoption track (what actually matters)
1. **Ship the reference implementation publicly** — MIT-licensed Solidity on GitHub, with a Foundry test suite and a clear audit path before production use.
2. **Deploy 2-3 live EMBER projects** — Real mainnet deployments matter more than a forum proposal.
3. **Write the EIP after** — with adoption data in the rationale. Editors and reviewers respect "this is already working" more than theoretical proposals.
4. **Defend the 1.3% in public standards review.** Most ERCs are fee-free; expect pushback. The honest argument: the fee terminates with the project, it's symmetric with the developer's payment, and it funds the maintenance of the standard's surrounding infrastructure (factory, registry, indexer).
5. **Partner with the Monad Foundation** in parallel. A Monad-endorsed standard with deployments on Base hits more developers faster than waiting on EIP Final status (which can take 12-24 months).

### EVM-equivalence note
ERC-EMBER works on every EVM chain (Monad, Base, Ethereum, Arbitrum, BNB) without modification. One submission, every chain.

---

## Open Design Questions

1. **Encrypted source storage** — IPFS pinning is the soft spot. Arweave + Filecoin redundancy preferred. Should the contract also commit a Merkle root of encrypted chunks to prove integrity?
2. **Bonding curve shape** — Linear ascending is simple. Logistic curves (slow-fast-plateau) or Uniswap V3-LP-as-curve would give different price discovery.
3. **Burner receipts** — Should burning tokens mint a soulbound NFT receipt? Useful for governance in successor DAOs ("I helped liberate this project").
4. **Forking lineage** — A `BloomRegistry` companion contract could track `parent → child` fork relationships on-chain. Could give downstream forks a way to attribute revenue back to original developers voluntarily.
5. **Permit2 / EIP-2612 integration** — Single-tx buy flow on chains where USDC supports gasless approvals.

---

## Next Pieces

### `EmberFactory` + `EmberRegistry`
The defensibility layer for the 1.3%. Projects deploy through the factory (which enforces the fee at the bytecode level the standard author controls). The registry gives them indexer/discovery, fork-lineage tracking, and metadata services. Fork-strippers don't get these benefits. The factory + registry is what turns "a line of code in a contract" into a real distribution business.

### Foundry test suite
Full coverage of the buy/burn/release/slash flows, fee routing, vesting math, and edge cases (zero burns, partial burns, missed deadlines, rounding dust).

### EIP draft
Formal ERC-XXXX writeup ready for a public standards discussion.

### Audit
Before any mainnet deployment with real funds, an audit from a reputable firm (OpenZeppelin, Trail of Bits, Spearbit) covering the bonding curve math, USDC integration, vesting calculations, and the slash mechanism.

---

## Appendix: Glossary

- **Ember Phase** — The 30-day window between the last token burning and the developer's required source release.
- **Bloom** — The act of releasing the source code (function: `release()`).
- **Source Commitment** — `keccak256(decryptionKey)` recorded immutably at deploy.
- **Standard Author Fee** — 1.3% routed to the immutable `STANDARD_AUTHOR` address on every primary sale.
- **Reserved Portion** — 20% of developer vesting, locked until `release()` is called.
- **Slash** — Permanent burn of the reserved portion if the developer fails to release within 30 days of full burn.
- **Monument State** — The contract's terminal state after `release()`: no further economic activity, but full on-chain history preserved.

---

## References

- Ethereum Improvement Proposals: https://eips.ethereum.org
- EIP-1 (process meta-doc): https://eips.ethereum.org/EIPS/eip-1
- ERC submissions repo: https://github.com/ethereum/ercs
- Public standards discussion: not yet opened
- Clanker (1% per-swap fee model, Base): https://www.clanker.world
- Bankr (1.2% per-swap fee model, Base/Solana): https://bankr.bot
- Monad documentation: https://docs.monad.xyz

---

*Archived draft for Material Synced LLC. Use `ERC-EMBER-v0.3.md` and `contracts/src/` for the current reference.*
