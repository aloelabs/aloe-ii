// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {Q24, Q48} from "./constants/Q.sol"; // solhint-disable-line no-unused-import

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
 * we check whether positions actually hold liquidity. Also note that this function will revert if `zipped`
 * contains duplicate positions like [-100, 100, -100, 100].
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
            let isSameAsX := eq(mod(shr(48, zipped), Q48), mod(zipped, Q48))
            if isSameAsX {
                // revert with `DuplicatePosition()`
                mstore(0x00, 0xe13355df)
                revert(0x1c, 0x04)
            }

            mstore(add(positionsOfNonZeroWidth, offset), l)
            mstore(add(positionsOfNonZeroWidth, add(offset, 32)), u)
            offset := add(offset, 64)
        }

        // if zl != zu
        l := mod(shr(96, zipped), Q24)
        u := mod(shr(120, zipped), Q24)
        if iszero(eq(l, u)) {
            let isSameAsX := eq(mod(shr(96, zipped), Q48), mod(zipped, Q48))
            let isSameAsY := eq(mod(shr(96, zipped), Q48), mod(shr(48, zipped), Q48))
            if or(isSameAsX, isSameAsY) {
                // revert with `DuplicatePosition()`
                mstore(0x00, 0xe13355df)
                revert(0x1c, 0x04)
            }

            mstore(add(positionsOfNonZeroWidth, offset), l)
            mstore(add(positionsOfNonZeroWidth, add(offset, 32)), u)
            offset := add(offset, 64)
        }

        mstore(positionsOfNonZeroWidth, shr(5, sub(offset, 32)))
        mstore(0x40, add(positionsOfNonZeroWidth, offset))
    }
}
