// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Ochre} from "../../src/Ochre.sol";

contract MockCoin {
    error InsufficientFunds();
    error ForcedFailure();

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    uint256 public calls;
    address public lastFrom;
    address public lastTo;
    uint256 public lastAmount;
    uint8 public failure;
    Ochre public target;
    uint256 public callbackCave;
    bool public callbackLeftover;
    uint256 public callbackId;
    uint256 public observedSupply;
    bool private entered;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function setFailure(uint8 value) external {
        failure = value;
    }

    function setCallback(Ochre target_, uint256 cave, bool leftover) external {
        target = target_;
        callbackCave = cave;
        callbackLeftover = leftover;
        balanceOf[address(this)] = 1 ether;
        allowance[address(this)][address(target_)] = 1 ether;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        if (allowance[from][msg.sender] < amount || balanceOf[from] < amount) revert InsufficientFunds();
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        ++calls;
        lastFrom = from;
        lastTo = to;
        lastAmount = amount;
        if (address(target) != address(0) && !entered) {
            entered = true;
            observedSupply = target.totalSupply();
            callbackId = callbackLeftover ? target.buyLeftover() : target.buy(callbackCave);
            entered = false;
        }
        if (failure == 1) return false;
        if (failure == 2) revert ForcedFailure();
        if (failure == 3) {
            assembly ("memory-safe") {
                return(0, 0)
            }
        }
        return true;
    }
}

abstract contract OchreFixture is Test {
    uint256 internal constant START = 1791384259;
    uint256 internal constant CAVE = 3600;
    uint256 internal constant ROUND = 150;
    uint256 internal constant HIGH = 4_000_000_000_000_000;
    uint256 internal constant FLOOR = 400_000_000_000_000;
    address internal constant ADMIN = 0x7B8C742F2e1eEB3fB2C10d72967Fa6d4a22f0479;
    address internal constant ADAM = address(0xADA);
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant DEAD = address(0xdead);
    address internal constant WETH = 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14;

    struct Config {
        address coin;
        address admin;
        address adam;
        bytes32 root;
        uint256 start;
        uint256 cave;
        uint256 round;
        uint256 high;
        uint256 floor;
        bytes32 label;
    }

    MockCoin internal coin;
    Ochre internal ochre;

    event Bought(uint256 indexed id, address indexed buyer, uint256 price);
    event Swept(uint256 indexed id);
    event Claimed(uint256 indexed id, address indexed wallet);
    event Reserved(uint256 indexed id, address indexed wallet);
    event UnclaimedReleased();
    event Frozen(uint256 indexed cave, string base);

    function setUp() public virtual {
        coin = new MockCoin();
        ochre = _deploy(_config());
        _fund(ALICE, ochre);
        _fund(BOB, ochre);
    }

    function _config() internal view returns (Config memory) {
        return Config({
            coin: address(coin),
            admin: ADMIN,
            adam: ADAM,
            root: _pair(_leaf(ALICE), _leaf(BOB)),
            start: START,
            cave: CAVE,
            round: ROUND,
            high: HIGH,
            floor: FLOOR,
            label: bytes32("zto-cave-test5")
        });
    }

    function _deploy(Config memory c) internal returns (Ochre) {
        return new Ochre(
            c.coin,
            c.admin,
            c.adam,
            c.root,
            c.start,
            c.cave,
            c.round,
            c.high,
            c.floor,
            c.label,
            bytes32("zto-cave-test4"),
            bytes32("zto-cave-test3"),
            bytes32("zto-cave-test2"),
            bytes32("zto-cave-test5"),
            bytes32("zto-cave-test4"),
            bytes32("zto-cave-test3")
        );
    }

    function _fund(address who, Ochre collection) internal {
        coin.mint(who, 10 ether);
        vm.prank(who);
        coin.approve(address(collection), 10 ether);
    }

    function _leaf(address who) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(who));
    }

    function _pair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? keccak256(abi.encode(a, b)) : keccak256(abi.encode(b, a));
    }

    function _proof(address sibling) internal pure returns (bytes32[] memory proof) {
        proof = new bytes32[](1);
        proof[0] = _leaf(sibling);
    }

    function _buy(uint256 c) internal returns (uint256) {
        vm.prank(ALICE);
        return ochre.buy(c);
    }
}
