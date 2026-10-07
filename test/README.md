# Ochre test coverage

Run from the repository root, with the existing vendored dependencies and compiler:

```sh
forge build
forge test
forge test --match-contract OchreInvariantTest
forge test --match-contract OchreAdversarialTest
```

No RPC, environment changes, FFI, dependency downloads, or skipped tests are needed. Fuzz and invariant run counts are embedded in the test source. The existing compiler configuration remains unchanged.

## Coverage and properties

The existing `Ochre.t.sol` and `Configuration.t.sol` cover the full allocation grid, exact counts, constructor validation, sale and release boundaries, proofs, reserve limits, events, metadata, freezing, payment failures, ERC-721 transfers, and completion to 737 tokens. These tests remain intact.

`OchreInvariant.t.sol` adds **256 sequences of 96 random calls**, with unexpected handler reverts treated as failures. Only nine selected handler functions are fuzz targets: advance time, buy, sweep, claim, mint reserve, release, buy leftover, transfer, and freeze. Four funded actors include two seat holders, admin, and Adam. Time only advances. Invalid proofs, repeated claims, unauthorized operations, zero recipients/batches, expired windows, insufficient approvals, false payments, and reverted payments are deliberately attempted and checked for their expected errors. Valid actions must succeed; there is no catch-and-ignore path.

The independent ledger in `helpers/OchreHandler.sol` enumerates the brief's wall grid once. It does not obtain expected allocations from Ochre's `saleId`, `seatId`, `reserveId`, or consumption counters. Sales follow the explicit round-by-round slot priority 5,4,3,2,1; seats follow increasing numeric ID order. Properties are grounded in the assignment's allocation, payment, access, and ERC-721 rules:

| Property | Check |
| --- | --- |
| Supply and ownership conservation | Expected mint count equals `totalSupply` and the sum of all tracked NFT balances; minted IDs are unique and have the expected recipients. |
| Disjoint fixed allocations | Every accepted action consumes its predetermined sale, seat, or reserve ID; cave sales stay within 21/21/42/63/84/84/85, seats within 315, reserves within 20, total within 737. |
| Payment conservation | Each actor loses exactly the modeled purchase prices; their aggregate spending equals the dead address's coin balance; exactly one successful coin call occurs per paid mint. |
| No custody through protocol operations | Ochre's coin and ETH balances remain zero in the modeled calls. Claims, reserves, sweeps, freezes, and NFT transfers do not charge coin. |
| Atomic rejection | Expected failures do not advance the ledger; contract counters and balances must still agree, and failed payment attempts preserve allowance. |
| Irreversible transitions | Claims survive transfers, release never reopens seats, freeze never resets, and time never moves backwards into a closed sale. |
| Transfer authorization | Owner/approved transfers preserve supply and clear token approval; unauthorized transfers fail. |
| Completion after arbitrary history | At each sequence's end, audit every ID and its metadata, then sweep all remaining sales, release and buy remaining seats, and mint remaining reserves. The result must be exactly 737 owned tokens, with further mint attempts rejected. |

`testHandlerExercisesSuccessFailureAndTerminalStates` explicitly exercises every handler and both successful and rejected operations. It checks exact success/failure counts before completion so harness coverage does not rely solely on random selection.

`OchreAdversarial.t.sol` adds:

- A 1,000-run price property over constructor-supplied floors, premiums, durations, schedule slack, caves, rounds, and elapsed times. Rational bounds check that the quote lies on the price line with less than one base unit of upward rounding, alongside monotonicity and exact endpoints.
- One-wei floors, maximum start prices, the exact multiplication-guard boundary and its first invalid value, and schedules whose release threshold is `uint256.max`.
- An adversarial coin that completes and pays for a nested purchase, then returns false for the outer purchase. Both mints, counters, balances, and allowances must roll back. Retrying successfully must mint the original two IDs and emit both correct purchase events. Both sale and leftover paths are exercised.
- A single-leaf seat tree with an empty proof, including rejection of the wrong wallet, ABI-padded address hashing, and double-hashed address leaves.

## Limits

The stateful model tracks four addresses and two valid seat proofs; the existing deterministic suite separately claims all 315 seats from a larger tree. Random time is capped at ten cave lengths, and the existing suite checks leftovers much later. The post-sequence completion procedure assumes funded buyers and an available admin; eventual minting requires participation, as the brief specifies.

Coin conservation assumes an exact-transfer, truthful-bool ERC-20, modeled locally. The callback coin tests transaction ordering and rollback under an adversarial dependency; it is not a claim that the specified Sepolia WETH has callbacks. Forced ETH, unsolicited token donations, fee-taking/rebasing tokens, and compromised coin code are outside the no-custody property. The suite uses the existing mocks, not a fork of live Sepolia WETH.

Live verification of Sepolia WETH's deployed code and behavior, and a complete deployment simulation under the target chain's gas schedule, remain external checks. Local tests use the repository's configured EVM and cannot establish Glamsterdam deployment gas. No transaction is broadcast. The application source, manifest, configuration, and vendored dependencies are unchanged.
