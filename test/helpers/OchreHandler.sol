// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Ochre, MockCoin} from "./Fixture.sol";

/// @notice A spec-derived allocation ledger, independent of Ochre's ordinal helpers and counters.
contract OchreHandler is Test {
    uint256 private constant START = 1791384259;
    uint256 private constant CAVE = 3600;
    uint256 private constant ROUND = 150;
    uint256 private constant HIGH = 4_000_000_000_000_000;
    uint256 private constant FLOOR = 400_000_000_000_000;
    address private constant DEAD = address(0xdead);

    Ochre public immutable collection;
    MockCoin public immutable coin;
    // Alice and Bob have seats; admin and Adam exercise purchases and transfers too.
    address[4] public actors;
    mapping(uint256 => uint256[]) private sales;
    uint256[] private seats;
    uint256[] private reserves;
    uint256[] private issued;
    mapping(uint256 => address) public owners;
    mapping(address => uint256) public nftBalances;
    mapping(address => uint256) public spent;
    mapping(address => bool) public seatClaimed;
    mapping(uint256 => uint256) public soldOrSwept;
    mapping(uint256 => string) private bases;
    uint256 public seatCursor;
    uint256 public reserveCursor;
    uint256 public payments;
    uint256 public burned;
    bool public released;
    uint256 public accepted;
    uint256 public rejected;

    constructor(Ochre collection_, MockCoin coin_, address[4] memory actors_) {
        collection = collection_;
        coin = coin_;
        actors = actors_;
        uint256[7] memory counts = [uint256(1), 1, 2, 3, 4, 4, 4];
        // Enumerate the brief's grid once instead of using saleId/seatId/reserveId as an oracle.
        uint256 first = 1;
        for (uint256 c = 1; c <= 7; ++c) {
            for (uint256 r = 1; r <= 21; ++r) {
                uint256 k = c == 7 && r == 21 ? 5 : counts[c - 1];
                for (uint256 s = 5; s > 5 - k; --s) {
                    sales[c].push(first + s - 1);
                }
                for (uint256 s = 1; s <= 5 - k; ++s) {
                    if (c < 7) seats.push(first + s - 1);
                    else reserves.push(first + s - 1);
                }
                first += 5;
            }
        }
        _minted(0, actors[3]);
        _minted(736, actors[2]);
    }

    function advanceTime(uint256 secondsSeed) public {
        // Never travel backwards: closed caves and released seats must stay closed.
        uint256 next = vm.getBlockTimestamp() + bound(secondsSeed, 0, CAVE);
        vm.warp(next > START + 10 * CAVE ? START + 10 * CAVE : next);
    }

    function buy(uint256 caveSeed, uint256 actorSeed, uint256 paymentSeed) public {
        uint256 c = bound(caveSeed, 0, 8);
        uint256 timestamp = vm.getBlockTimestamp();
        // Half the choices target the live cave; the rest probe invalid or closed caves.
        if (caveSeed % 2 == 0 && timestamp >= START && timestamp < START + 7 * CAVE) {
            c = (timestamp - START) / CAVE + 1;
        }
        bytes memory errorData;
        uint256 expectedId;
        uint256 amount;
        if (c == 0 || c > 7) {
            errorData = abi.encodeWithSelector(Ochre.InvalidCave.selector);
        } else if (timestamp < START + (c - 1) * CAVE || timestamp >= START + c * CAVE) {
            errorData = abi.encodeWithSelector(Ochre.CaveNotOpen.selector);
        } else if (soldOrSwept[c] == sales[c].length) {
            errorData = abi.encodeWithSelector(Ochre.SoldOut.selector);
        } else {
            expectedId = sales[c][soldOrSwept[c]];
            uint256 r = (expectedId - (c - 1) * 105 - 1) / 5;
            uint256 opening = START + (c - 1) * CAVE + r * ROUND;
            if (timestamp < opening) {
                errorData = abi.encodeWithSelector(Ochre.RoundNotOpen.selector);
            } else {
                uint256 elapsed = timestamp - opening;
                // Remaining premium, rounded up: an algebraically different price oracle.
                amount = elapsed >= ROUND
                    ? FLOOR
                    : FLOOR + ((HIGH - FLOOR) * (ROUND - elapsed) + ROUND - 1) / ROUND;
                assertEq(collection.priceNow(c), amount, "next piece quote");
            }
        }
        address buyer = actors[bound(actorSeed, 0, 3)];
        if (_pay(abi.encodeCall(Ochre.buy, (c)), buyer, paymentSeed, errorData, expectedId, amount)) {
            ++soldOrSwept[c];
        }
    }

    function sweep(uint256 caveSeed, uint256 batchSeed, uint256 actorSeed) public {
        uint256 c = bound(caveSeed, 1, 7);
        uint256 batch = batchSeed == type(uint256).max ? batchSeed : bound(batchSeed, 0, 90);
        bytes memory errorData;
        if (vm.getBlockTimestamp() < START + c * CAVE) {
            errorData = abi.encodeWithSelector(Ochre.TooEarly.selector);
        } else if (batch == 0) {
            errorData = abi.encodeWithSelector(Ochre.ZeroBatch.selector);
        } else if (soldOrSwept[c] == sales[c].length) {
            errorData = abi.encodeWithSelector(Ochre.SoldOut.selector);
        }
        bytes memory result =
            _call(actors[bound(actorSeed, 0, 3)], abi.encodeCall(Ochre.sweep, (c, batch)), errorData);
        if (errorData.length != 0) return;
        uint256 remaining = sales[c].length - soldOrSwept[c];
        uint256 count = batch < remaining ? batch : remaining;
        assertEq(abi.decode(result, (uint256)), count, "sweep batch size");
        for (uint256 i; i < count; ++i) {
            _minted(sales[c][soldOrSwept[c]++], actors[2]);
        }
    }

    function claim(uint256 actorSeed, bool badProof) public {
        uint256 index = bound(actorSeed, 0, 3);
        address actor = actors[index];
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = badProof ? bytes32(uint256(123)) : keccak256(abi.encodePacked(actors[index == 0 ? 1 : 0]));
        bytes memory errorData;
        if (vm.getBlockTimestamp() < START) errorData = abi.encodeWithSelector(Ochre.TooEarly.selector);
        else if (released) errorData = abi.encodeWithSelector(Ochre.SeatsReleased.selector);
        else if (seatClaimed[actor]) errorData = abi.encodeWithSelector(Ochre.AlreadyClaimed.selector);
        else if (index > 1 || badProof) errorData = abi.encodeWithSelector(Ochre.InvalidProof.selector);
        else if (seatCursor == seats.length) errorData = abi.encodeWithSelector(Ochre.SoldOut.selector);
        bytes memory result = _call(actor, abi.encodeCall(Ochre.claimSeat, (proof)), errorData);
        if (errorData.length != 0) return;
        uint256 expectedId = seats[seatCursor++];
        assertEq(abi.decode(result, (uint256)), expectedId, "claim queue order");
        seatClaimed[actor] = true;
        _minted(expectedId, actor);
    }

    function reserve(uint256 actorSeed, bool authorized, bool zeroRecipient) public {
        address recipient = zeroRecipient ? address(0) : actors[bound(actorSeed, 0, 3)];
        bytes memory errorData;
        if (!authorized) {
            errorData = abi.encodeWithSelector(Ochre.Unauthorized.selector);
        } else if (reserveCursor == reserves.length) {
            errorData = abi.encodeWithSelector(Ochre.SoldOut.selector);
        } else if (zeroRecipient) {
            errorData = abi.encodeWithSelector(IERC721Errors.ERC721InvalidReceiver.selector, address(0));
        }
        bytes memory result = _call(
            authorized ? actors[2] : actors[0], abi.encodeCall(Ochre.mintReserve, (recipient)), errorData
        );
        if (errorData.length != 0) return;
        uint256 expectedId = reserves[reserveCursor++];
        assertEq(abi.decode(result, (uint256)), expectedId, "reserve queue order");
        _minted(expectedId, recipient);
    }

    function release(uint256 actorSeed) public {
        bytes memory errorData;
        if (vm.getBlockTimestamp() < START + 8 * CAVE) {
            errorData = abi.encodeWithSelector(Ochre.TooEarly.selector);
        } else if (released) {
            errorData = abi.encodeWithSelector(Ochre.SeatsReleased.selector);
        }
        _call(actors[bound(actorSeed, 0, 3)], abi.encodeCall(Ochre.releaseUnclaimed, ()), errorData);
        if (errorData.length == 0) released = true;
    }

    function buyLeftover(uint256 actorSeed, uint256 paymentSeed) public {
        bytes memory errorData;
        if (!released) errorData = abi.encodeWithSelector(Ochre.NotReleased.selector);
        else if (seatCursor == seats.length) errorData = abi.encodeWithSelector(Ochre.SoldOut.selector);
        uint256 expectedId = seatCursor < seats.length ? seats[seatCursor] : 0;
        if (_pay(
                abi.encodeCall(Ochre.buyLeftover, ()),
                actors[bound(actorSeed, 0, 3)],
                paymentSeed,
                errorData,
                expectedId,
                FLOOR
            )) {
            ++seatCursor;
        }
    }

    function transfer(uint256 idSeed, uint256 recipientSeed, uint256 modeSeed) public {
        uint256 id = issued[bound(idSeed, 0, issued.length - 1)];
        address from = owners[id];
        address to = actors[bound(recipientSeed, 0, 3)];
        address operator = from == actors[0] ? actors[1] : actors[0];
        uint256 mode = bound(modeSeed, 0, 2);
        // Direct ownership, per-token approval, and unauthorized transfer attempts.
        if (mode == 1) {
            vm.prank(from);
            collection.approve(operator, id);
        }
        bytes memory errorData = mode == 2
            ? abi.encodeWithSelector(IERC721Errors.ERC721InsufficientApproval.selector, operator, id)
            : bytes("");
        _call(
            mode == 0 ? from : operator,
            abi.encodeWithSignature("transferFrom(address,address,uint256)", from, to, id),
            errorData
        );
        if (mode == 2) return;
        --nftBalances[from];
        ++nftBalances[to];
        owners[id] = to;
        assertEq(collection.ownerOf(id), to, "transfer owner");
        assertEq(collection.getApproved(id), address(0), "transfer clears token approval");
    }

    function freeze(uint256 caveSeed, bool authorized, bool validBase) public {
        uint256 c = bound(caveSeed, 0, 8);
        string memory base =
            validBase ? string.concat("ipfs://frozen-", vm.toString(c), "/") : "ipfs://no-slash";
        bytes memory errorData;
        if (!authorized) errorData = abi.encodeWithSelector(Ochre.Unauthorized.selector);
        else if (c == 0 || c > 7) errorData = abi.encodeWithSelector(Ochre.InvalidCave.selector);
        else if (bytes(bases[c]).length != 0) errorData = abi.encodeWithSelector(Ochre.AlreadyFrozen.selector);
        else if (!validBase) errorData = abi.encodeWithSelector(Ochre.InvalidBase.selector);
        _call(authorized ? actors[2] : actors[0], abi.encodeCall(Ochre.freeze, (c, base)), errorData);
        if (errorData.length == 0) bases[c] = base;
    }

    /// @notice Every accepted allocation consumes a new, predetermined ID, never an observed return as oracle.
    function _minted(uint256 id, address to) private {
        assertEq(owners[id], address(0), "duplicate allocation");
        assertEq(collection.ownerOf(id), to, "mint beneficiary");
        issued.push(id);
        owners[id] = to;
        ++nftBalances[to];
    }

    function _call(address caller, bytes memory data, bytes memory errorData)
        private
        returns (bytes memory result)
    {
        vm.prank(caller);
        (bool ok, bytes memory returned) = address(collection).call(data);
        if (errorData.length == 0) {
            assertTrue(ok, "valid model action reverted");
            ++accepted;
        } else {
            assertFalse(ok, "invalid model action succeeded");
            assertEq(returned, errorData, "unexpected revert");
            ++rejected;
        }
        return returned;
    }

    function _pay(
        bytes memory data,
        address buyer,
        uint256 modeSeed,
        bytes memory errorData,
        uint256 id,
        uint256 amount
    ) private returns (bool) {
        uint256 mode = bound(modeSeed, 0, 5);
        coin.setFailure(mode == 1 ? 1 : mode == 2 ? 2 : 0);
        uint256 allowance = mode == 3 && amount != 0 ? amount - 1 : 10 ether;
        vm.prank(buyer);
        coin.approve(address(collection), allowance);
        if (errorData.length == 0) {
            if (mode == 1) errorData = abi.encodeWithSelector(Ochre.PaymentFailed.selector);
            else if (mode == 2) errorData = abi.encodeWithSelector(MockCoin.ForcedFailure.selector);
            else if (mode == 3) errorData = abi.encodeWithSelector(MockCoin.InsufficientFunds.selector);
        }
        bytes memory result = _call(buyer, data, errorData);
        coin.setFailure(0);
        if (errorData.length != 0) {
            assertEq(coin.allowance(buyer, address(collection)), allowance, "failure consumed approval");
            return false;
        }
        assertEq(abi.decode(result, (uint256)), id, "purchase queue order");
        assertEq(coin.allowance(buyer, address(collection)), allowance - amount, "approval charge");
        assertEq(coin.lastFrom(), buyer, "payment source");
        assertEq(coin.lastTo(), DEAD, "payment destination");
        assertEq(coin.lastAmount(), amount, "payment amount");
        _minted(id, buyer);
        spent[buyer] += amount;
        burned += amount;
        ++payments;
        return true;
    }

    /// @notice Supply, ownership balances, disjoint allocations, one-way transitions and coin conservation.
    function assertAccounting() public view {
        uint256 balances;
        uint256 spentTotal;
        for (uint256 i; i < 4; ++i) {
            address actor = actors[i];
            assertEq(collection.balanceOf(actor), nftBalances[actor], "NFT balance ledger");
            assertEq(collection.claimed(actor), seatClaimed[actor], "seat claim is permanent");
            assertEq(coin.balanceOf(actor), 10 ether - spent[actor], "buyer coin ledger");
            balances += collection.balanceOf(actor);
            spentTotal += spent[actor];
        }
        assertEq(collection.totalSupply(), issued.length, "mint ledger supply");
        assertEq(balances, issued.length, "sum of NFT balances");
        assertLe(issued.length, 737, "fixed supply");
        for (uint256 c = 1; c <= 7; ++c) {
            assertEq(collection.saleTaken(c), soldOrSwept[c], "sale cursor");
            assertLe(soldOrSwept[c], sales[c].length, "sale allocation cap");
            assertEq(collection.frozen(c), bytes(bases[c]).length != 0, "freeze never resets");
        }
        assertEq(collection.seatsTaken(), seatCursor, "seat cursor");
        assertEq(collection.reserveTaken(), reserveCursor, "reserve cursor");
        assertLe(seatCursor, 315);
        assertLe(reserveCursor, 20);
        assertEq(collection.unclaimedReleased(), released, "release never resets");
        assertEq(coin.calls(), payments, "one coin call per purchase");
        assertEq(spentTotal, burned, "aggregate spending");
        assertEq(coin.balanceOf(DEAD), burned, "all payments reach dead");
        assertEq(coin.balanceOf(address(collection)), 0, "no coin custody on protocol paths");
        assertEq(address(collection).balance, 0, "no ETH custody on protocol paths");
        assertEq(coin.balanceOf(address(this)), 0);
    }

    /// @notice Audit ownership and metadata of every issued ID at the end of each sequence.
    function assertAllTokens() public view {
        string[7] memory labels = [
            "zto-cave-test5",
            "zto-cave-test4",
            "zto-cave-test3",
            "zto-cave-test2",
            "zto-cave-test5",
            "zto-cave-test4",
            "zto-cave-test3"
        ];
        for (uint256 id; id < 737; ++id) {
            if (owners[id] == address(0)) {
                (bool ok, bytes memory reason) =
                    address(collection).staticcall(abi.encodeWithSignature("ownerOf(uint256)", id));
                assertFalse(ok, "unrecorded mint");
                assertEq(reason, abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, id));
                continue;
            }
            assertEq(collection.ownerOf(id), owners[id], "owner ledger");
            uint256 c = id == 0 ? 1 : id == 736 ? 7 : (id - 1) / 105 + 1;
            string memory base = bytes(bases[c]).length == 0
                ? string.concat("https://", labels[c - 1], ".sites.imd.fun/")
                : bases[c];
            string memory suffix;
            if (id == 0) {
                suffix = "zero.json";
            } else if (id == 736) {
                suffix = "one.json";
            } else {
                uint256 r = (id - 1) % 105 / 5 + 1;
                uint256 s = (id - 1) % 5 + 1;
                suffix = string.concat(
                    s == 5 ? "gathering/" : string.concat("line-", vm.toString(s), "/"),
                    r < 10 ? "0" : "",
                    vm.toString(r),
                    ".json"
                );
            }
            assertEq(collection.tokenURI(id), string.concat(base, suffix), "metadata ledger");
        }
    }

    /// @notice Liveness after arbitrary history: every remaining allocation can still be completed.
    /// @dev Called only by afterInvariant/the smoke test, excluded from random selectors.
    function finish() public {
        if (vm.getBlockTimestamp() < START + 8 * CAVE) vm.warp(START + 8 * CAVE);
        for (uint256 c = 1; c <= 7; ++c) {
            if (soldOrSwept[c] < sales[c].length) sweep(c, type(uint256).max, 1);
        }
        if (!released) release(1);
        while (seatCursor < 315) buyLeftover(seatCursor % 4, 0);
        while (reserveCursor < 20) reserve(reserveCursor % 4, true, false);
        assertAccounting();
        assertEq(issued.length, 737, "all allocations remain reachable");
        buyLeftover(0, 0);
        reserve(0, true, false);
        claim(1, false);
        release(0);
        for (uint256 c = 1; c <= 7; ++c) {
            sweep(c, 1, 0);
            buy(c, 0, 0);
        }
        assertAccounting();
        assertAllTokens();
    }
}
