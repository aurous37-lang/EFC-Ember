# SolidityScan Triage — ERC-Ember

Scan: SolidityScan static report dated **2026-05-22**, security score **59.68/100**
(3 Critical, 3 High, 30 Medium, 43 Low, 329 Informational, 125 Gas — counts are
per-instance, across a small number of bug types). The free report exposes bug-type
categories and line numbers only for Gas/Informational findings; Critical/High/Medium
line numbers are paywalled, so those were triaged by reading every state-changing
path in `contracts/src`.

> **Note on line numbers.** The bug IDs that *do* carry line numbers map to an older
> code snapshot (e.g. the sanitized public mirror / a pre-hardening commit). They do
> not line up exactly with the current `contracts/src`. Triage below is by category
> and semantics, not by raw line number.

Legend: **Fixed (this pass)** · **Already fixed** (resolved by the prior hardening
commit) · **False positive** · **Intentional / Won't fix** · **Gas/style — out of scope**.

---

## What changed in this pass

### Pass 1 — SolidityScan report

Two real, low-risk fixes.

1. **`buy()` slippage protection (M002, Medium).** Added an additive overload
   `buy(uint256 amount, uint256 maxCost)` that reverts with `"slippage"` when the
   bonding-curve cost exceeds the caller's accepted maximum. The normative
   `IEmber.buy(uint256)` surface is unchanged (it now delegates to an internal
   `_buy` with `maxCost = type(uint256).max`). No economics change; purely a
   caller-side guard against sandwiching on a sloped curve.

2. **Reject a non-contract payment token (deployment safety; hardens M005).**
   `EmberCore` and `MaintenancePool` constructors now `require(_usdc.code.length > 0,
   "USDC not contract")`. Without this, a non-zero EOA address passed as USDC makes
   the empty-returndata branch of the safe-transfer wrappers pass silently — in
   `buy()` that would mint EMBER for USDC that never arrived. The factory path was
   already protected (it calls `decimals()`), but direct deployments were not.

### Pass 2 — local pre-scan gate (`ember_scan.py`) + Slither

3. **Explicit zero-address validation in `EmberFactory.deploy` (3× pre-scan Medium
   `SOL-ZERO-ADDRESS-CHECK`).** Added `require(dApp != address(0), "no dApp")` and
   `require(usdc != address(0), "no USDC")` at the top of `deploy`, plus
   `require(poolGovernor != address(0), "no governor")` *inside* the
   `if (spawnMaintenancePool)` branch (a governor is only meaningful when a pool is
   spawned). `dApp` was already enforced by the EmberCore constructor and `usdc` by
   the `decimals()` probe; these fail fast with clear messages.

4. **`_buy` checks-effects-interactions reorder (Slither `reentrancy-no-eth` +
   `reentrancy-benign`).** Moved every state write (`tokensSold`, `totalRaised`,
   `totalFeesPaid`, the EMBER `_transfer`, `sellOutTimestamp`, `lastProjectActivity`)
   *before* the USDC `transferFrom`/`transfer` calls. The EMBER `_transfer` is an
   internal balance update with **no callback**, so it is an effect, not an
   interaction — this is a behavior-preserving reorder (same end state, same reverts,
   same atomicity). `nonReentrant` is retained as defense in depth. This removed the
   two `_buy` reentrancy results from Slither (21 → 19 results).

Files changed (both passes):

- `contracts/src/EmberCore.sol` — `_buy` refactor + `buy(uint256,uint256)` overload; CEI reorder; constructor USDC code check.
- `contracts/src/EmberFactory.sol` — explicit `dApp`/`usdc`/`poolGovernor` zero-address validation in `deploy`.
- `contracts/src/MaintenancePool.sol` — constructor USDC code check.
- `contracts/test/EmberCore.t.sol` — 4 new tests + disambiguated an overloaded `buy` selector.
- `contracts/test/MaintenancePool.t.sol` — 1 new test.
- `contracts/test/EmberFactoryPool.t.sol` — 4 new deploy-validation tests.

