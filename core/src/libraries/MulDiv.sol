// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.23;

/// @dev Equivalent to `fullMulDiv(x, x, 1 << 64)`
function square(uint160 x) pure returns (uint256 result) {
    assembly ("memory-safe") {
        // 512-bit multiply [prod1 prod0] = x * x. Compute the product mod 2^256 and mod 2^256 - 1, then use
        // use the Chinese Remainder Theorem to reconstruct the 512 bit result. The result is stored in two 256
        // variables such that product = prod1 * 2^256 + prod0.

        // Least significant 256 bits of the product.
        let prod0 := mul(x, x)
        let mm := mulmod(x, x, not(0))
        // Most significant 256 bits of the product.
        let prod1 := sub(mm, add(prod0, lt(mm, prod0)))

        // Divide [prod1 prod0] by 2^64.
        result := or(shr(64, prod0), shl(192, prod1))
    }
}

/// @dev Equivalent to `fullMulDiv(x, y, 1 << 96)`.
/// NOTE: Does not check for overflow, so choose `x` and `y` carefully.
function mulDiv96(uint256 x, uint256 y) pure returns (uint256 result) {
    assembly ("memory-safe") {
        // 512-bit multiply [prod1 prod0] = x * y. Compute the product mod 2^256 and mod 2^256 - 1, then use
        // use the Chinese Remainder Theorem to reconstruct the 512 bit result. The result is stored in two 256
        // variables such that product = prod1 * 2^256 + prod0.

        // Least significant 256 bits of the product.
        let prod0 := mul(x, y)
        let mm := mulmod(x, y, not(0))
        // Most significant 256 bits of the product.
        let prod1 := sub(mm, add(prod0, lt(mm, prod0)))

        // Divide [prod1 prod0] by 2^96.
        result := or(shr(96, prod0), shl(160, prod1))
    }
}

/// @dev Equivalent to `fullMulDiv(x, x, 1 << 128)`
function mulDiv128(uint256 x, uint256 y) pure returns (uint256 result) {
    assembly ("memory-safe") {
        // 512-bit multiply [prod1 prod0] = x * y. Compute the product mod 2^256 and mod 2^256 - 1, then use
        // use the Chinese Remainder Theorem to reconstruct the 512 bit result. The result is stored in two 256
        // variables such that product = prod1 * 2^256 + prod0.

        // Least significant 256 bits of the product.
        let prod0 := mul(x, y)
        let mm := mulmod(x, y, not(0))
        // Most significant 256 bits of the product.
        let prod1 := sub(mm, add(prod0, lt(mm, prod0)))

        // Make sure the result is less than `2**256`.
        if iszero(gt(0x100000000000000000000000000000000, prod1)) {
            // Store the function selector of `FullMulDivFailed()`.
            mstore(0x00, 0xae47f702)
            // Revert with (offset, size).
            revert(0x1c, 0x04)
        }

        // Divide [prod1 prod0] by 2^128.
        result := or(shr(128, prod0), shl(128, prod1))
    }
}

/// @dev Equivalent to `fullMulDivUp(x, x, 1 << 128)`
function mulDiv128Up(uint256 x, uint256 y) pure returns (uint256 result) {
    result = mulDiv128(x, y);
    assembly ("memory-safe") {
        if mulmod(x, y, 0x100000000000000000000000000000000) {
            if iszero(add(result, 1)) {
                // Store the function selector of `FullMulDivFailed()`.
                mstore(0x00, 0xae47f702)
                // Revert with (offset, size).
                revert(0x1c, 0x04)
            }
            result := add(result, 1)
        }
    }
}

/// @dev Equivalent to `fullMulDiv(x, y, 1 << 224)`.
/// NOTE: Does not check for overflow, so choose `x` and `y` carefully.
function mulDiv224(uint256 x, uint256 y) pure returns (uint256 result) {
    assembly ("memory-safe") {
        // 512-bit multiply [prod1 prod0] = x * y. Compute the product mod 2^256 and mod 2^256 - 1, then use
        // use the Chinese Remainder Theorem to reconstruct the 512 bit result. The result is stored in two 256
        // variables such that product = prod1 * 2^256 + prod0.

        // Least significant 256 bits of the product.
        let prod0 := mul(x, y)
        let mm := mulmod(x, y, not(0))
        // Most significant 256 bits of the product.
        let prod1 := sub(mm, add(prod0, lt(mm, prod0)))

        // Divide [prod1 prod0] by 2^224.
        result := or(shr(224, prod0), shl(32, prod1))
    }
}
