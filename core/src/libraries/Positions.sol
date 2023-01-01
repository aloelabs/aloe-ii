// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

library Positions {
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
        uint256 count = stor.length;

        if (count > 0) {
            mem = new int24[](count);
            mem[0] = stor[0];
            mem[1] = stor[1];
        }
        if (count > 2) {
            mem[2] = stor[2];
            mem[3] = stor[3];
        }
        if (count > 4) {
            mem[4] = stor[4];
            mem[5] = stor[5];
        }
    }
}
