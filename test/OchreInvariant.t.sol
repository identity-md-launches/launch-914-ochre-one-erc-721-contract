// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {OchreFixture} from "./helpers/Fixture.sol";
import {OchreHandler} from "./helpers/OchreHandler.sol";

contract OchreInvariantTest is OchreFixture {
    OchreHandler internal handler;

    function setUp() public override {
        super.setUp();
        _fund(ADMIN, ochre);
        _fund(ADAM, ochre);
        vm.warp(START - 1);
        handler = new OchreHandler(ochre, coin, [ALICE, BOB, ADMIN, ADAM]);
        bytes4[] memory selectors = new bytes4[](9);
        selectors[0] = handler.advanceTime.selector;
        selectors[1] = handler.buy.selector;
        selectors[2] = handler.sweep.selector;
        selectors[3] = handler.claim.selector;
        selectors[4] = handler.reserve.selector;
        selectors[5] = handler.release.selector;
        selectors[6] = handler.buyLeftover.selector;
        selectors[7] = handler.transfer.selector;
        selectors[8] = handler.freeze.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector(address(handler), selectors));
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 96
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_allocationsOwnershipAndPaymentsMatchIndependentLedger() public view {
        handler.assertAccounting();
    }

    function afterInvariant() public {
        // Detect phantom tokens before filling gaps, then prove completion is still possible.
        handler.assertAllTokens();
        handler.finish();
    }

    function testHandlerExercisesSuccessFailureAndTerminalStates() public {
        handler.buy(1, 0, 0);
        handler.claim(0, false);
        handler.release(0);
        handler.buyLeftover(0, 0);
        handler.reserve(0, false, false);
        handler.reserve(0, true, true);
        handler.advanceTime(1);
        handler.claim(0, true);
        handler.claim(0, false);
        handler.claim(0, false);
        handler.buy(1, 0, 1);
        handler.buy(1, 0, 2);
        handler.buy(1, 0, 3);
        handler.buy(1, 0, 0);
        handler.buy(1, 1, 0);
        handler.transfer(2, 1, 2);
        handler.transfer(2, 1, 1);
        handler.transfer(2, 0, 0);
        handler.freeze(1, false, true);
        handler.freeze(1, true, false);
        handler.freeze(1, true, true);
        handler.freeze(1, true, true);
        handler.reserve(1, true, false);
        handler.sweep(1, 1, 0);
        handler.advanceTime(CAVE);
        handler.sweep(1, 0, 0);
        handler.sweep(1, 1, 1);
        handler.assertAccounting();
        for (uint256 i; i < 7; ++i) {
            handler.advanceTime(CAVE);
        }
        handler.release(1);
        handler.buyLeftover(1, 1);
        handler.buyLeftover(1, 2);
        handler.buyLeftover(1, 3);
        handler.buyLeftover(1, 0);
        handler.assertAccounting();
        assertEq(handler.accepted(), 9);
        assertEq(handler.rejected(), 21);
        handler.finish();
    }
}
