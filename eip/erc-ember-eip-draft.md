---
eip: <TBD — assigned by an editor after the PR opens>
title: Burn-to-Bloom Access Token
description: Access tokens consumed on use; committed source is released and the contract terminates once a burn threshold is met.
author: Material Synced LLC (@Gh0stNaSmilee)
discussions-to: <public standards discussion URL — create before opening the PR>
status: Draft
type: Standards Track
category: ERC
created: 2026-05-20
requires: 20, 165
---

<!--
  SCOPE: LAYERS 1–2 ONLY — the `IEmber` interface and the `EmberCore` reference
  implementation. `EmberFactory` (paid distribution) and `MaintenancePool`
  (optional companion) are NOT part of the standard; referenced only as "one
  possible distribution implementation."

  Resolved scoping decisions (2026-05-20):
   1. Prescriptiveness: `IEmber` AND the burn → Ember Phase → release/slash/
      termination lifecycle are normative. Pricing curve, sale mechanics, storage
      backend, fee/treasury policy, and maintenance funding are implementation-defined.
   2. ERC-165: required. `IEmber is IERC165`; preamble `requires: 20, 165`.
   3. Abandoned recovery: NOT in the neutral standard. It is an optional, non-normative
      extension (`IEmberRecovery`); treasury/commission routing is excluded from core
      conformance.

  LICENSE NOTE: this EIP document must be CC0 (see Copyright). Repo code stays MIT.
-->

## Abstract

This standard defines an access token that is **consumed (burned) when the
underlying application is used**. A developer mints a fixed supply, the community
buys it on a bonding curve denominated in a stablecoin, and each use of the
application burns the buyer's tokens. When a release threshold is reached — full
burn, or a quorum after a long timeout — a cryptographic commitment recorded at
deploy time forces the on-chain reveal of decryption keys for a structured source
manifest, after which the contract permanently terminates. Funds are paid to the
developer in proportion to burn progress, with a reserved portion gated on the
source release; any holders who never burned are paid out, never confiscated.

## Motivation

A developer with a working product today chooses among closed-source/SaaS
(perpetual rent, no community ownership), open-source-from-day-one (ownership but
no compensation), and VC-backed (dilution, exit-optimized). None encode the
pattern most software actually wants: **build it, get paid fairly for the work,
then hand it to the community.**

This standard encodes that lifecycle on-chain. The developer is paid by the
people who get value from the product, capped at a market-discovered amount, and
when payment is complete and the access tokens are burned, the source belongs to
the community. There are no subscriptions, no perpetual fees in the standard
itself, no equity, and — by construction — no mechanism that lets the system
seize a holder's balance.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHOULD", "SHOULD NOT", "MAY", and
"OPTIONAL" in this document are to be interpreted as described in RFC 2119 and
RFC 8174.

### Conformance

A conforming contract MUST implement ERC-20, MUST implement `IEmber`, and MUST
implement ERC-165 such that `supportsInterface(type(IEmber).interfaceId)` and
`supportsInterface(type(IERC165).interfaceId)` return `true`. The token's
`decimals` MAY be `0` to represent countable access units.

The interface and the lifecycle in "Lifecycle requirements" below are normative.
The pricing/bonding curve, sale mechanics, the encrypted-source storage backend,
any fee or treasury policy, and any post-release maintenance funding are
implementation-defined and outside the scope of conformance.

### Interface

```solidity
// Keep byte-for-byte in sync with contracts/src/IEmber.sol
interface IEmber is IERC165 {
    struct SourceManifest {
        bytes32 archiveHash;
        bytes32 fileTreeMerkleRoot;
        bytes32 lockfileHash;
        bytes32 buildArtifactHash;
        string  spdxLicense;
        string  manifestCID;
    }

    event TokensBurnedForUse(address indexed user, uint256 amount, uint256 totalBurned);
    event SourceUpdated(uint256 indexed version, bytes32 commitment, string encryptedCID);
    event EmberPhase(uint256 deadline);
    event SourceReleased(string[] decryptionKeys);
    event ContractTerminated(uint256 finalBurned, uint256 timestamp);
    event Redeemed(address indexed holder, uint256 tokens, uint256 usdc);
    event ReserveSlashed(uint256 usdcAmount);

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

    function buy(uint256 amount) external;
    function useApp(address user, uint256 amount) external returns (bool);
    function forceEmberPhase() external;
    function release(string[] calldata decryptionKeys) external;
    function slashReserve() external;
    function redeem(uint256 amount) external;
    function withdrawDev() external;
}
```

### Lifecycle requirements

**Commitment.** At construction the contract MUST record an immutable genesis
commitment `keccak256(K)` for a decryption key `K`, and a `SourceManifest` whose
`spdxLicense` is non-empty and whose `archiveHash` is non-zero. A conforming
contract MUST NOT allow the genesis commitment to change after construction.

**Production updates.** A conforming contract MAY allow the developer to append
further commitments (each with an encrypted-source pointer and manifest hash),
forming an ordered chain. If supported, appends MUST be rejected once the Ember
Phase has opened (i.e. once `releaseDeadline != 0`), and `release` MUST require a
decryption key for every committed version, genesis first.

**Burn on use.** Burning MUST reduce the holder's balance and total supply,
increase `totalBurned`, and emit `TokensBurnedForUse`. A conforming contract MUST
NOT reduce any holder's balance for inactivity or any reason other than the
holder's own use (`useApp`) or redemption (`redeem`).

