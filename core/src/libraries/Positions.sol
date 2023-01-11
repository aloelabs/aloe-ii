// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

uint256 constant Q24 = 0x1000000;

/**
 * @notice Extracts up to three Uniswap positions from `zipped`. Each position consists of an `int24 lower` and
 * `int24 upper`, and will be included in the output array iff `lower != upper`. The output array is flattened
 * such that lower and upper ticks are next to each other, e.g. one position may be at indices 0 & 1, and another
 * at indices 2 & 3.
 * @dev The output array's length will be one of {0, 2, 4, 6}. We do *not* validate that `lower < upper`, nor do
 * we check whether positions actually hold liquidity. Also note that this function will happily return duplicate
 * positions like [-100, 100, -100, 100].
 * @param zipped Encoded Uniswap positions. Equivalent to the layout of `int24[6] storage yourPositions`
 * @return positionsOfNonZeroWidth Flattened array of Uniswap positions that may or may not hold liquidity
 */
function extract(uint144 zipped) pure returns (int24[] memory positionsOfNonZeroWidth) {
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
    function write(int24[6] storage stor, int24[] memory mem) internal returns (int24[] memory) {
        // Validate formatting of Uniswap positions
        uint256 count = mem.length;

        // Ensure uniqueness of Uniswap positions and store them
        if (count == 2) {
            stor[0] = mem[0];
            stor[1] = mem[1];
            stor[2] = 0;
            stor[3] = 0;
            stor[4] = 0;
            stor[5] = 0;
            return mem;
        } else if (count == 4) {
            require(mem[0] != mem[2] || mem[1] != mem[3]);
            stor[0] = mem[0];
            stor[1] = mem[1];
            stor[2] = mem[2];
            stor[3] = mem[3];
            stor[4] = 0;
            stor[5] = 0;
            return mem;
        } else if (count == 6) {
            require(
                (mem[0] != mem[2] || mem[1] != mem[3]) &&
                    (mem[2] != mem[4] || mem[3] != mem[5]) &&
                    (mem[4] != mem[0] || mem[5] != mem[1])
            );
            stor[0] = mem[0];
            stor[1] = mem[1];
            stor[2] = mem[2];
            stor[3] = mem[3];
            stor[4] = mem[4];
            stor[5] = mem[5];
            return mem;
        } else {
            return read(stor);
        }
    }

    function read(int24[6] storage positions) internal view returns (int24[] memory positions_) {
        uint144 zipped;
        assembly ("memory-safe") {
            zipped := sload(positions.slot)
        }
        positions_ = extract(zipped);
    }
}
