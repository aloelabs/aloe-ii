// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

library Positions {
    uint256 private constant Q24 = 0x1000000;
    uint256 private constant Q48 = 0x1000000000000;
    uint256 private constant Q96 = 0x1000000000000000000000000;

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

    function read(int24[6] storage stor) internal view returns (int24[] memory mem) {
        assembly {
            // stor = [xl, xu, yl, yu, zl, zu]
            // cpy:
            // -->  xl + (xu << 24) + (yl << 48) + (yu << 72) + (zl << 96) + (zu << 120)
            // -->  |-------|-----|----|----|----|----|----|
            //      | shift | 120 | 96 | 72 | 48 | 24 |  0 |
            //      | value |  zu | zl | yu | yl | xu | xl |
            //      |-------|-----|----|----|----|----|----|
            let cpy := sload(stor.slot)
            let count := 0

            // If zu == zl...
            if eq(shr(cpy, 120), mod(shr(cpy, 96), Q24)) {
                cpy := mod(cpy, Q96)
                count := sub(count, 1)
            }

            // |----------|-----|----|----|----|----|----|-------|
            // | shift    | 120 | 96 | 72 | 48 | 24 |  0 | count |
            // | zl != zu |  zu | zl | yu | yl | xu | xl |     3 |
            // | zl == zu |     |    | yu | yl | xu | xl |     2 |
            // |----------|-----|----|----|----|----|----|-------|

            // If yu == yl...
            if eq(mod(shr(cpy, 72), Q24), mod(shr(cpy, 48), Q24)) {
                cpy := add(shl(shr(cpy, 96), 48), mod(cpy, Q48))
                count := sub(count, 1)
            }

            // |----------------------|-----|----|----|----|----|----|-------|
            // | shift                | 120 | 96 | 72 | 48 | 24 |  0 | count |
            // | zl != zu && yl != yu |  zu | zl | yu | yl | xu | xl |     3 |
            // | zl == zu && yl != yu |     |    | yu | yl | xu | xl |     2 |
            // | zl != zu && yl == yu |     |    | zu | zl | xu | xl |     2 |
            // | zl == zu && yl == yu |     |    |    |    | xu | xl |     1 |
            // |----------------------|-----|----|----|----|----|----|-------|

            // If xu == xl...
            if eq(mod(shr(cpy, 24), Q24), mod(cpy, Q24)) {
                cpy := shr(cpy, 48)
                count := sub(count, 1)
            }
        }

        // int24[6] memory cpy = stor;
        // bool x = cpy[0] != cpy[1];
        // bool y = cpy[2] != cpy[3];
        // bool z = cpy[4] != cpy[5];

        // uint256 count;
        // assembly ("memory-safe") {
        //     count := mul(add(x, add(y, z)), 2)
        // }
        // mem = new int24[](count);

        // unchecked {
        //     count = 0;
        //     if (x) {
        //         mem[0] = cpy[0];
        //         mem[1] = cpy[1];
        //         count += 2;
        //     }
        //     if (y) {
        //         mem[count] = cpy[2];
        //         mem[count + 1] = cpy[3];
        //         count += 2;
        //     }
        //     if (z) {
        //         mem[count] = cpy[4];
        //         mem[count + 1] = cpy[5];
        //     }
        // }
    }
}
