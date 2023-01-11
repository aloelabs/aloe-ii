// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

uint256 constant Q24 = 0x1000000;
uint256 constant Q144 = 0x1000000000000000000000000000000000000;

/// @dev unclean inputs could be a problem here, TODO make a better note about this
function zip(int24[6] memory positions) pure returns (uint144 zipped) {
    assembly ("memory-safe") {
        zipped := mod(mload(positions), Q24)
        zipped := add(zipped, shl(24, mod(mload(add(positions, 32)), Q24)))
        zipped := add(zipped, shl(48, mod(mload(add(positions, 64)), Q24)))
        zipped := add(zipped, shl(72, mod(mload(add(positions, 96)), Q24)))
        zipped := add(zipped, shl(96, mod(mload(add(positions, 128)), Q24)))
        zipped := add(zipped, shl(120, mod(mload(add(positions, 160)), Q24)))
    }
}

function extract(uint256 zipped) pure returns (int24[] memory positionsOfNonZeroWidth) {
    assembly ("memory-safe") {
        // zipped:
        // -->  xl + (xu << 24) + (yl << 48) + (yu << 72) + (zl << 96) + (zu << 120)
        // -->  |-------|-----|----|----|----|----|----|
        //      | shift | 120 | 96 | 72 | 48 | 24 |  0 |
        //      | value |  zu | zl | yu | yl | xu | xl |
        //      |-------|-----|----|----|----|----|----|

        positionsOfNonZeroWidth := mload(0x40)
        let offset := 32

        // if xl != xu
        let l := mod(zipped, Q24)
        let u := mod(shr(24, zipped), Q24)
        if iszero(eq(l, u)) {
            mstore(add(positionsOfNonZeroWidth, 32), l)
            mstore(add(positionsOfNonZeroWidth, 64), u)
            offset := 96
        }

        // if yl != yu
        l := mod(shr(48, zipped), Q24)
        u := mod(shr(72, zipped), Q24)
        if iszero(eq(l, u)) {
            mstore(add(positionsOfNonZeroWidth, offset), l)
            mstore(add(positionsOfNonZeroWidth, add(offset, 32)), u)
            offset := add(offset, 64)
        }

        // if zl != zu
        l := mod(shr(96, zipped), Q24)
        u := shr(120, zipped)
        if iszero(eq(l, u)) {
            mstore(add(positionsOfNonZeroWidth, offset), l)
            mstore(add(positionsOfNonZeroWidth, add(offset, 32)), u)
            offset := add(offset, 64)
        }

        mstore(positionsOfNonZeroWidth, shr(5, sub(offset, 32)))
        mstore(0x40, add(positionsOfNonZeroWidth, offset))
    }
}

library Positions {
    function write(int24[6] storage positions, uint144 update) internal returns (int24[] memory) {
        if (update == 0) {
            return read(positions);
        }

        assembly ("memory-safe") {
            sstore(positions.slot, update)
        }

        // `extract` only returns positions of non-zero width, i.e. potentially active ones
        int24[] memory positions_ = extract(update);

        // We don't need to check that each lowerTick < upperTick, since Uniswap will handle
        // that for us. But we do need to make sure the user isn't trying to double-count
        // any liquidity.
        uint256 count = positions_.length;
        if (count == 4) {
            require(positions_[0] != positions_[2] || positions_[1] != positions_[3]);
        } else if (count == 6) {
            // prettier-ignore
            require(
                (positions_[0] != positions_[2] || positions_[1] != positions_[3]) &&
                (positions_[2] != positions_[4] || positions_[3] != positions_[5]) &&
                (positions_[4] != positions_[0] || positions_[5] != positions_[1])
            );
        }

        return positions_;
    }

    function read(int24[6] storage positions) internal view returns (int24[] memory positions_) {
        uint256 zipped;
        assembly ("memory-safe") {
            zipped := sload(positions.slot)
        }
        positions_ = extract(zipped);
    }
}
