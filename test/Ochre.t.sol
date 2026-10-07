// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {OchreFixture, MockCoin, Ochre} from "./helpers/Fixture.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {Vm} from "forge-std/Vm.sol";

contract OchreTest is OchreFixture {
    function testConstructorConfigurationAndInterfaces() public view {
        assertEq(ochre.name(), "Ochre");
        assertEq(ochre.symbol(), "OCHRE");
        assertEq(address(ochre.coin()), address(coin));
        assertEq(ochre.coinDecimals(), 18);
        assertEq(ochre.dead(), DEAD);
        assertEq(ochre.admin(), ADMIN);
        assertEq(ochre.adam(), ADAM);
        assertEq(ochre.seatRoot(), _pair(_leaf(ALICE), _leaf(BOB)));
        assertEq(ochre.startTime(), START);
        assertEq(ochre.caveLength(), CAVE);
        assertEq(ochre.roundLength(), ROUND);
        assertEq(ochre.floorPrice(), FLOOR);
        assertEq(ochre.ownerOf(0), ADAM);
        assertEq(ochre.ownerOf(736), ADMIN);
        assertEq(ochre.balanceOf(ADAM), 1);
        assertEq(ochre.balanceOf(ADMIN), 1);
        assertEq(ochre.totalSupply(), 2);
        assertTrue(ochre.supportsInterface(0x01ffc9a7));
        assertTrue(ochre.supportsInterface(0x80ac58cd));
        assertTrue(ochre.supportsInterface(0x5b5e139f));
        assertFalse(ochre.supportsInterface(0x2a55205a));
        assertFalse(ochre.supportsInterface(0x780e9d63));
        assertFalse(ochre.supportsInterface(0xffffffff));
        for (uint256 c = 1; c <= 7; ++c) {
            assertEq(ochre.startPrice(c), HIGH);
            assertEq(ochre.caveOpen(c), START + (c - 1) * CAVE);
            assertEq(ochre.caveClose(c), START + c * CAVE);
            for (uint256 r = 1; r <= 21; ++r) {
                assertEq(ochre.roundOpen(c, r), START + (c - 1) * CAVE + (r - 1) * ROUND);
            }
        }
    }

    function testDeploymentInEmptySepoliaEvmAndCodeBudget() public {
        vm.chainId(11155111);
        assertEq(WETH.code.length, 0);
        Config memory c = _config();
        c.coin = WETH;
        c.adam = ADMIN;
        c.root = bytes32(uint256(0x1111111111111111111111111111111111111111111111111111111111111111));
        vm.prank(address(0xFAC));
        Ochre deployed = _deploy(c);
        assertEq(deployed.ownerOf(0), ADMIN);
        assertEq(deployed.ownerOf(736), ADMIN);
        assertEq(address(deployed.coin()), WETH);
        assertLt(address(deployed).code.length, 9000);
        bytes memory code = address(deployed).code;
        for (uint256 i = 0; i < code.length; ++i) {
            uint8 op = uint8(code[i]);
            if (op >= 0x60 && op <= 0x7f) {
                i += op - 0x5f;
                continue;
            }
            assertTrue(op != 0xf4 && op != 0xf2 && op != 0xff && op != 0xf0 && op != 0xf5);
        }
    }

    function testEveryPieceAndExactAllocation() public view {
        uint256[7] memory counts = [uint256(21), 21, 42, 63, 84, 84, 85];
        uint256[7] memory ks = [uint256(1), 1, 2, 3, 4, 4, 4];
        bool[737] memory seen;
        uint256 seats = 0;
        uint256 reserve = 0;
        uint256 sold = 0;
        for (uint256 c = 1; c <= 7; ++c) {
            uint256 ordinal = 0;
            assertEq(ochre.saleCount(c), counts[c - 1]);
            for (uint256 r = 1; r <= 21; ++r) {
                uint256 k = c == 7 && r == 21 ? 5 : ks[c - 1];
                assertEq(ochre.saleSlots(c, r), k);
                for (uint256 s = 1; s <= 5; ++s) {
                    uint256 id = (c - 1) * 105 + (r - 1) * 5 + s;
                    (uint256 actualC, uint256 actualR, uint256 actualS) = ochre.piece(id);
                    assertEq(actualC, c);
                    assertEq(actualR, r);
                    assertEq(actualS, s);
                    if (s <= 5 - k) {
                        if (c <= 6) assertEq(ochre.seatId(seats++), id);
                        else assertEq(ochre.reserveId(reserve++), id);
                        assertFalse(seen[id]);
                        seen[id] = true;
                    }
                }
                for (uint256 offset = 0; offset < k; ++offset) {
                    uint256 id = (c - 1) * 105 + (r - 1) * 5 + 5 - offset;
                    assertEq(ochre.saleId(c, ordinal++), id);
                    assertFalse(seen[id]);
                    seen[id] = true;
                    ++sold;
                }
            }
            assertEq(ordinal, counts[c - 1]);
        }
        assertEq(sold, 400);
        assertEq(seats, 315);
        assertEq(reserve, 20);
        for (uint256 id = 1; id <= 735; ++id) {
            assertTrue(seen[id]);
        }
    }

    function testInvalidCoordinatesAndOrdinalsRevert() public {
        vm.expectRevert(Ochre.InvalidPiece.selector);
        ochre.piece(0);
        vm.expectRevert(Ochre.InvalidPiece.selector);
        ochre.piece(736);
        vm.expectRevert(Ochre.InvalidPiece.selector);
        ochre.piece(type(uint256).max);
        vm.expectRevert(Ochre.InvalidCave.selector);
        ochre.caveOpen(0);
        vm.expectRevert(Ochre.InvalidCave.selector);
        ochre.caveClose(8);
        vm.expectRevert(Ochre.InvalidCave.selector);
        ochre.saleCount(8);
        vm.expectRevert(Ochre.InvalidRound.selector);
        ochre.roundOpen(1, 0);
        vm.expectRevert(Ochre.InvalidRound.selector);
        ochre.price(1, 22, START);
        vm.expectRevert(Ochre.SoldOut.selector);
        ochre.seatId(315);
        vm.expectRevert(Ochre.SoldOut.selector);
        ochre.reserveId(20);
        vm.expectRevert(Ochre.SoldOut.selector);
        ochre.saleId(7, 85);
    }

    function testPriceBoundariesAndRoundSpecificReset() public view {
        for (uint256 c = 1; c <= 7; ++c) {
            for (uint256 r = 1; r <= 21; ++r) {
                uint256 t = START + (c - 1) * CAVE + (r - 1) * ROUND;
                assertEq(ochre.price(c, r, t - 1), HIGH);
                assertEq(ochre.price(c, r, t), HIGH);
                assertEq(ochre.price(c, r, t + 75), 2_200_000_000_000_000);
                assertEq(ochre.price(c, r, t + 149), 424_000_000_000_000);
                assertEq(ochre.price(c, r, t + 150), FLOOR);
                assertEq(ochre.price(c, r, type(uint256).max), FLOOR);
            }
        }
    }

    function testFuzzPriceIsBoundedMonotonicAndRounded(uint8 caveSeed, uint8 roundSeed, uint16 elapsedSeed)
        public
        view
    {
        uint256 c = uint256(caveSeed) % 7 + 1;
        uint256 r = uint256(roundSeed) % 21 + 1;
        uint256 elapsed = uint256(elapsedSeed);
        uint256 t = START + (c - 1) * CAVE + (r - 1) * ROUND;
        uint256 value = ochre.price(c, r, t + elapsed);
        assertGe(value, FLOOR);
        assertLe(value, HIGH);
        assertGe(value, ochre.price(c, r, t + elapsed + 1));
        uint256 clamped = elapsed < ROUND ? elapsed : ROUND;
        assertEq(value, HIGH - (HIGH - FLOOR) * clamped / ROUND);
    }

    function testBuyWindowsAndResetForNextRound() public {
        vm.warp(START - 1);
        vm.expectRevert(Ochre.CaveNotOpen.selector);
        ochre.buy(1);
        vm.expectRevert(Ochre.CaveNotOpen.selector);
        ochre.priceNow(1);
        vm.warp(START);
        assertEq(ochre.priceNow(1), HIGH);
        vm.expectEmit(true, true, false, true, address(ochre));
        emit Bought(5, ALICE, HIGH);
        assertEq(_buy(1), 5);
        assertEq(ochre.ownerOf(5), ALICE);
        assertEq(coin.lastFrom(), ALICE);
        assertEq(coin.lastTo(), DEAD);
        assertEq(coin.lastAmount(), HIGH);
        assertEq(coin.balanceOf(address(ochre)), 0);
        assertEq(coin.balanceOf(DEAD), HIGH);
        vm.expectRevert(Ochre.RoundNotOpen.selector);
        ochre.priceNow(1);
        vm.expectRevert(Ochre.RoundNotOpen.selector);
        ochre.buy(1);
        vm.warp(START + ROUND - 1);
        vm.expectRevert(Ochre.RoundNotOpen.selector);
        ochre.buy(1);
        vm.warp(START + ROUND);
        assertEq(ochre.priceNow(1), HIGH);
        assertEq(_buy(1), 10);
        vm.warp(START + CAVE);
        vm.expectRevert(Ochre.CaveNotOpen.selector);
        ochre.buy(1);
        vm.expectRevert(Ochre.CaveNotOpen.selector);
        ochre.priceNow(1);
        assertEq(_buy(2), 110);
    }

    function testLaterRoundDoesNotRepriceEarlierUnsoldPiece() public {
        vm.warp(START + 10 * ROUND);
        assertEq(ochre.priceNow(1), FLOOR);
        assertEq(_buy(1), 5);
        assertEq(coin.lastAmount(), FLOOR);
        assertEq(ochre.priceNow(1), FLOOR);
    }

    function testAll400SalePiecesMintInExplicitOrder() public {
        uint256[7] memory ks = [uint256(1), 1, 2, 3, 4, 4, 4];
        for (uint256 c = 1; c <= 7; ++c) {
            vm.warp(START + c * CAVE - 1);
            for (uint256 r = 1; r <= 21; ++r) {
                uint256 k = c == 7 && r == 21 ? 5 : ks[c - 1];
                for (uint256 s = 5; s > 5 - k; --s) {
                    uint256 expected = (c - 1) * 105 + (r - 1) * 5 + s;
                    assertEq(ochre.priceNow(c), FLOOR);
                    assertEq(_buy(c), expected);
                    assertEq(ochre.ownerOf(expected), ALICE);
                }
            }
            vm.expectRevert(Ochre.SoldOut.selector);
            ochre.buy(c);
            vm.expectRevert(Ochre.SoldOut.selector);
            ochre.priceNow(c);
        }
        assertEq(ochre.balanceOf(ALICE), 400);
        assertEq(ochre.totalSupply(), 402);
        assertEq(coin.calls(), 400);
        assertEq(coin.balanceOf(DEAD), 400 * FLOOR);
        assertEq(coin.balanceOf(address(ochre)), 0);
    }

    function testNoApprovalAndInsufficientBalanceRollBack() public {
        vm.warp(START);
        vm.prank(ALICE);
        coin.approve(address(ochre), HIGH - 1);
        vm.expectRevert(MockCoin.InsufficientFunds.selector);
        _buy(1);
        vm.prank(address(0xD00D));
        coin.approve(address(ochre), HIGH);
        vm.prank(address(0xD00D));
        vm.expectRevert(MockCoin.InsufficientFunds.selector);
        ochre.buy(1);
        _assertEmptySale();
    }

    function testFalseRevertingAndMissingBoolPaymentRollBack() public {
        vm.warp(START);
        for (uint8 mode = 1; mode <= 3; ++mode) {
            coin.setFailure(mode);
            if (mode == 1) vm.expectRevert(Ochre.PaymentFailed.selector);
            else if (mode == 2) vm.expectRevert(MockCoin.ForcedFailure.selector);
            else vm.expectRevert();
            _buy(1);
            _assertEmptySale();
        }
        coin.setFailure(0);
        assertEq(_buy(1), 5);
    }

    function _assertEmptySale() private view {
        assertEq(ochre.saleTaken(1), 0);
        assertEq(ochre.totalSupply(), 2);
        assertEq(ochre.balanceOf(ALICE), 0);
        assertEq(coin.balanceOf(DEAD), 0);
        assertEq(coin.balanceOf(ALICE), 10 ether);
        assertEq(coin.calls(), 0);
    }

    function testReentrantCoinSeesConsumedSaleAndCannotDuplicateIt() public {
        vm.warp(START + 2 * CAVE);
        coin.setCallback(ochre, 3, false);
        assertEq(_buy(3), 215);
        assertEq(coin.callbackId(), 214);
        assertEq(coin.observedSupply(), 3);
        assertEq(ochre.ownerOf(215), ALICE);
        assertEq(ochre.ownerOf(214), address(coin));
        assertEq(ochre.saleTaken(3), 2);
        assertEq(coin.balanceOf(DEAD), HIGH * 2);
        assertEq(ochre.totalSupply(), 4);
    }

    function testSweepWindowBoundsAndOnlyUnsoldSalePieces() public {
        vm.warp(START + 2 * CAVE);
        assertEq(_buy(3), 215);
        vm.warp(START + 3 * CAVE - 1);
        vm.expectRevert(Ochre.TooEarly.selector);
        ochre.sweep(3, 1);
        vm.warp(START + 3 * CAVE);
        vm.expectRevert(Ochre.ZeroBatch.selector);
        ochre.sweep(3, 0);
        vm.expectEmit(true, false, false, true, address(ochre));
        emit Swept(214);
        vm.prank(BOB);
        assertEq(ochre.sweep(3, 1), 1);
        assertEq(ochre.ownerOf(214), ADMIN);
        assertEq(ochre.ownerOf(215), ALICE);
        assertEq(ochre.sweep(3, type(uint256).max), 40);
        assertEq(ochre.saleTaken(3), 42);
        vm.expectRevert(Ochre.SoldOut.selector);
        ochre.sweep(3, 1);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 211));
        ochre.ownerOf(211);
        assertEq(coin.calls(), 1);
        assertEq(ochre.seatsTaken(), 0);
    }

    function testSweepEveryCaveInBatches() public {
        vm.warp(START + 7 * CAVE);
        uint256 total = 0;
        for (uint256 c = 1; c <= 7; ++c) {
            uint256 count = ochre.saleCount(c);
            while (ochre.saleTaken(c) < count) total += ochre.sweep(c, 7);
            for (uint256 i = 0; i < count; ++i) {
                assertEq(ochre.ownerOf(ochre.saleId(c, i)), ADMIN);
            }
            vm.expectRevert(Ochre.SoldOut.selector);
            ochre.sweep(c, 7);
        }
        assertEq(total, 400);
        assertEq(ochre.totalSupply(), 402);
        assertEq(coin.calls(), 0);
    }

    function testClaimTimingProofAndDoubleClaim() public {
        bytes32[] memory proof = _proof(BOB);
        vm.warp(START - 1);
        vm.prank(ALICE);
        vm.expectRevert(Ochre.TooEarly.selector);
        ochre.claimSeat(proof);
        vm.warp(START);
        vm.prank(BOB);
        vm.expectRevert(Ochre.InvalidProof.selector);
        ochre.claimSeat(proof);
        vm.prank(ALICE);
        vm.expectRevert(Ochre.InvalidProof.selector);
        ochre.claimSeat(new bytes32[](0));
        vm.expectEmit(true, true, false, true, address(ochre));
        emit Claimed(1, ALICE);
        vm.prank(ALICE);
        assertEq(ochre.claimSeat(proof), 1);
        assertTrue(ochre.claimed(ALICE));
        vm.prank(ALICE);
        ochre.transferFrom(ALICE, BOB, 1);
        vm.prank(ALICE);
        vm.expectRevert(Ochre.AlreadyClaimed.selector);
        ochre.claimSeat(proof);
        vm.prank(BOB);
        assertEq(ochre.claimSeat(_proof(ALICE)), 2);
        assertEq(ochre.seatsTaken(), 2);
        assertEq(coin.calls(), 0);
    }

    function testAll315SeatsAndNo316thClaim() public {
        bytes32[] memory tree = new bytes32[](1024);
        for (uint256 i = 0; i < 512; ++i) {
            tree[512 + i] = _leaf(address(uint160(10_000 + i)));
        }
        for (uint256 i = 511; i > 0; --i) {
            tree[i] = _pair(tree[2 * i], tree[2 * i + 1]);
        }
        Config memory c = _config();
        c.root = tree[1];
        Ochre seats = _deploy(c);
        vm.warp(START);
        uint256 expectedId = 1;
        for (uint256 i = 0; i < 316; ++i) {
            bytes32[] memory proof = new bytes32[](9);
            uint256 pos = 512 + i;
            for (uint256 depth = 0; depth < 9; ++depth) {
                proof[depth] = tree[pos ^ 1];
                pos /= 2;
            }
            address wallet = address(uint160(10_000 + i));
            if (i == 315) {
                vm.prank(wallet);
                vm.expectRevert(Ochre.SoldOut.selector);
                seats.claimSeat(proof);
                assertFalse(seats.claimed(wallet));
            } else {
                while (_isSale(expectedId)) ++expectedId;
                vm.prank(wallet);
                assertEq(seats.claimSeat(proof), expectedId++);
            }
        }
        assertEq(seats.totalSupply(), 317);
        assertEq(seats.seatsTaken(), 315);
        assertEq(coin.calls(), 0);
    }

    function _isSale(uint256 id) private pure returns (bool) {
        uint256 c = (id - 1) / 105 + 1;
        uint256 r = ((id - 1) % 105) / 5 + 1;
        uint256 slot = (id - 1) % 5 + 1;
        uint256[7] memory slots = [uint256(1), 1, 2, 3, 4, 4, 4];
        uint256 k = c == 7 && r == 21 ? 5 : slots[c - 1];
        return slot > 5 - k;
    }

    function testReserveOnlyAdminAndCappedAtTwenty() public {
        vm.expectRevert(Ochre.Unauthorized.selector);
        ochre.mintReserve(ALICE);
        vm.prank(ADMIN);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InvalidReceiver.selector, address(0)));
        ochre.mintReserve(address(0));
        assertEq(ochre.reserveTaken(), 0);
        for (uint256 i = 0; i < 20; ++i) {
            uint256 id = 631 + i * 5;
            vm.expectEmit(true, true, false, true, address(ochre));
            emit Reserved(id, BOB);
            vm.prank(ADMIN);
            assertEq(ochre.mintReserve(BOB), id);
            assertEq(ochre.ownerOf(id), BOB);
        }
        vm.prank(ADMIN);
        vm.expectRevert(Ochre.SoldOut.selector);
        ochre.mintReserve(BOB);
        assertEq(ochre.reserveTaken(), 20);
        assertEq(coin.calls(), 0);
    }

    function testReleaseIsExplicitAndBoundaryInclusive() public {
        vm.warp(START + 8 * CAVE - 1);
        vm.expectRevert(Ochre.TooEarly.selector);
        ochre.releaseUnclaimed();
        vm.expectRevert(Ochre.NotReleased.selector);
        ochre.buyLeftover();
        vm.warp(START + 8 * CAVE);
        // The deadline enables release; claims remain possible until someone calls it.
        vm.prank(ALICE);
        assertEq(ochre.claimSeat(_proof(BOB)), 1);
        vm.expectEmit(false, false, false, true, address(ochre));
        emit UnclaimedReleased();
        vm.prank(BOB);
        ochre.releaseUnclaimed();
        vm.expectRevert(Ochre.SeatsReleased.selector);
        ochre.releaseUnclaimed();
        vm.prank(BOB);
        vm.expectRevert(Ochre.SeatsReleased.selector);
        ochre.claimSeat(_proof(ALICE));
        vm.warp(START + 1000 * CAVE);
        vm.expectEmit(true, true, false, true, address(ochre));
        emit Bought(2, ALICE, FLOOR);
        vm.prank(ALICE);
        assertEq(ochre.buyLeftover(), 2);
        assertEq(coin.lastFrom(), ALICE);
        assertEq(coin.lastTo(), DEAD);
        assertEq(coin.lastAmount(), FLOOR);
    }

    function testLeftoverPaymentFailureRollsBackAndReentrancyConsumesNextSeat() public {
        vm.warp(START + 8 * CAVE);
        ochre.releaseUnclaimed();
        for (uint8 mode = 1; mode <= 3; ++mode) {
            coin.setFailure(mode);
            vm.prank(ALICE);
            vm.expectRevert();
            ochre.buyLeftover();
            assertEq(ochre.seatsTaken(), 0);
            assertEq(ochre.totalSupply(), 2);
            assertEq(coin.balanceOf(DEAD), 0);
        }
        coin.setFailure(0);
        coin.setCallback(ochre, 0, true);
        vm.prank(ALICE);
        assertEq(ochre.buyLeftover(), 1);
        assertEq(coin.callbackId(), 2);
        assertEq(coin.observedSupply(), 3);
        assertEq(ochre.ownerOf(1), ALICE);
        assertEq(ochre.ownerOf(2), address(coin));
        assertEq(ochre.seatsTaken(), 2);
        assertEq(coin.balanceOf(DEAD), 2 * FLOOR);
    }

    function testCompleteMixedLifecycleMintsExactly737() public {
        vm.warp(START);
        vm.prank(ALICE);
        ochre.claimSeat(_proof(BOB));
        for (uint256 c = 1; c <= 7; ++c) {
            vm.warp(START + (c - 1) * CAVE);
            _buy(c);
        }
        vm.warp(START + 8 * CAVE);
        for (uint256 c = 1; c <= 7; ++c) {
            ochre.sweep(c, 100);
        }
        for (uint256 i = 0; i < 20; ++i) {
            vm.prank(ADMIN);
            ochre.mintReserve(BOB);
        }
        ochre.releaseUnclaimed();
        for (uint256 i = 1; i < 315; ++i) {
            vm.prank(ALICE);
            ochre.buyLeftover();
        }
        assertEq(ochre.totalSupply(), 737);
        assertEq(ochre.balanceOf(ALICE), 322);
        assertEq(ochre.balanceOf(BOB), 20);
        assertEq(ochre.balanceOf(ADMIN), 394);
        assertEq(ochre.balanceOf(ADAM), 1);
        for (uint256 id = 0; id < 737; ++id) {
            assertTrue(ochre.ownerOf(id) != address(0));
        }
        assertEq(coin.balanceOf(DEAD), HIGH * 7 + FLOOR * 314);
        assertEq(coin.balanceOf(address(ochre)), 0);
        vm.expectRevert(Ochre.SoldOut.selector);
        ochre.buyLeftover();
        vm.prank(ADMIN);
        vm.expectRevert(Ochre.SoldOut.selector);
        ochre.mintReserve(ALICE);
        for (uint256 c = 1; c <= 7; ++c) {
            vm.expectRevert(Ochre.SoldOut.selector);
            ochre.sweep(c, 1);
            vm.expectRevert(Ochre.CaveNotOpen.selector);
            ochre.buy(c);
        }
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 737));
        ochre.ownerOf(737);
    }

    function testTokenURIsAndFreezeScopeIncludingEndpoints() public {
        assertEq(ochre.tokenURI(0), "https://zto-cave-test5.sites.imd.fun/zero.json");
        assertEq(ochre.tokenURI(736), "https://zto-cave-test3.sites.imd.fun/one.json");
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 1));
        ochre.tokenURI(1);
        vm.warp(START);
        vm.prank(ALICE);
        ochre.claimSeat(_proof(BOB));
        _buy(1);
        assertEq(ochre.tokenURI(1), "https://zto-cave-test5.sites.imd.fun/line-1/01.json");
        assertEq(ochre.tokenURI(5), "https://zto-cave-test5.sites.imd.fun/gathering/01.json");
        vm.warp(START + 7 * CAVE);
        ochre.sweep(5, 100);
        ochre.sweep(7, 100);
        assertEq(ochre.tokenURI(469), "https://zto-cave-test5.sites.imd.fun/line-4/10.json");
        assertEq(ochre.tokenURI(473), "https://zto-cave-test5.sites.imd.fun/line-3/11.json");
        assertEq(ochre.tokenURI(477), "https://zto-cave-test5.sites.imd.fun/line-2/12.json");
        assertEq(ochre.tokenURI(731), "https://zto-cave-test3.sites.imd.fun/line-1/21.json");
        assertEq(ochre.tokenURI(735), "https://zto-cave-test3.sites.imd.fun/gathering/21.json");
        vm.expectEmit(true, false, false, true, address(ochre));
        emit Frozen(1, "ipfs://cid-one/");
        vm.prank(ADMIN);
        ochre.freeze(1, "ipfs://cid-one/");
        assertEq(ochre.tokenURI(0), "ipfs://cid-one/zero.json");
        assertEq(ochre.tokenURI(1), "ipfs://cid-one/line-1/01.json");
        assertEq(ochre.tokenURI(5), "ipfs://cid-one/gathering/01.json");
        assertEq(ochre.tokenURI(469), "https://zto-cave-test5.sites.imd.fun/line-4/10.json");
        vm.prank(ADMIN);
        ochre.freeze(7, "ipfs://cid-seven/");
        assertEq(ochre.tokenURI(736), "ipfs://cid-seven/one.json");
        assertEq(ochre.tokenURI(731), "ipfs://cid-seven/line-1/21.json");
        vm.prank(ADMIN);
        vm.expectRevert(Ochre.AlreadyFrozen.selector);
        ochre.freeze(1, "ipfs://replacement/");
    }

    function testFreezeAuthorizationValidationAndBeforeMint() public {
        vm.expectRevert(Ochre.Unauthorized.selector);
        ochre.freeze(2, "ipfs://cid/");
        vm.startPrank(ADMIN);
        vm.expectRevert(Ochre.InvalidCave.selector);
        ochre.freeze(8, "ipfs://cid/");
        vm.expectRevert(Ochre.InvalidBase.selector);
        ochre.freeze(2, "");
        vm.expectRevert(Ochre.InvalidBase.selector);
        ochre.freeze(2, "ipfs://cid");
        ochre.freeze(2, "ipfs://two/");
        vm.stopPrank();
        vm.warp(START + CAVE);
        _buy(2);
        assertEq(ochre.tokenURI(110), "ipfs://two/gathering/01.json");
    }

    function testTransfersApprovalsAndSafeReceiver() public {
        vm.warp(START);
        _buy(1);
        vm.prank(BOB);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InsufficientApproval.selector, BOB, 5));
        ochre.transferFrom(ALICE, BOB, 5);
        vm.prank(ALICE);
        ochre.approve(BOB, 5);
        assertEq(ochre.getApproved(5), BOB);
        vm.prank(BOB);
        ochre.transferFrom(ALICE, BOB, 5);
        assertEq(ochre.getApproved(5), address(0));
        assertEq(ochre.balanceOf(ALICE), 0);
        assertEq(ochre.balanceOf(BOB), 1);
        vm.prank(BOB);
        ochre.setApprovalForAll(ALICE, true);
        assertTrue(ochre.isApprovedForAll(BOB, ALICE));
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InvalidReceiver.selector, address(coin)));
        ochre.safeTransferFrom(BOB, address(coin), 5);
        assertEq(ochre.ownerOf(5), BOB);
        Receiver receiver = new Receiver();
        vm.prank(ALICE);
        ochre.safeTransferFrom(BOB, address(receiver), 5, hex"1234");
        assertEq(ochre.ownerOf(5), address(receiver));
        assertEq(receiver.operator(), ALICE);
        assertEq(receiver.from(), BOB);
        assertEq(receiver.id(), 5);
        assertEq(receiver.data(), hex"1234");
        assertEq(ochre.totalSupply(), 3);
    }

    function testRejectsEther() public {
        vm.deal(ALICE, 1 ether);
        vm.prank(ALICE);
        (bool ok,) = address(ochre).call{value: 1}("");
        assertFalse(ok);
        vm.prank(ALICE);
        (ok,) = address(ochre).call{value: 1}(abi.encodeCall(Ochre.buy, (1)));
        assertFalse(ok);
        assertEq(address(ochre).balance, 0);
    }
}

contract Receiver is IERC721Receiver {
    address public operator;
    address public from;
    uint256 public id;
    bytes public data;

    function onERC721Received(address operator_, address from_, uint256 id_, bytes calldata data_)
        external
        returns (bytes4)
    {
        operator = operator_;
        from = from_;
        id = id_;
        data = data_;
        return IERC721Receiver.onERC721Received.selector;
    }
}