**Release triggers.** Opening the Ember Phase MUST set `releaseDeadline` to a
future timestamp and emit `EmberPhase`. It MUST be triggerable by either: (a)
full burn (`totalBurned == INITIAL_SUPPLY`); or (b) a quorum-plus-timeout path,
permissionlessly callable via `forceEmberPhase` once a defined burn quorum and a
post-sellout timeout have both elapsed. Opening the phase MUST freeze further
burns and commitment appends, and MUST snapshot the accounting used for developer
vesting and redemption so subsequent activity cannot move it.

**Terminal states.** A conforming contract has exactly the terminal outcomes
`released` and `slashed`, which MUST be mutually exclusive. `release` MUST verify
each provided key against its commitment, set `released`, reveal the keys, and
emit `SourceReleased` and `ContractTerminated`. `release` MUST be accepted at any
time before a slash occurs, including after `releaseDeadline` ("grace until
slashed"). `slashReserve` MUST be callable only after `releaseDeadline` has
passed with no release, MUST set `slashed`, and MUST burn only the reserved
tranche snapshotted at trigger (it MUST NOT take the redemption pool or unvested
developer funds).

**Developer vesting.** `devClaimable` MUST be a non-decreasing function of burn
progress up to the trigger snapshot, MUST gate the reserved tranche on `released`,
and MUST freeze once the Ember Phase opens.

**Redemption.** When the Ember Phase opens with tokens still outstanding, those
holders MUST be able to `redeem` for a pro-rata share of the unearned remainder
at the snapshotted rate (`redemptionQuote`). The sum of redemptions MUST NOT
exceed the snapshotted redemption pool. Redemption is pro-rata against the net
project raise, not any individual holder's cost basis.

### Optional extensions (non-normative)

Implementations MAY offer additional behavior outside core conformance. Such
extensions SHOULD be exposed as separate ERC-165-advertised interfaces so that
non-supporting deployments remain fully conformant. The reference implementation
ships one such extension, `IEmberRecovery` (abandoned-capital recovery): after a
long inactivity window, residual stablecoin MAY be routed to a configured
treasury and commission recipient. Because it routes a commission, it is
intentionally **excluded from core conformance**; it is disabled by default and a
deployment that omits it remains a conforming EMBER token.

In the reference factory deployment, the non-normative product economics are
explicit: factory-created contracts route a 1.3% primary-sale fee to the
configured standard-author address. If abandoned-capital recovery is enabled,
recoverable idle capital outside any remaining holder redemption reserve is
routed 90% to a treasury intended to support startup and software ecosystem
initiatives, and 10% to the standard-author / commission-recipient address. The
factory fee is not a perpetual royalty; it is collected only during active
primary sales, and after an EMBER contract closes through release, slash, or
abandoned recovery, there is no ongoing standard-author payment stream. These
routes are product policy, not ERC conformance requirements.

## Rationale

- **Burn-on-use over swap fees.** Monetizes utility rather than speculation and
  gives the lifecycle a natural terminus.
- **Manifest commitment, not a bare blob.** Binds the deployer to a buildable,
  licensed archive; a stripped or unbuildable reveal does not satisfy it.
- **Dual trigger.** Exact full-burn is brittle (lost or hostile holders); the
  quorum-plus-timeout path guarantees eventual release without confiscation.
- **Redemption instead of sweep.** Outstanding holders are paid, never seized —
  the core ethical invariant, and the reason inactivity-based balance burning is
  explicitly forbidden.
- **Reserved-only slash; grace-until-slashed.** Optimizes for source liberation
  over punishing lateness, while still giving the community a lever.
- **Extensions kept out of core.** Anything that routes value to a
  treasury/commission (e.g. recovery, factory fees) is excluded from conformance
  so the neutral standard carries no extraction and draws no "rent" objection.
- **ERC-165.** Lets indexers, marketplaces, and integrators detect EMBER tokens
  and which optional extensions a deployment supports.

## Backwards Compatibility

Conforming tokens are ERC-20 tokens and interoperate with existing wallets and
exchanges during the sale and burn phases. `decimals` MAY be `0`. ERC-165 is
additive. No backwards-incompatible changes to ERC-20 semantics are introduced.

## Reference Implementation

`EmberCore` is the reference implementation, in `contracts/src/EmberCore.sol` of
this repository, with a Foundry test suite under `contracts/test/`. It is
fee-neutral by default; a capped fee recipient may be configured for distribution
layers. It additionally implements the optional `IEmberRecovery` extension.
`EmberFactory` and `MaintenancePool` in the same directory are **not part of this
standard** — they are one possible paid-distribution implementation and an
optional funding companion, included for completeness only.

## Security Considerations

- **Source availability vs. on-chain commitment.** The chain proves the revealed
  key matches the commitment, not that the encrypted blob is still retrievable;
  storage permanence (IPFS/Arweave/Filecoin) is out of band and SHOULD be
  redundant.
- **Reproducible builds.** The manifest binds build hashes, but on-chain
  verification that the released source rebuilds to `buildArtifactHash` is not
  enforced; integrators SHOULD verify off-chain.
- **Timestamp dependence.** Release, slash, and (extension) recovery gates compare
  `block.timestamp` against multi-day-to-multi-year timeouts; validator drift of
  seconds is immaterial at that scale.
- **Solvency.** Developer entitlement, the reserved tranche, and the redemption
  pool are disjoint and snapshotted at trigger, keeping the contract solvent for
  all outstanding claims (integer-division dust excepted).
- **Stablecoin assumptions.** Settlement assumes a well-behaved ERC-20 stablecoin;
  fee-on-transfer and rebasing tokens are out of scope.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE-CC0).
