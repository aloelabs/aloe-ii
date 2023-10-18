// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {SSTORE2} from "solady/utils/SSTORE2.sol";

import {BytesLib} from "./BytesLib.sol";
import {SafeSSTORE2} from "./SafeSSTORE2.sol";

/**
 * @title ERC721Z
 * @author Aloe Labs, Inc.
 * Credits: beskay0x, chiru-labs, solmate, transmissions11, nftchance, squeebo_nft and others
 * @notice ERC-721 implementation optimized for minting multiple tokens at once, similar to
 * [ERC721A](https://github.com/chiru-labs/ERC721A) and [ERC721B](https://github.com/beskay/ERC721B). This version allows
 * tokens to have "attributes" (up to 224 bits of data stored in the `tokenId`) and enables gas-efficient queries of all
 * tokens held by a given `owner`.
 */
abstract contract ERC721Z {
    using SafeSSTORE2 for address;
    using SafeSSTORE2 for bytes;
    using BytesLib for bytes;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    event Approval(address indexed owner, address indexed spender, uint256 indexed tokenId);

    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    /*//////////////////////////////////////////////////////////////
                           ATTRIBUTES STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @dev Mapping from `owner` to an SSTORE2 pointer where all their `tokenId`s are stored
    /// @custom:future-work If there are properties specific to an `owner` (_not_ a token) this could map to a
    /// struct instead of just an `address`. There are 96 extra bits to work with.
    mapping(address => address) internal _pointers;

    /*//////////////////////////////////////////////////////////////
                             ERC721 STORAGE
    //////////////////////////////////////////////////////////////*/

    uint256 public totalSupply;

    /// @dev The lowest bits of `tokenId` are a counter. The counter starts at 0, and increases by 1 after each
    /// mint. To get the owner of a `tokenId` with counter = i, search this mapping (beginning at the ith index and
    /// moving up) until a non-zero entry is found. That entry is the owner.
    mapping(uint256 => address) internal _owners;

    mapping(uint256 => address) public getApproved;

    mapping(address => mapping(address => bool)) public isApprovedForAll;

    /*//////////////////////////////////////////////////////////////
                             METADATA LOGIC
    //////////////////////////////////////////////////////////////*/

    function name() external view virtual returns (string memory);

    function symbol() external view virtual returns (string memory);

    function tokenURI(uint256 tokenId) external view virtual returns (string memory);

    /*//////////////////////////////////////////////////////////////
                              ERC721 LOGIC
    //////////////////////////////////////////////////////////////*/

    function ownerOf(uint256 tokenId) public view virtual returns (address owner) {
        uint256 i = _indexOf(tokenId);
        require(i < totalSupply, "NOT_MINTED");

        unchecked {
            while (true) {
                owner = _owners[i];
                if (owner != address(0)) break;
                i++;
            }
        }

        require(_pointers[owner].read().includes(tokenId, _TOKEN_SIZE()), "NOT_MINTED");
    }

    function balanceOf(address owner) public view virtual returns (uint256) {
        require(owner != address(0), "ZERO_ADDRESS");

        address pointer = _pointers[owner];
        return pointer == address(0) ? 0 : (pointer.code.length - SSTORE2.DATA_OFFSET) / _TOKEN_SIZE();
    }

    function approve(address spender, uint256 tokenId) public virtual {
        address owner = ownerOf(tokenId);

        require(msg.sender == owner || isApprovedForAll[owner][msg.sender], "NOT_AUTHORIZED");

        getApproved[tokenId] = spender;

        emit Approval(owner, spender, tokenId);
    }

    function setApprovalForAll(address operator, bool approved) public virtual {
        isApprovedForAll[msg.sender][operator] = approved;

        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function transferFrom(address from, address to, uint256 tokenId) public virtual {
        require(to != address(0), "INVALID_RECIPIENT");
        require(
            msg.sender == from || isApprovedForAll[from][msg.sender] || msg.sender == getApproved[tokenId],
            "NOT_AUTHORIZED"
        );

        // Move `tokenId` and update storage pointers. `from` must own `tokenId` for `remove` to succeed
        _pointers[from] = _pointers[from].read().remove(tokenId, _TOKEN_SIZE()).write();
        _pointers[to] = _pointers[to].read().append(tokenId, _TOKEN_SIZE()).write();

        // Update `_owners` array
        uint256 i = _indexOf(tokenId);
        _owners[i] = to;
        if (i > 0 && _owners[i - 1] == address(0)) {
            _owners[i - 1] = from;
        }

        // Delete old approval
        delete getApproved[tokenId];

        emit Transfer(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) public virtual {
        safeTransferFrom(from, to, tokenId, "");
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public virtual {
        transferFrom(from, to, tokenId);

        require(
            to.code.length == 0 ||
                ERC721TokenReceiver(to).onERC721Received(msg.sender, from, tokenId, data) ==
                ERC721TokenReceiver.onERC721Received.selector,
            "UNSAFE_RECIPIENT"
        );
    }

    /*//////////////////////////////////////////////////////////////
                              ERC165 LOGIC
    //////////////////////////////////////////////////////////////*/

    function supportsInterface(bytes4 interfaceId) external view virtual returns (bool) {
        return
            interfaceId == 0x01ffc9a7 || // ERC165 Interface ID for ERC165
            interfaceId == 0x80ac58cd || // ERC165 Interface ID for ERC721
            interfaceId == 0x5b5e139f; // ERC165 Interface ID for ERC721Metadata
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL MINT/BURN LOGIC
    //////////////////////////////////////////////////////////////*/

    function _mint(address to, uint256 qty, uint256[] memory attributes) internal virtual {
        require(to != address(0), "INVALID_RECIPIENT");
        require(qty > 0 && qty == attributes.length, "BAD_QUANTITY");

        unchecked {
            // Increase `totalSupply` by `qty`
            uint256 totalSupply_ = totalSupply;
            require((totalSupply = totalSupply_ + qty) < _MAX_SUPPLY(), "MAX_SUPPLY");

            // Set the owner of the highest minted index
            _owners[totalSupply_ + qty - 1] = to;

            // Emit an event for each new token
            uint256 i;
            do {
                attributes[i] = _tokenIdFor(totalSupply_ + i, attributes[i]);
                emit Transfer(address(0), to, attributes[i]);
                i++;
            } while (i < qty);
        }

        // Write new `tokenId`s (`attributes` array was overwritten with full `tokenId`s in the loop)
        _pointers[to] = _pointers[to].read().append(attributes, _TOKEN_SIZE()).write();
    }

    /*//////////////////////////////////////////////////////////////
                            ATTRIBUTES LOGIC
    //////////////////////////////////////////////////////////////*/

    function _tokenIdFor(uint256 index, uint256 attributes) internal pure returns (uint256) {
        return index | (attributes << (_INDEX_SIZE() << 3));
    }

    function _indexOf(uint256 tokenId) internal pure returns (uint256) {
        return tokenId % _MAX_SUPPLY();
    }

    function _attributesOf(uint256 tokenId) internal pure returns (uint256) {
        return tokenId >> (_INDEX_SIZE() << 3);
    }

    function _MAX_SUPPLY() internal pure returns (uint256) {
        return (1 << (_INDEX_SIZE() << 3));
    }

    function _TOKEN_SIZE() internal pure returns (uint256 tokenSize) {
        unchecked {
            tokenSize = _INDEX_SIZE() + _ATTRIBUTES_SIZE();
            // The optimizer removes this assertion; don't worry about gas
            assert(tokenSize <= 32);
        }
    }

    /// @dev The number of bytes used to store indices. This plus `_ATTRIBUTES_SIZE` MUST be a constant <= 32.
    function _INDEX_SIZE() internal pure virtual returns (uint256);

    /// @dev The number of bytes used to store attributes. This plus `_INDEX_SIZE` MUST be a constant <= 32.
    function _ATTRIBUTES_SIZE() internal pure virtual returns (uint256);
}

/// @notice A generic interface for a contract which properly accepts ERC721 tokens.
/// @author Solmate (https://github.com/transmissions11/solmate/blob/main/src/tokens/ERC721.sol)
abstract contract ERC721TokenReceiver {
    function onERC721Received(address, address, uint256, bytes calldata) external virtual returns (bytes4) {
        return ERC721TokenReceiver.onERC721Received.selector;
    }
}
