// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

library Positions {
    uint256 private constant Q24 = 0x1000000;

    function write(int24[6] storage stor, int24[] memory mem) internal {
        // Validate formatting of Uniswap positions
        uint256 count = mem.length;
        require(count <= 6, "Aloe: too many positions");

        // Ensure uniqueness of Uniswap positions and store them
        if (count > 0) {
            stor[0] = mem[0];
            stor[1] = mem[1];
        }
        if (count > 2) {
            require(mem[2] != mem[0] || mem[3] != mem[1]);
            stor[2] = mem[2];
            stor[3] = mem[3];
        }
        if (count > 4) {
            require(mem[4] != mem[0] || mem[5] != mem[1]);
            require(mem[4] != mem[2] || mem[5] != mem[3]);
            stor[4] = mem[4];
            stor[5] = mem[5];
        }
    }

    function read(int24[6] storage positions) internal view returns (int24[] memory ptr) {
        assembly ("memory-safe") {
            // positions = [xl, xu, yl, yu, zl, zu]
            // cpy:
            // -->  xl + (xu << 24) + (yl << 48) + (yu << 72) + (zl << 96) + (zu << 120)
            // -->  |-------|-----|----|----|----|----|----|
            //      | shift | 120 | 96 | 72 | 48 | 24 |  0 |
            //      | value |  zu | zl | yu | yl | xu | xl |
            //      |-------|-----|----|----|----|----|----|
            let cpy := sload(positions.slot)

            ptr := mload(0x40)
            let offset := 3

            // if xl != xu
            let l := mod(cpy, Q24)
            let u := mod(shr(24, cpy), Q24)
            if iszero(eq(l, u)) {
                mstore(add(ptr, 32), l)
                mstore(add(ptr, 64), u)
                offset := 96
            }

            // if yl != yu
            l := mod(shr(48, cpy), Q24)
            u := mod(shr(72, cpy), Q24)
            if iszero(eq(l, u)) {
                mstore(add(ptr, offset), l)
                mstore(add(ptr, add(offset, 32)), u)
                offset := add(offset, 64)
            }

            // if zl != zu
            l := mod(shr(96, cpy), Q24)
            u := shr(120, cpy)
            if iszero(eq(l, u)) {
                mstore(add(ptr, offset), l)
                mstore(add(ptr, add(offset, 32)), u)
                offset := add(offset, 64)
            }

            mstore(ptr, div(sub(offset, 32), 32))
            mstore(0x40, add(ptr, offset))
        }
    }
}
