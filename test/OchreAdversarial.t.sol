// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {OchreFixture, Ochre} from "./helpers/Fixture.sol";

/// @dev The nested purchase pays successfully; only the OUTER transfer returns false.
/// This distinguishes transaction-wide rollback from a callback that itself fails.
contract OuterFailureCoin {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    Ochre private target;
    bool private entered;
    bool private leftovers;
    bool public rejectOuter = true;
    uint256 public calls;
    uint256 public nestedId;

    function configure(Ochre target_, address buyer, bool leftovers_) external {
        target = target_;
        leftovers = leftovers_;
        balanceOf[buyer] = 1 ether;
        balanceOf[address(this)] = 1 ether;
        allowance[address(this)][address(target)] = 1 ether;
    }

    function approve(address spender, uint256 amount) external {
        allowance[msg.sender][spender] = amount;
    }

    function allowOuter() external {
        rejectOuter = false;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        ++calls;
        if (!entered) {
            entered = true;
            nestedId = leftovers ? target.buyLeftover() : target.buy(3);
            entered = false;
            return !rejectOuter;
        }
        return true;
    }
}

contract OchreAdversarialTest is OchreFixture {
    /// forge-config: default.fuzz.runs = 1000
    function testFuzzPriceRationalBoundsAcrossConstructorParameters(
        uint128 floorSeed,
        uint128 premium,
        uint32 durationSeed,
        uint32 slackSeed,
        uint8 caveSeed,
        uint8 roundSeed,
        uint32 elapsedSeed
    ) public {
        Config memory cfg = _config();
        cfg.floor = bound(floorSeed, 1, type(uint128).max);
        cfg.high = cfg.floor + uint256(premium);
        cfg.round = bound(durationSeed, 1, 1 days);
        cfg.cave = 21 * cfg.round + bound(slackSeed, 0, 1 days);
        Ochre custom = _deploy(cfg);
        uint256 c = bound(caveSeed, 1, 7);
        uint256 r = bound(roundSeed, 1, 21);
        uint256 elapsed = bound(elapsedSeed, 0, 2 * cfg.round);
        uint256 opening = START + (c - 1) * cfg.cave + (r - 1) * cfg.round;
        assertEq(custom.caveOpen(c), START + (c - 1) * cfg.cave);
        assertEq(custom.caveClose(c), START + c * cfg.cave);
        assertEq(custom.roundOpen(c, r), opening);
        assertEq(custom.price(c, r, opening - 1), cfg.high);
        assertEq(custom.price(c, r, opening), cfg.high);
        assertEq(custom.price(c, r, opening + cfg.round), cfg.floor);
        assertEq(custom.price(c, r, type(uint256).max), cfg.floor);
        uint256 value = custom.price(c, r, opening + elapsed);
        assertGe(value, cfg.floor);
        assertLe(value, cfg.high);
        assertGe(value, custom.price(c, r, opening + elapsed + 1), "time cannot increase a round's price");
        if (elapsed >= cfg.round) {
            assertEq(value, cfg.floor);
        } else {
            // Cross-multiply the rational line: the quote is its ceiling, with < 1 wei error.
            // These uint128 prices and <= 86400-second rounds keep both sides in uint256.
            uint256 quotedPremium = (value - cfg.floor) * cfg.round;
            uint256 rationalPremium = uint256(premium) * (cfg.round - elapsed);
            assertGe(quotedPremium, rationalPremium, "rounded below price line");
            assertLt(quotedPremium - rationalPremium, cfg.round, "rounding exceeds one coin base unit");
        }
    }

    function testMaximumPricesAndScheduleRemainDefinedAtEdges() public {
        Config memory cfg = _config();
        cfg.round = 1;
        cfg.cave = 21;
        cfg.floor = 1;
        cfg.high = type(uint256).max;
        Ochre maximum = _deploy(cfg);
        assertEq(maximum.price(7, 21, START + 146), type(uint256).max);
        assertEq(maximum.price(7, 21, START + 147), 1);

        // The last valid premium at the multiplication guard, then one unit beyond it.
        cfg.round = 150;
        cfg.cave = 3150;
        cfg.high = type(uint256).max / 150 + 1;
        Ochre limit = _deploy(cfg);
        assertGe(limit.price(1, 1, START + 149), 1);
        assertLe(limit.price(1, 1, START + 149), cfg.high);
        assertEq(limit.price(1, 1, START + 150), 1);
        ++cfg.high;
        vm.expectRevert(Ochre.InvalidConfig.selector);
        _deploy(cfg);

        cfg.round = type(uint256).max / 168;
        cfg.cave = cfg.round * 21;
        cfg.start = type(uint256).max - 8 * cfg.cave;
        cfg.high = 1;
        Ochre longest = _deploy(cfg);
        assertEq(longest.caveClose(7), type(uint256).max - cfg.cave);
        assertLt(longest.roundOpen(7, 21), longest.caveClose(7));
        assertEq(longest.price(7, 21, type(uint256).max), 1);
        vm.warp(type(uint256).max - 1);
        vm.expectRevert(Ochre.TooEarly.selector);
        longest.releaseUnclaimed();
        vm.warp(type(uint256).max);
        longest.releaseUnclaimed();
        assertTrue(longest.unclaimedReleased());
    }

    function testOuterSalePaymentFailureRollsBackSuccessfulNestedPurchase() public {
        _assertNestedRollback(false);
    }

    function testOuterLeftoverPaymentFailureRollsBackSuccessfulNestedPurchase() public {
        _assertNestedRollback(true);
    }

    function _assertNestedRollback(bool leftovers) private {
        OuterFailureCoin callbackCoin = new OuterFailureCoin();
        Config memory cfg = _config();
        cfg.coin = address(callbackCoin);
        Ochre target = _deploy(cfg);
        callbackCoin.configure(target, ALICE, leftovers);
        vm.prank(ALICE);
        callbackCoin.approve(address(target), 1 ether);
        uint256 firstId = leftovers ? 1 : 215;
        uint256 secondId = leftovers ? 2 : 214;
        uint256 amount = leftovers ? FLOOR : HIGH;
        vm.warp(START + (leftovers ? 8 : 2) * CAVE);
        if (leftovers) target.releaseUnclaimed();

        vm.prank(ALICE);
        vm.expectRevert(Ochre.PaymentFailed.selector);
        if (leftovers) target.buyLeftover();
        else target.buy(3);
        assertEq(target.totalSupply(), 2);
        assertEq(target.saleTaken(3), 0);
        assertEq(target.seatsTaken(), 0);
        assertEq(target.balanceOf(ALICE), 0);
        assertEq(target.balanceOf(address(callbackCoin)), 0);
        assertEq(callbackCoin.calls(), 0);
        assertEq(callbackCoin.balanceOf(ALICE), 1 ether);
        assertEq(callbackCoin.balanceOf(address(callbackCoin)), 1 ether);
        assertEq(callbackCoin.balanceOf(DEAD), 0);
        assertEq(callbackCoin.allowance(ALICE, address(target)), 1 ether);
        assertEq(callbackCoin.allowance(address(callbackCoin), address(target)), 1 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, firstId));
        target.ownerOf(firstId);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, secondId));
        target.ownerOf(secondId);

        callbackCoin.allowOuter();
        vm.expectEmit(true, true, false, true, address(target));
        emit Bought(firstId, ALICE, amount);
        vm.expectEmit(true, true, false, true, address(target));
        emit Bought(secondId, address(callbackCoin), amount);
        vm.prank(ALICE);
        assertEq(leftovers ? target.buyLeftover() : target.buy(3), firstId);
        assertEq(callbackCoin.nestedId(), secondId);
        assertEq(target.ownerOf(firstId), ALICE);
        assertEq(target.ownerOf(secondId), address(callbackCoin));
        assertEq(target.totalSupply(), 4);
        assertEq(callbackCoin.calls(), 2);
        assertEq(callbackCoin.balanceOf(DEAD), 2 * amount);
        assertEq(callbackCoin.balanceOf(ALICE), 1 ether - amount);
        assertEq(callbackCoin.balanceOf(address(callbackCoin)), 1 ether - amount);
        assertEq(callbackCoin.balanceOf(address(target)), 0);
    }

    function testSingleLeafSeatRootUsesOneHashOfPackedAddress() public {
        Config memory cfg = _config();
        cfg.root = keccak256(abi.encodePacked(ALICE));
        Ochre single = _deploy(cfg);
        vm.warp(START);
        vm.prank(BOB);
        vm.expectRevert(Ochre.InvalidProof.selector);
        single.claimSeat(new bytes32[](0));
        vm.prank(ALICE);
        assertEq(single.claimSeat(new bytes32[](0)), 1);
        assertEq(single.ownerOf(1), ALICE);

        cfg.root = keccak256(abi.encode(ALICE));
        Ochre padded = _deploy(cfg);
        vm.prank(ALICE);
        vm.expectRevert(Ochre.InvalidProof.selector);
        padded.claimSeat(new bytes32[](0));
        cfg.root = keccak256(abi.encodePacked(keccak256(abi.encodePacked(ALICE))));
        Ochre doubleHashed = _deploy(cfg);
        vm.prank(ALICE);
        vm.expectRevert(Ochre.InvalidProof.selector);
        doubleHashed.claimSeat(new bytes32[](0));
        assertEq(padded.seatsTaken(), 0);
        assertEq(doubleHashed.seatsTaken(), 0);
    }
}
