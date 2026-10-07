// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

interface IOchreCoin {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

/// @notice The 737 pieces of Ochre. Payments go directly from buyer to dead.
contract Ochre is ERC721 {
    error InvalidConfig();
    error InvalidLabel();
    error InvalidPiece();
    error InvalidCave();
    error InvalidRound();
    error SoldOut();
    error CaveNotOpen();
    error RoundNotOpen();
    error TooEarly();
    error Unauthorized();
    error InvalidProof();
    error AlreadyClaimed();
    error SeatsReleased();
    error NotReleased();
    error ZeroBatch();
    error PaymentFailed();
    error AlreadyFrozen();
    error InvalidBase();

    event Bought(uint256 indexed id, address indexed buyer, uint256 price);
    event Swept(uint256 indexed id);
    event Claimed(uint256 indexed id, address indexed wallet);
    event Reserved(uint256 indexed id, address indexed wallet);
    event UnclaimedReleased();
    event Frozen(uint256 indexed cave, string base);

    address public constant dead = 0x000000000000000000000000000000000000dEaD;
    uint8 public constant coinDecimals = 18;
    uint256 public constant MAX_SUPPLY = 737;
    // Written only in the constructor. Storage avoids repeating immutable words in the runtime bytecode.
    IOchreCoin public coin;
    address public admin;
    address public adam;
    bytes32 public seatRoot;
    uint256 public startTime;
    uint256 public caveLength;
    uint256 public roundLength;
    uint256 private initialPrice;
    uint256 public floorPrice;

    mapping(uint256 cave => bytes32) public labels;
    mapping(uint256 cave => uint256) public saleTaken;
    mapping(address wallet => bool) public claimed;
    mapping(uint256 cave => bool) public frozen;
    mapping(uint256 cave => string) private frozenBase;
    uint256 public seatsTaken;
    uint256 public reserveTaken;
    bool public unclaimedReleased;

    /// @dev Sixteen static arguments; dead and decimals are constants. No external calls,
    ///      including no receiver hooks on the two initial mints and no coin metadata reads.
    constructor(
        address coin_,
        address admin_,
        address adam_,
        bytes32 seatRoot_,
        uint256 startTime_,
        uint256 caveLength_,
        uint256 roundLength_,
        uint256 startPrice_,
        uint256 floorPrice_,
        bytes32 label1,
        bytes32 label2,
        bytes32 label3,
        bytes32 label4,
        bytes32 label5,
        bytes32 label6,
        bytes32 label7
    ) ERC721("Ochre", "OCHRE") {
        if (
            coin_ == address(0) || admin_ == address(0) || adam_ == address(0) || seatRoot_ == bytes32(0)
                || roundLength_ == 0 || roundLength_ > caveLength_ / 21 || floorPrice_ == 0
                || startPrice_ < floorPrice_ || caveLength_ > (type(uint256).max - startTime_) / 8
        ) revert InvalidConfig();
        // Keep the linear-price numerator within uint256 for every permitted timestamp.
        if (startPrice_ - floorPrice_ > type(uint256).max / roundLength_) revert InvalidConfig();
        coin = IOchreCoin(coin_);
        admin = admin_;
        adam = adam_;
        seatRoot = seatRoot_;
        startTime = startTime_;
        caveLength = caveLength_;
        roundLength = roundLength_;
        initialPrice = startPrice_;
        floorPrice = floorPrice_;
        _setLabel(1, label1);
        _setLabel(2, label2);
        _setLabel(3, label3);
        _setLabel(4, label4);
        _setLabel(5, label5);
        _setLabel(6, label6);
        _setLabel(7, label7);
        _mint(adam_, 0);
        _mint(admin_, 736);
    }

    function totalSupply() external view returns (uint256 supply) {
        // Bounds follow from validated coordinates, ordinals and constructor parameters.
        unchecked {
            supply = 2 + seatsTaken + reserveTaken;
            for (uint256 c = 1; c <= 7; ++c) {
                supply += saleTaken[c];
            }
        }
    }

    /// @notice Coordinates for ordinary pieces only; Zero and One are endpoints.
    function piece(uint256 id) public pure returns (uint256 cave, uint256 round, uint256 slot) {
        // Bounds follow from validated coordinates, ordinals and constructor parameters.
        unchecked {
            if (id == 0 || id >= 736) revert InvalidPiece();
            uint256 offset = id - 1;
            return (offset / 105 + 1, (offset % 105) / 5 + 1, offset % 5 + 1);
        }
    }

    function caveOpen(uint256 c) public view returns (uint256) {
        // Bounds follow from validated coordinates, ordinals and constructor parameters.
        unchecked {
            _checkCave(c);
            return startTime + (c - 1) * caveLength;
        }
    }

    function caveClose(uint256 c) public view returns (uint256) {
        // Bounds follow from validated coordinates, ordinals and constructor parameters.
        unchecked {
            return caveOpen(c) + caveLength;
        }
    }

    function roundOpen(uint256 c, uint256 r) public view returns (uint256) {
        // Bounds follow from validated coordinates, ordinals and constructor parameters.
        unchecked {
            _checkRound(r);
            return caveOpen(c) + (r - 1) * roundLength;
        }
    }

    function startPrice(uint256 c) external view returns (uint256) {
        _checkCave(c);
        return initialPrice;
    }

    /// @notice Mathematical price curve, clamped at both ends, even outside the sale window.
    /// @dev buy and priceNow enforce the cave and round windows separately.
    function price(uint256 c, uint256 r, uint256 t) public view returns (uint256) {
        // Bounds follow from validated coordinates, ordinals and constructor parameters.
        unchecked {
            uint256 opening = roundOpen(c, r);
            if (t <= opening) return initialPrice;
            uint256 elapsed = t - opening;
            if (elapsed >= roundLength) return floorPrice;
            return initialPrice - (initialPrice - floorPrice) * elapsed / roundLength;
        }
    }

    function saleSlots(uint256 c, uint256 r) public pure returns (uint256) {
        // Bounds follow from validated coordinates, ordinals and constructor parameters.
        unchecked {
            _checkCave(c);
            _checkRound(r);
            if (c == 7 && r == 21) return 5;
            return _baseSaleSlots(c);
        }
    }

    function saleCount(uint256 c) public pure returns (uint256) {
        // Bounds follow from validated coordinates, ordinals and constructor parameters.
        unchecked {
            _checkCave(c);
            return _baseSaleSlots(c) * 21 + (c == 7 ? 1 : 0);
        }
    }

    /// @notice Zero-based sale ordinal, rounds ascending, slots 5,4,3,2,1.
    function saleId(uint256 c, uint256 index) public pure returns (uint256) {
        // Bounds follow from validated coordinates, ordinals and constructor parameters.
        unchecked {
            if (index >= saleCount(c)) revert SoldOut();
            if (c == 7 && index == 84) return 731;
            uint256 k = _baseSaleSlots(c);
            uint256 offset = index % k;
            // Remove the remainder, then scale before division: an exact whole-round offset.
            return (c - 1) * 105 + (index - offset) * 5 / k + 5 - offset;
        }
    }

    /// @notice Zero-based seat ordinal, in increasing numeric ID order, caves 1..6 only.
    function seatId(uint256 index) public pure returns (uint256) {
        // Bounds follow from validated coordinates, ordinals and constructor parameters.
        unchecked {
            if (index >= 315) revert SoldOut();
            for (uint256 c = 1; c <= 6; ++c) {
                uint256 freeSlots = 5 - _baseSaleSlots(c);
                uint256 count = freeSlots * 21;
                if (index < count) {
                    uint256 offset = index % freeSlots;
                    return (c - 1) * 105 + (index - offset) * 5 / freeSlots + offset + 1;
                }
                index -= count;
            }
            revert SoldOut();
        }
    }

    function reserveId(uint256 index) public pure returns (uint256) {
        // Bounds follow from validated coordinates, ordinals and constructor parameters.
        unchecked {
            if (index >= 20) revert SoldOut();
            return 631 + index * 5;
        }
    }

    function priceNow(uint256 c) public view returns (uint256) {
        (, uint256 amount) = _nextSale(c);
        return amount;
    }

    function buy(uint256 c) external returns (uint256 id) {
        uint256 amount;
        (id, amount) = _nextSale(c);
        unchecked {
            ++saleTaken[c];
        }
        _mint(msg.sender, id);
        emit Bought(id, msg.sender, amount);
        // All effects and events precede the only external call. A failed payment rolls back all of them.
        if (!coin.transferFrom(msg.sender, dead, amount)) revert PaymentFailed();
    }

    function sweep(uint256 c, uint256 max) external returns (uint256 minted) {
        // Arithmetic is bounded by the fixed supply, valid coordinates and constructor limits.
        unchecked {
            if (block.timestamp < caveClose(c)) revert TooEarly();
            if (max == 0) revert ZeroBatch();
            uint256 taken = saleTaken[c];
            uint256 remaining = saleCount(c) - taken;
            if (remaining == 0) revert SoldOut();
            minted = max < remaining ? max : remaining;
            saleTaken[c] = taken + minted;
            for (uint256 i = 0; i < minted; ++i) {
                uint256 id = saleId(c, taken + i);
                _mint(admin, id);
                emit Swept(id);
            }
        }
    }

    function claimSeat(bytes32[] calldata proof) external returns (uint256 id) {
        if (block.timestamp < startTime) revert TooEarly();
        if (unclaimedReleased) revert SeatsReleased();
        if (claimed[msg.sender]) revert AlreadyClaimed();
        if (!MerkleProof.verifyCalldata(proof, seatRoot, keccak256(abi.encodePacked(msg.sender)))) {
            revert InvalidProof();
        }
        id = seatId(seatsTaken);
        claimed[msg.sender] = true;
        unchecked {
            ++seatsTaken;
        }
        _mint(msg.sender, id);
        emit Claimed(id, msg.sender);
    }

    function mintReserve(address to) external returns (uint256 id) {
        _checkAdmin();
        id = reserveId(reserveTaken);
        unchecked {
            ++reserveTaken;
        }
        _mint(to, id);
        emit Reserved(id, to);
    }

    function releaseUnclaimed() external {
        // Arithmetic is bounded by the fixed supply, valid coordinates and constructor limits.
        unchecked {
            if (block.timestamp < startTime + 8 * caveLength) revert TooEarly();
            if (unclaimedReleased) revert SeatsReleased();
            unclaimedReleased = true;
            emit UnclaimedReleased();
        }
    }

    function buyLeftover() external returns (uint256 id) {
        if (!unclaimedReleased) revert NotReleased();
        id = seatId(seatsTaken);
        unchecked {
            ++seatsTaken;
        }
        _mint(msg.sender, id);
        emit Bought(id, msg.sender, floorPrice);
        if (!coin.transferFrom(msg.sender, dead, floorPrice)) revert PaymentFailed();
    }

    function freeze(uint256 c, string calldata base) external {
        _checkAdmin();
        _checkCave(c);
        if (frozen[c]) revert AlreadyFrozen();
        bytes memory value = bytes(base);
        if (value.length == 0 || value[value.length - 1] != bytes1("/")) revert InvalidBase();
        frozen[c] = true;
        frozenBase[c] = base;
        emit Frozen(c, base);
    }

    function tokenURI(uint256 id) public view override returns (string memory) {
        // Arithmetic is bounded by the fixed supply, valid coordinates and constructor limits.
        unchecked {
            _requireOwned(id);
            if (id == 0) return string.concat(_caveBase(1), "zero.json");
            if (id == 736) return string.concat(_caveBase(7), "one.json");
            (uint256 c, uint256 r, uint256 slot) = piece(id);
            bytes memory suffix = slot == 5 ? bytes("gathering/00.json") : bytes("line-0/00.json");
            uint256 digitOffset = slot == 5 ? 10 : 7;
            if (slot != 5) suffix[5] = bytes1(uint8(48 + slot));
            suffix[digitOffset] = bytes1(uint8(48 + r / 10));
            suffix[digitOffset + 1] = bytes1(uint8(48 + r % 10));
            return string.concat(_caveBase(c), string(suffix));
        }
    }

    function _nextSale(uint256 c) private view returns (uint256 id, uint256 amount) {
        // Bounds follow from validated coordinates, ordinals and constructor parameters.
        unchecked {
            uint256 opening = caveOpen(c);
            if (block.timestamp < opening || block.timestamp >= opening + caveLength) revert CaveNotOpen();
            id = saleId(c, saleTaken[c]);
            (, uint256 r,) = piece(id);
            if (block.timestamp < roundOpen(c, r)) revert RoundNotOpen();
            amount = price(c, r, block.timestamp);
        }
    }

    function _caveBase(uint256 c) private view returns (string memory) {
        if (frozen[c]) return frozenBase[c];
        bytes memory value = abi.encode(labels[c]);
        uint256 length = 0;
        while (length < 32 && value[length] != 0) ++length;
        // Trim the owned, 32-byte memory buffer in place; the data and allocation stay unchanged.
        assembly ("memory-safe") {
            mstore(value, length)
        }
        return string.concat("https://", string(value), ".sites.imd.fun/");
    }

    function _setLabel(uint256 c, bytes32 label) private {
        if (label[0] == 0) revert InvalidLabel();
        bool padding = false;
        for (uint256 i = 0; i < 32; ++i) {
            uint8 ch = uint8(label[i]);
            if (ch == 0) padding = true;
            else if (padding || ch > 127) revert InvalidLabel();
        }
        labels[c] = label;
    }

    function _checkAdmin() private view {
        if (msg.sender != admin) revert Unauthorized();
    }

    /// @dev Only called with c in 1..7. Low-to-high nibbles encode 1,1,2,3,4,4,4.
    function _baseSaleSlots(uint256 c) private pure returns (uint256) {
        unchecked {
            return (0x4443211 >> ((c - 1) * 4)) & 15;
        }
    }

    function _checkCave(uint256 c) private pure {
        if (c == 0 || c > 7) revert InvalidCave();
    }

    function _checkRound(uint256 r) private pure {
        if (r == 0 || r > 21) revert InvalidRound();
    }
}