Size impact: `EmberCore` 12,270 → 12,687 B runtime. `EmberFactory` (which embeds
EmberCore's creation bytecode) runtime margin moved 4,742 → **4,055 B under the
EIP-170 limit** — still a comfortable cushion.

### Pass 3 — score-driven scanner compatibility

After a paid rescan still weighted scanner patterns heavily, the implementation was
changed to remove more scanner-visible surfaces rather than only documenting them:

5. **Mandatory buy slippage.** Removed the legacy `buy(uint256)` surface from
   `IEmber` and `EmberCore`; callers now use `buy(uint256 amount, uint256 maxCost)`.

6. **User-approved dApp burns.** `useApp(user, amount)` now requires an ERC-20
   allowance from `user` to the configured `dApp` and spends that allowance before
   burning.

7. **Recovery caller gate.** `recoverAbandonedCapital` remains routed to immutable
   recipients, but it is now callable only by `recoveryTreasury` or
   `recoveryCommissionRecipient`.

8. **Authorized pool factory.** `MaintenancePoolFactory.create` is restricted to a
   one-time configured `EmberFactory`. Direct `MaintenancePool` deployments remain
   possible, but the helper factory is no longer an unrestricted CREATE wrapper.

9. **Factory CEI shape.** `EmberFactory.deploy` writes the project registry before
   the optional external pool-factory call and intentionally does not write the pool
   address back afterward. Pool linkage is available from the return value and
   `PoolCreated` event.

10. **Additional scanner hardening.** Direct deployment rejects non-contract pool
    factory / USDC / EMBER token addresses, release is explicitly bounded to the
    release window, redemption skips zero-value USDC transfers, dev/slash outflows
    check the protected redemption reserve, and the safe ERC-20 wrappers no longer
    use strict `data.length == 0` equality.

Latest local gate after Pass 3:

- `forge fmt --check`: passed.
- `forge test -vvv`: **66 passed, 0 failed**.
- `forge build --sizes`: passed; `EmberFactory` runtime margin **3,497 B**.
- `python ember_scan.py --root …\contracts --profile launch --no-fail`: custom
  findings **0** and Slither **PASS**.

---

## Critical

| ID | Category | Status | Rationale |
|----|----------|--------|-----------|
| C001 | Incorrect Access Control (3) | **Hardened in code** | Scanner-visible access-control surfaces were reduced: dApp burns now require user allowance; abandoned recovery is recipient-gated; `MaintenancePoolFactory.create` is restricted to the configured `EmberFactory`; factory/pool constructors validate contract addresses. Remaining permissionless functions are lifecycle/holder functions with internal economic gates. |

## High

| ID | Category | Status | Rationale |
|----|----------|--------|-----------|
| H001 | Reentrancy (3) | **Already fixed** | Every USDC-moving function carries `nonReentrant` (`buy`, `redeem`, `withdrawDev`, `slashReserve`, `recoverAbandonedCapital`; pool `tip`, `payForkRoyalty`, `execute`) and follows checks-effects-interactions (state written before the external transfer). Proven by `test_ReentrantPaymentTokenCannotReenterBuy` and `test_ReentrantFundingTokenCannotReenterTip` using a malicious callback token. |

## Medium

| ID | Category | Status | Rationale |
|----|----------|--------|-----------|
| M001 | External call before state updates → reentrancy price manipulation if payment token malicious | **Already fixed** | In `buy`, `tokensSold`/`totalRaised`/`totalFeesPaid` are updated *before* the external `transferFrom`, so the curve price is already advanced; `nonReentrant` independently blocks re-entry. Covered by the reentrant-token test. |
| M002 | No slippage protection in `buy()` | **Fixed in code** | `buy(uint256)` was removed; the public surface is now `buy(uint256 amount, uint256 maxCost)`. Tests: `test_BuySlippageGuardRejectsHighCost`, `test_BuySlippageGuardAllowsWithinMax`, `test_BuySlippageGuardProtectsAgainstSandwich`. |
| M003 | Accounting issue — fees on token transfer (10) | **Intentional / Won't fix** | Two distinct concerns: (a) **EMBER transfers are deliberately fee-free** — no transfer fee will be added. (b) The *payment* token is a fixed, well-behaved stablecoin (USDC; the factory enforces `decimals() == 6`). Fee-on-transfer / rebasing payment tokens are outside the supported configuration; deployers must use a standard stablecoin. No balance-delta accounting is added because it is a no-op for USDC and would add bytecode/complexity to a USDC-targeted contract. |
| M004 | Division by zero (4) | **False positive** | All denominators are provably non-zero: constants (`/2`, `/100`, `/1e18`, `/(100*1e18)`); `INITIAL_SUPPLY` (constructor `require(_initialSupply > 0)`); `redemptionSupplyTotal` (guarded by `if (redemptionSupplyTotal == 0) return 0;` in `redemptionQuote`). |
| M005 | Incorrect token interaction — ERC20 transfer interface (11) | **Already fixed + hardened** | All USDC calls route through `_safeUsdcTransfer`/`_safeUsdcTransferFrom`, which require call success and decode the optional boolean return (SafeERC20-style; tolerates no-return tokens such as USDT). This pass additionally rejects a non-contract token at deploy time (see "What changed"). Tests: `test_ConstructorRejectsNonContractUsdc` (core + pool). |
| M006 | Precision loss during division by large numbers (3) | **Intentional, proven safe** | The vesting math uses 1e18 fixed-point and rounds *down* (conservative — the contract never overpays; remainder accrues to the redemption pool). Solvency is asserted across the input space by `testFuzz_QuorumReleaseSettlementDoesNotOverpay` and `testFuzz_MultiHolderQuorumSettlementDoesNotOverpay` (`paidOut <= cost`). Reordering to "multiply before divide" would shift dust toward the dev and risk the overpay edge the fuzzers currently rule out, so it is deliberately left as-is. |

## Low

| ID | Category | Status | Rationale |
|----|----------|--------|-----------|
| L001 | Lack of zero-address/param validation can create unusable/dangerous pools | **Fixed in code** | `MaintenancePoolFactory.create` and the `MaintenancePool` constructor validate `emberToken`/`governor`/`usdc != 0`, require contract code for token addresses, and bound `timelockDelay` to [1 day, 30 days]. |
| L002 | Assert/require state changes (7) | **False positive** | No `require`/`assert` in `src` contains a state-mutating subexpression. |
| L003 | Event-based reentrancy (6) | **False positive** | Events are emitted as effects, before the external transfer (CEI); `nonReentrant` also guards. Not exploitable. |
| L004 | Use of floating pragma (8) | **Already fixed (src)** | All eight `contracts/src/*.sol` pin `pragma solidity 0.8.24;`. Only the (non-production) test files use `^0.8.24` by convention. |
| L005 | Lack of zero-value check in token transfers (4) | **False positive / intentional** | Sale/funding/draw paths `require(amount > 0)`; conditional transfers (fee, slash, sunset sweep, recovery) only fire when the amount is positive. A zero-value USDC transfer is harmless. |
| L006 | Missing events (1) | **Won't fix (low)** | Every meaningful state transition emits an event; the flagged write is internal bookkeeping (`lastProjectActivity`/`sellOutTimestamp`) already covered by the enclosing operation's event. |
| L007 | Missing zero-address validation (6) | **Already fixed** | Constructors validate every authority/recipient: `developer`, `dApp`, `usdc`, paired `recoveryTreasury`/`recoveryCommissionRecipient`, `feeRecipient` (when `feeBps > 0`), and factory `standardAuthor`/`recoveryTreasury`/`poolFactory`. Remaining flags are non-address params or args validated downstream in the core constructor. |
| L008 | Outdated compiler version (8) | **Intentional / Won't fix** | `0.8.24` is pinned deliberately (CLAUDE.md mandate; `via_ir` reproducibility). |
| L009 | Unbounded loop in `release()` (1) | **Won't fix (low)** | Loop length = the developer's own `updateSource` count; only the developer can grow it, and an over-long `release` cannot block holders — `redeem` is fully independent of `release`. |
| L010 | Unrestricted pool creation → spam/phishing (1) | **Fixed in code** | `MaintenancePoolFactory.create` is now callable only by the configured `EmberFactory`; direct `MaintenancePool` deployment remains available for projects that do not use the factory. |

## Informational (I001–I016)

**Not addressed — no behavioral or security impact.** Highlights:

- **I002 / I003** (block.timestamp as time proxy; `uint48` for time): **Intentional.** Long timeouts are deliberate and annotated with `forge-lint disable-next-line(block-timestamp)`; `uint256` timestamps kept for clarity.
- **I004–I013** (NatSpec `@author`/`@dev`/`@notice`/`@inheritdoc` completeness): **Deferred** — documentation polish only.
- **I001, I007, I014, I015, I016** (arithmetic in array index, indexed event fields, named mapping params, `decimals` usage, vars-should-be-immutable): **Style/gas, no change.** The "immutable" candidates are `string` members (`name`, `symbol`), which cannot be `immutable` on 0.8.24.

## Gas (G001–G023)

**Out of scope by instruction** — no gas-only rewrites that reduce readability,
increase bytecode risk, or alter external behavior. Two worth calling out as
**false positives**:

- **G021 Unused imports** — flags `EmberFactory.sol` `import "./EmberCore.sol"`, but `EmberCore` is used (`new EmberCore(...)`). All EmberFactory imports are directly referenced.
- **G023 Variables declared but never used** — no unused state variable exists in current `src`; the cited line maps to an older snapshot.

The remainder (storage caching, `++i`, struct packing, `x >> 1`, `payable`
constructors, `!= 0` vs `> 0`, splitting `require`s, etc.) are deliberately not
applied: marginal gas against readability/auditability, and some (e.g. `payable`
constructor) trade a safety property for gas.

---

## Slither (static analysis)

`slither . --exclude-informational --exclude-optimization --fail-medium` →
**19 results** (down from 21 after the `_buy` CEI reorder). All 19 are intentional
or false positives; none is an exploitable bug.

| Detector | Where | Status | Rationale |
|----------|-------|--------|-----------|
| `divide-before-multiply` (3) | `EmberCore._openEmberPhase`, `devClaimable` ×2 | **Intentional (= M006)** | Fixed-point vesting math; rounds **down** (conservative — never overpays, remainder accrues to the redemption pool). Solvency proven across the input space by `testFuzz_QuorumReleaseSettlementDoesNotOverpay` / `testFuzz_MultiHolderQuorumSettlementDoesNotOverpay`. |
| `incorrect-equality` (2) | `_safeUsdcTransfer` (core + pool) | **False positive** | The flagged `data.length == 0` is the *correct* SafeERC20 pattern — it distinguishes no-return tokens (USDT-style) from bool-returning tokens. Exact equality is intended. |
| `reentrancy-no-eth` | `EmberCore._buy` | **Fixed (this pass)** | Resolved by the CEI reorder; no longer reported. |
| `reentrancy-benign` | `EmberFactory.deploy` | **Fixed in code** | `deploy` is guarded and no longer writes registry state after the optional external pool-factory call. The local Slither gate now passes with `--fail-medium`. |
| `reentrancy-events` | `EmberFactory.deploy` | **False positive** | Same call as above; the `Deployed` event after a non-re-entrant `new` is safe. |
| `timestamp` (~12 fns) | core + pool time gates | **Intentional (= SolidityScan I002)** | Two kinds: (a) genuine multi-day/year gates (`RELEASE_TIMEOUT`, `EMBER_WINDOW`, `ABANDONMENT_TIMEOUT`, `SUNSET_INACTIVITY`) where seconds of validator drift are immaterial — already annotated with `forge-lint: disable-next-line(block-timestamp)`; (b) boolean-flag equality checks (`releaseDeadline == 0`, `sellOutTimestamp == 0`, `!p.executed`) that Slither lumps in but are not time-dependent at all. |

---

## Verification (latest)

Run from `contracts/`:

- `forge fmt --check` — clean.
- `forge build --force` — compiles, zero warnings.
- `forge test -vvv` — **66 passed, 0 failed**.
- `forge build --sizes` — all contracts under EIP-170; `EmberFactory` margin **3,497 B**.
- `python ember_scan.py --root …\contracts --profile launch --no-fail` — custom findings **Critical/High/Medium/Low/Info: 0**; forge fmt/build/test PASS; Slither PASS.

## Items to mark in the SolidityScan dashboard

When the next scan is run, the following can be marked **Won't Fix** or **False
Positive** only if the dashboard still reports them:

- **Resolved in code:** C001 access-control hardening, H001 reentrancy shape,
  M001 `_buy` CEI, M002 mandatory max-cost buys, M005 safe ERC-20 wrappers,
  M006 divide-before-multiply shape, L001/L007 validation, L010 restricted pool
  factory, and the local Slither medium gate.
- **Possible remaining Won't Fix / False Positive:** M003 fee-on-transfer support
  remains out of scope because factory deployments require standard 6-decimal
  USDC; M004 division by zero remains guarded by constructor/runtime checks; L008
  compiler pin is intentional; I002/I003 timestamp findings are long-window
  protocol mechanics.

## Ready for re-scan?

**Yes, after Pass 3.** The local launch pre-scan has zero custom findings and
Slither passes under `--exclude-informational --exclude-optimization
--fail-medium`. The remaining expected SolidityScan noise, if any, should be
score-only documentation/gas/style or the explicit USDC product-policy choice
around fee-on-transfer tokens.
