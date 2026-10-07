# Ochre — Sepolia rehearsal

Ochre is one ERC-721 contract for 737 pieces of a wall painted live. It uses the existing Sepolia WETH at `0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14`; no coin, proxy, distributor, pool, or second application is deployed. `launch.json` configures **chain 11155111** through the deployment service. No transaction has been broadcast by this project.

## Build and check

```sh
forge build
forge test
forge fmt --check
forge build --sizes
```

`foundry.toml` pins Solidity **0.8.26**, optimizer enabled with **1 run**, **via-IR**, a Cancun instruction target, and `bytecode_hash = "none"`. There is no FFI, filesystem permission, environment-dependent test, or compiler path pin. Given Foundry and the pinned compiler, the build and tests require no network. OpenZeppelin Contracts v5.0.2 (the ERC-721/MerkleProof dependency closure) and forge-std v1.9.4 sources and licenses are ordinary files in `lib/`; each has archive provenance in `VENDORED.md`. Nothing is a submodule.

The Yul optimization sequence is the [Solidity 0.8.26 default](https://github.com/ethereum/solidity/blob/v0.8.26/libsolidity/interface/OptimiserSettings.h) with only `F` (FunctionSpecializer) omitted. This avoids duplicated event-emitting functions and the resulting trailing event-hash constant pool: the pinned deployment verifier scans even that data as opcodes. The final build has **8,163 runtime bytes**, **9,984 creation-code bytes**, and **512 constructor-argument bytes**. Both the size limit and the full-bytecode opcode scan are regression-tested.

Tests cover every ID and allocation, sale ordering, timing boundaries, price rounding, valid/invalid/duplicate proofs, all 315 seat claims, all 400 purchases, bounded sweeps, the 20-piece reserve, leftover release, payment failure rollback, reentrant coin callbacks, metadata, freeze permissions, ERC-721 transfers/receivers, constructor validation, and a mixed lifecycle reaching exactly 737 tokens. Deployment tests use an address with no coin code and enforce runtime **under 9,000 bytes**, with no CREATE, CREATE2, DELEGATECALL, CALLCODE, or SELFDESTRUCT in the application runtime.

## Deployment parameters

The nonpayable constructor accepts exactly **16 static arguments**, in this order. The manifest contains their literal ABI values, including right-padded bytes32 labels. Configuration is assigned only by the constructor; there are no configuration setters. It uses storage rather than repeated Solidity `immutable` words to reduce bytecode size.

| Position | Argument | Rehearsal value |
| --- | --- | --- |
| 1 | `coin_` (address) | `0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14` |
| 2 | `admin_` (address) | `0x7B8C742F2e1eEB3fB2C10d72967Fa6d4a22f0479` |
| 3 | `adam_` (address) | `0x7B8C742F2e1eEB3fB2C10d72967Fa6d4a22f0479` |
| 4 | `seatRoot_` (bytes32) | `0x1111111111111111111111111111111111111111111111111111111111111111` |
| 5 | `startTime_` (uint256) | `1791384259` — 2026-10-07 14:44:19 UTC |
| 6 | `caveLength_` (uint256) | `3600` seconds |
| 7 | `roundLength_` (uint256) | `150` seconds |
| 8 | `startPrice_` (uint256) | `4000000000000000` — 0.004 WETH, common to all caves |
| 9 | `floorPrice_` (uint256) | `400000000000000` — 0.0004 WETH |
| 10 | `label1` (bytes32) | `zto-cave-test5` |
| 11 | `label2` (bytes32) | `zto-cave-test4` |
| 12 | `label3` (bytes32) | `zto-cave-test3` |
| 13 | `label4` (bytes32) | `zto-cave-test2` |
| 14 | `label5` (bytes32) | `zto-cave-test5` |
| 15 | `label6` (bytes32) | `zto-cave-test4` |
| 16 | `label7` (bytes32) | `zto-cave-test3` |

The dead address is the constant `0x000000000000000000000000000000000000dEaD`; coin decimals are the constant `18`. The constructor never reads WETH, checks its bytecode, or calls token recipients. It mints ID 0 to Adam and ID 736 to admin, regardless of the deploying factory's address. Constructor configuration rejects zero coin/beneficiaries/root, zero round duration or floor, a start price below the floor, and schedules with `21 * roundLength > caveLength`. It also rejects arithmetic-overflow configurations. A 21-round exact fit is allowed, as are equal start/floor prices. Labels must be nonempty ASCII, up to 32 bytes, with only zeros after the first zero; the operator is responsible for choosing valid host labels.

## Pieces and schedule

IDs 0 and 736 are Zero and One. For every other ID:

```text
cave  = (id - 1) / 105 + 1
round = ((id - 1) % 105) / 5 + 1
slot  = (id - 1) % 5 + 1
```

Integer division is used. Slots 1–4 are lines; slot 5 is the gathering. `piece(id)` returns these coordinates for IDs 1–735 and rejects the two endpoints and out-of-range IDs.

| Cave | Sale slots per round | Sale pieces | Seat pieces | Admin reserve |
| --- | --- | --- | --- | --- |
| 1 | 1 | 21 | 84 | 0 |
| 2 | 1 | 21 | 84 | 0 |
| 3 | 2 | 42 | 63 | 0 |
| 4 | 3 | 63 | 42 | 0 |
| 5 | 4 | 84 | 21 | 0 |
| 6 | 4 | 84 | 21 | 0 |
| 7 | 4, except 5 in round 21 | 85 | 0 | 20 |
| Total | | **400** | **315** | **20** |

The two endpoints bring the total to **737**. There is no burn function, arbitrary mint, or way to mint outside these allocations. `totalSupply()` counts minted tokens; ERC-721 enumeration is not implemented.

`caveOpen(c) = startTime + (c - 1) * caveLength`; `caveClose(c)` is one cave length later. `roundOpen(c,r) = caveOpen(c) + (r - 1) * roundLength`. A cave is open on **[open, close)**. Caves are numbered 1–7 and rounds 1–21. The final cave closes at 2026-10-07 21:44:19 UTC. The rehearsal plays out over seven hours; the constructor also supports 86,400-second caves and 3,600-second rounds for a separately configured deployment.

**Ordering interpretation:** the brief's explicit slot priority `5,4,3,2,1` takes precedence over its phrase “in id order” for sales and sweeps. Rounds advance from 1 to 21, and each round consumes its eligible slots in that descending priority. For example, cave 3 starts `215,214,220,219`. Seats use strictly increasing numeric IDs, skipping sale slots. Reserve IDs are `631,636,...,726`. `saleId(c,index)`, `seatId(index)` and `reserveId(index)` expose these zero-based ordinals.

## Buying and giving away

Each round has its own price curve. Before/on its opening, the mathematical `price(c,r,t)` view returns the start price; for elapsed time `e` strictly between zero and `roundLength`:

```text
price = startPrice - ((startPrice - floorPrice) * e / roundLength)
```

The discount is rounded down to base units, so fractional prices round toward the start price by less than one base unit. From the round's end onward, the view returns the floor. This mathematical view works outside the sale window; **`buy(c)` and `priceNow(c)` enforce the window**. They reject before the cave opens, at/after close, after all its sale pieces are consumed, or before the next piece's round opens. Unsold earlier rounds remain at their own floor even when a later round begins.

Rehearsal wallets wrap Sepolia ETH into WETH themselves, approve Ochre, then call `buy(c)`. There is no wallet purchase limit or ID choice. Each purchase mints the next sale piece and calls only `coin.transferFrom(buyer, dead, price)`, requiring a returned `true`. False, reverted, missing, or malformed return data reverts the entire transaction, including mint, counters, and logs. It emits `Bought(id,buyer,price)` in addition to ERC-721 `Transfer`.

Once a cave closes, anyone may call `sweep(c,max)`. It mints up to `max` remaining sale pieces to admin, in the same sale order, emitting `Swept(id)` per piece. `max = 0`, premature calls, and exhausted caves revert. A very large `max` is capped at the actual remaining allocation. Repeat bounded batches until empty. Sweeping never touches seat or reserve IDs and never charges WETH.

From `startTime`, `claimSeat(proof)` gives the caller the next free ID in caves 1–6, gas only, with `Claimed(id,wallet)`. The leaf is **one keccak256 hash of the raw 20 address bytes** (`keccak256(abi.encodePacked(address))`), with each internal pair sorted by bytes32 value before hashing. It is not ABI-padded or double-hashed. Each wallet may claim once even after transferring its NFT away. A proof cannot be used for a different caller. The 315-seat allocation can exhaust before a larger allowlist does.

The rehearsal root is a placeholder, with **no usable seat list or proofs supplied**. A real deployment needs the independently checked root before deployment; there is no root-update power. The tests use their own concrete trees.

`mintReserve(to)` is admin-only, may be called at any time, and mints the next cave-7 reserve piece to any nonzero recipient, at most 20. It emits `Reserved(id,wallet)`.

At or after `startTime + 8 * caveLength` (2026-10-07 22:44:19 UTC), anyone may call `releaseUnclaimed()`, once, emitting `UnclaimedReleased()`. This explicitly ends claims. The time threshold alone does not end them: a valid claim remains possible until the release transaction executes. After release, `buyLeftover()` sells the next remaining seat ID at the floor through the same direct-to-dead payment path and `Bought` event. These purchases have no closing time or wallet limit. Sold-out leftovers revert. Reserve and unsold sale pieces are unaffected by release.

**Eventual supply is conditional on participation:** somebody must buy leftovers, callers must sweep all expired sales, and admin must assign all 20 reserves. There is no timer-driven automatic mint or forced completion.

## Metadata and ERC-721

The default base is `https://<label>.sites.imd.fun/`. Ordinary paths are `line-<slot>/<two-digit-round>.json` or `gathering/<two-digit-round>.json`. Zero uses cave 1's `zero.json`, and One uses cave 7's `one.json`. Unminted IDs revert. Strings are constructed with `string.concat`; no multiple-dynamic-argument packed encoding is used.

Admin may call `freeze(c,base)` once per cave, even before its pieces mint. `base` must be nonempty and end in `/`; it replaces the whole web base verbatim, without changing suffixes. For example, `ipfs://<cid>/`. `Frozen(cave,base)` records it. Cave 1 also changes Zero; cave 7 also changes One. Identical rehearsal labels do not couple caves' freeze state. The contract does not validate URI schemes or content, ensure availability, pin IPFS data, or verify that a base is content-addressed. A permanent base pointing to mutable HTTPS content does not make the content immutable.

Name is `Ochre`; symbol is `OCHRE`. ERC-165, ERC-721, and ERC-721Metadata interfaces are supported, with standard approval and safe-transfer behavior from [OpenZeppelin v5.0.2](https://github.com/OpenZeppelin/openzeppelin-contracts/releases/tag/v5.0.2) implementing [ERC-721](https://eips.ethereum.org/EIPS/eip-721). ERC-2981 royalties and ERC-721Enumerable are not supported. No NFT receiver callback occurs on mint: callers and admin must choose recipients capable of managing NFTs. This allows constructor mints without external calls and keeps the WETH call last in purchases. Standard `safeTransferFrom` still checks receiving contracts.

## Operational responsibilities and limits

- The deployment service must confirm chain 11155111, verify the existing WETH address/code and its 18-decimal behavior, preserve the manifest's parameters, and simulate the complete factory deployment under the actual target fork and transaction gas ceiling. The fixed start timestamp does not shift if deployment is late. No live RPC verification or funded-wallet operation was performed here.
- Local tests run the configured Cancun EVM and do not reproduce the brief's Glamsterdam deployment gas schedule. The runtime-size regression test is a byte budget, not a substitute for the deployment service's full gas simulation, including constructor/factory work.
- Admin has exactly two special powers: assign the reserve and freeze each cave's URI base once. It also receives One and swept sale pieces; Adam receives Zero. There is no Ownable module, administrator rotation, pause, upgrade, mint expansion, fund withdrawal, or arbitrary external-call facility. Lost admin access leaves reserve/freeze work incomplete.
- Admin must validate final files and base URIs and arrange durable hosting/pinning before freezing. Seat organizers must publish the seat list/proofs securely. Keepers must fund gas to release leftovers and sweep closed caves; no keeper reward exists.
- All mint state and purchase events precede the coin call; there is no ReentrancyGuard. A callback observes consumed allocations, and a failed payment rolls everything back. The expected coin is the specified conventional WETH, with a truthful bool return and exact transfers. Configuring a malicious, fee-taking, rebasing, or incompatible token is unsupported.
- Ochre never takes custody on its payment paths and rejects ordinary ETH transfers. Anyone can forcibly send ETH or transfer tokens/NFTs directly to a contract; those unsolicited assets cannot be recovered here. Sending WETH to `dead` immobilizes it there; it does not call a WETH burn function or reduce WETH's reported total supply.
- Block timestamps determine windows and prices by design. Transactions can be reordered or delayed: another purchase may advance the next piece into a newer round with a higher price. `buy(c)` has no price cap or expected-ID argument. A wallet can bound exposure with an exact WETH allowance, but cannot reserve an ID. A claim can lose a race with release at/after its threshold.
- The suite includes adversarial callback/payment tests and Foundry fuzzing. Slither and Mythril were not available/run. Passing tests is not an independent security audit; independent contract and manifest review and final fork-aware deployment simulation remain the release operator's responsibilities.
