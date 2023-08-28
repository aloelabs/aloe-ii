// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {Q24} from "./constants/Q.sol"; // solhint-disable-line no-unused-import

/**
 * @notice Compresses `positions` into `zipped`. Useful for creating the return value of `IManager.callback`
 * @param positions A flattened array of ticks, each consecutive pair of indices representing one Uniswap position
 * @param zipped Encoded Uniswap positions
 */
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

/**
 * @notice Extracts up to three Uniswap positions from `zipped`. Each position consists of an `int24 lower` and
 * `int24 upper`, and will be included in the output array *iff* `lower != upper`. The output array is flattened
 * such that lower and upper ticks are next to each other, e.g. one position may be at indices 0 & 1, and another
 * at indices 2 & 3.
 * @dev The output array's length will be one of {0, 2, 4, 6}. We do *not* validate that `lower < upper`, nor do
 * we check whether positions actually hold liquidity. Also note that this function will happily return duplicate
 * positions like [-100, 100, -100, 100].
 * @param zipped Encoded Uniswap positions. Equivalent to the layout of `int24[6] storage yourPositions`
 * @return positionsOfNonZeroWidth Flattened array of Uniswap positions that may or may not hold liquidity
 */
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

/// @title Positions
/// @notice Provides functions for handling Uniswap positions in `Borrower`'s storage
/// @author Aloe Labs, Inc.
library Positions {
    function write(int24[6] storage positions, uint256 update) internal returns (int24[] memory) {
        // `update == 0` implies that the caller *does not* want to modify their positions, so we
        // read the existing ones and return early.
        if (update == 0) return read(positions);

        // Optimistically copy the `update`d positions to storage.
        // Need assembly to bypass Solidity's type-checking.
        assembly ("memory-safe") {
            sstore(positions.slot, update)
        }

        // Extract the updated positions from `update`. This is the array that will be used for
        // solvency checks (at least until the next `write`), so we need to verify that all
        // positions are unique (no duplicates / double-counting).
        int24[] memory positions_ = extract(update);

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

        // NOTE: we still haven't checked that each `lower < upper`, or that the ticks align
        // with tickSpacing. Uniswap will do that for us.
        return positions_;
    }

    function read(int24[6] storage positions) internal view returns (int24[] memory positions_) {
        uint144 zipped;
        assembly ("memory-safe") {
            zipped := sload(positions.slot)
        }
        positions_ = extract(zipped);
    }
}
