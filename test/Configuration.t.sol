// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {OchreFixture, Ochre} from "./helpers/Fixture.sol";

contract ConfigurationTest is OchreFixture {
    function testRejectsZeroAddressesAndRoot() public {
        Config memory c = _config();
        c.coin = address(0);
        _invalid(c);
        c = _config();
        c.admin = address(0);
        _invalid(c);
        c = _config();
        c.adam = address(0);
        _invalid(c);
        c = _config();
        c.root = bytes32(0);
        _invalid(c);
    }

    function testRejectsZeroDurationsAndRoundsThatDoNotFit() public {
        Config memory c = _config();
        c.round = 0;
        _invalid(c);
        c = _config();
        c.cave = 0;
        _invalid(c);
        c = _config();
        c.cave = 21 * ROUND - 1;
        _invalid(c);
        c = _config();
        c.round = type(uint256).max;
        _invalid(c);
    }

    function testRejectsInvalidPricesAndOverflowingConfiguration() public {
        Config memory c = _config();
        c.floor = 0;
        _invalid(c);
        c = _config();
        c.high = FLOOR - 1;
        _invalid(c);
        c = _config();
        c.high = type(uint256).max;
        _invalid(c);
        c = _config();
        c.start = type(uint256).max;
        _invalid(c);
        c = _config();
        c.cave = type(uint256).max;
        _invalid(c);
    }

    function testLabelsRejectEmptyNonAsciiAndNonzeroAfterPadding() public {
        Config memory c = _config();
        c.label = bytes32(0);
        vm.expectRevert(Ochre.InvalidLabel.selector);
        _deploy(c);
        c.label = bytes32(hex"61620063");
        vm.expectRevert(Ochre.InvalidLabel.selector);
        _deploy(c);
        c.label = bytes32(hex"ff");
        vm.expectRevert(Ochre.InvalidLabel.selector);
        _deploy(c);
    }

    function testLabelsSupportAll32BytesWithoutTerminator() public {
        Config memory c = _config();
        c.label = bytes32("abcdefghijklmnopqrstuvwxyz123456");
        Ochre full = _deploy(c);
        assertEq(full.labels(1), c.label);
        assertEq(full.tokenURI(0), "https://abcdefghijklmnopqrstuvwxyz123456.sites.imd.fun/zero.json");
    }

    function testDurationsAndPricesAreArgumentsWithExactFitAndRounding() public {
        Config memory c = _config();
        c.cave = 63;
        c.round = 3;
        c.high = 11;
        c.floor = 1;
        Ochre custom = _deploy(c);
        assertEq(custom.caveClose(1), START + 63);
        assertEq(custom.roundOpen(1, 21), START + 60);
        assertEq(custom.price(1, 1, START), 11);
        assertEq(custom.price(1, 1, START + 1), 8);
        assertEq(custom.price(1, 1, START + 2), 5);
        assertEq(custom.price(1, 1, START + 3), 1);
        c.high = c.floor;
        Ochre flat = _deploy(c);
        assertEq(flat.price(7, 21, 0), 1);
        assertEq(flat.price(7, 21, type(uint256).max), 1);
        c.cave = 86400;
        c.round = 3600;
        Ochre daily = _deploy(c);
        assertEq(daily.caveClose(7), START + 7 days);
        assertEq(daily.roundOpen(1, 21), START + 20 hours);
    }

    function testLatestValidScheduleDoesNotOverflow() public {
        Config memory c = _config();
        c.start = type(uint256).max - 8 * CAVE;
        Ochre latest = _deploy(c);
        assertEq(latest.caveClose(7), type(uint256).max - CAVE);
        assertEq(latest.price(7, 21, type(uint256).max), FLOOR);
        vm.warp(type(uint256).max);
        latest.releaseUnclaimed();
        assertTrue(latest.unclaimedReleased());
    }

    function _invalid(Config memory c) private {
        vm.expectRevert(Ochre.InvalidConfig.selector);
        _deploy(c);
    }
}
