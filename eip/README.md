# EIP submission workspace

Working area for the ERC-EMBER EIP. **Scope: layers 1–2 only** — the `IEmber`
interface and the `EmberCore` reference implementation. `EmberFactory` and
`MaintenancePool` are deliberately *not* part of the standard.

- `erc-ember-eip-draft.md` — EIP-1-formatted draft scaffold.

## Decisions (resolved 2026-05-20)

1. **Prescriptiveness** — `IEmber` **and** the burn → Ember Phase →
   release/slash/termination lifecycle are normative. Pricing curve, sale
   mechanics, storage backend, fee/treasury policy, and maintenance funding are
   implementation-defined.
2. **ERC-165** — required. `IEmber is IERC165`; preamble `requires: 20, 165`.
3. **Abandoned recovery** — removed from neutral `IEmber`. It is an optional,
   non-normative extension (`IEmberRecovery`), disabled by default for direct
   deployments and wired by the factory as product policy. Treasury/commission
   routing is excluded from core ERC conformance.

These are reflected in `erc-ember-eip-draft.md` and in the contracts
(`contracts/src/IEmber.sol`, `IEmberRecovery.sol`, `IERC165.sol`, `EmberCore.sol`).

## Process (from the v0.3 "Path to Adoption" section)

1. Open a public standards discussion topic; put its URL in
   `discussions-to`.
2. Finalize `erc-ember-eip-draft.md` per EIP-1 and keep the interface excerpt
   aligned with `contracts/src/IEmber.sol`.
3. PR to `github.com/ethereum/ercs` (ERCs were split from `ethereum/EIPs`).
4. Status: Draft → Review → Last Call → Final.

## Gotchas

- **The EIP document MUST be CC0**, not MIT. The repo code stays MIT; only this
  document is CC0. Add a `LICENSE-CC0` (or inline the standard waiver) before PR.
- The `IEmber` block in the draft must be kept aligned with
  `contracts/src/IEmber.sol`; recovery remains outside the neutral interface.
- The reference-implementation section points at `contracts/src/EmberCore.sol`;
  that file is canonical, so keep `ERC-EMBER-v0.3.md` and the EIP consistent
  with it.
