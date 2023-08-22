// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

/// @notice Finds the most significant bit of `x`
function msb(uint256 x) pure returns (uint256 y) {
    assembly ("memory-safe") {
        y := shl(7, lt(0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, x))
        y := or(y, shl(6, lt(0xFFFFFFFFFFFFFFFF, shr(y, x))))
        y := or(y, shl(5, lt(0xFFFFFFFF, shr(y, x))))

        // For the remaining 32 bits, use a De Bruijn lookup.
        // See: https://graphics.stanford.edu/~seander/bithacks.html
        x := shr(y, x)
        x := or(x, shr(1, x))
        x := or(x, shr(2, x))
        x := or(x, shr(4, x))
        x := or(x, shr(8, x))
        x := or(x, shr(16, x))

        y := or(
            y,
            byte(
                shr(251, mul(x, shl(224, 0x07c4acdd))),
                0x0009010a0d15021d0b0e10121619031e080c141c0f111807131b17061a05041f
            )
        )
    }
}

/**
 * @notice Implements the binary logarithm
 * @param x A Q128.128 number. WARNING: If `x == 0` this pretends it's 1
 * @return result log_2(x) as a Q8.10 number, precise up to 10 fractional bits
 * @custom:math The math, for your convenience...
 * log_2(x) = log_2(2^n · y)                                         |  n ∈ ℤ, y ∈ [1, 2)
 *          = log_2(2^n) + log_2(y)
 *          = n + log_2(y)
 *            ┃     ║
 *            ┃     ║  ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
 *            ┗━━━━━╫━━┫ n = ⌊log_2(x)⌋                ┃
 *                  ║  ┃   = most significant bit of x ┃
 *                  ║  ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
 *                  ║
 *                  ║  ╔════════════════════════════════════════════════════════════════╗
 *                  ╚══╣ Iterative Approximation:                                       ║
 *                     ║ ↳ goal: solve log_2(a) | a ∈ [1, 2)                            ║
 *                     ║                                                                ║
 *                     ║ log_2(a) = ½log_2(a^2)                                         ║
 *                     ║          = ½⌊log_2(a^2)⌋ - ½⌊log_2(a^2)⌋ + ½log_2(a^2)         ║
 *                     ║                                                                ║
 *                     ║                                              ⎧ 0   for a^2 < 2 ║
 *                     ║ a ∈ [1, 2)  ⇒  a^2 ∈ [1, 4)  ∴  ⌊log_2(a^2)⌋ ⎨                 ║
 *                     ║                                              ⎩ 1   for a^2 ≥ 2 ║
 *                     ║                                                                ║
 *                     ║ if a^2 < 2                                                     ║
 *                     ║ ┌────────────────────────────────────────────────────────────┐ ║
 *                     ║ │ log_2(a) = ½⌊log_2(a^2)⌋ - ½⌊log_2(a^2)⌋ + ½log_2(a^2)     │ ║
 *                     ║ │          = ½⌊log_2(a^2)⌋ - ½·0 + ½log_2(a^2)               │ ║
 *                     ║ │          = ½⌊log_2(a^2)⌋ + ½log_2(a^2)                     │ ║
 *                     ║ │                                                            │ ║
 *                     ║ │ (Yes, 1st term is just 0. Keeping it as-is for fun.)       │ ║
 *                     ║ │ a^2 ∈ [1, 4)  ^  a^2 < 2  ∴  a^2 ∈ [1, 2)                  │ ║
 *                     ║ └────────────────────────────────────────────────────────────┘ ║
 *                     ║                                                                ║
 *                     ║ if a^2 ≥ 2                                                     ║
 *                     ║ ┌────────────────────────────────────────────────────────────┐ ║
 *                     ║ │ log_2(a) = ½⌊log_2(a^2)⌋ - ½⌊log_2(a^2)⌋ + ½log_2(a^2)     │ ║
 *                     ║ │          = ½⌊log_2(a^2)⌋ - ½·1 + ½log_2(a^2)               │ ║
 *                     ║ │          = ½⌊log_2(a^2)⌋ + ½log_2(a^2) - ½                 │ ║
 *                     ║ │          = ½⌊log_2(a^2)⌋ + ½(log_2(a^2) - 1)               │ ║
 *                     ║ │          = ½⌊log_2(a^2)⌋ + ½(log_2(a^2) - log_2(2))        │ ║
 *                     ║ │          = ½⌊log_2(a^2)⌋ + ½log_2(a^2 / 2)                 │ ║
 *                     ║ │                                                            │ ║
 *                     ║ │ (Yes, 1st term is just ½. Keeping it as-is for fun.)       │ ║
 *                     ║ │ a^2 ∈ [1, 4)  ^  a^2 ≥ 2  ∴  a^2 / 2 ∈ [1, 2)              │ ║
 *                     ║ └────────────────────────────────────────────────────────────┘ ║
 *                     ║                                                                ║
 *                     ║ ↳ combining...                                                 ║
 *                     ║                                                                ║
 *                     ║                              ⎧ log_2(a^2)       for a^2 < 2    ║
 *                     ║ log_2(a) = ½⌊log_2(a^2)⌋ + ½·⎨                                 ║
 *                     ║                              ⎩ log_2(a^2 / 2)   for a^2 ≥ 2    ║
 *                     ║                                                                ║
 *                     ║ ↳ works out nicely! as shown above, the arguments of the       ║
 *                     ║   final log_2 (a^2 and a^2 / 2, respectively) are in the       ║
 *                     ║   range [1, 2)  ⇒  run the algo recursively. Each step adds    ║
 *                     ║   1 bit of precision to the result.                            ║
 *                     ╚════════════════════════════════════════════════════════════════╝
 */
function log2(uint256 x) pure returns (int256 result) {
    unchecked {
        // Compute the integer part of the logarithm
        // n ∈ [0, 256) so it could fit in uint8 if we wanted
        uint256 n = msb(x);

        // x = 2^n · y  ∴  y = x / 2^n
        // To retain as many digits as possible, we multiply by 2^127, i.e.
        // y = x * 2^127 / 2^n
        // y = x * 2^(127 - n) = x / 2^(n - 127)
        uint256 y = (n >= 128) ? x >> (n - 127) : x << (127 - n);
        // y ∈ [1 << 127, 2 << 127)

        // Since x is Q128.128, log2(1 * 2^128) = 0
        // To make that happen, we offset n by 128.
        // We also shift left to make room for the 10 fractional bits.
        result = (int256(n) - 128) << 10;
        // error ≡ ε = log_2(x) - n ∈ [0, 1)

        // To compute fractional bits, we need to implement the following
        // psuedocode (based on math above):
        //
        // ```
        // y = x / 2^n
        // for i in range(1, iters):
        //     y = y^2
        //     if y >= 2:
        //         n += 1 / 2^i
        //         y = y / 2
        // ```
        //
        // For gas efficiency, we unroll the for-loop in assembly:
        assembly ("memory-safe") {
            y := shr(127, mul(y, y)) // y = y^2
            let isGe2 := shr(128, y) // 1 if y >= 2 else 0
            result := or(result, shl(9, isGe2)) // if isGe2: result += 2^10/2^1
            y := shr(isGe2, y) // if isGe2: y = y/2
            // ε ∈ [0, 1/2)

            y := shr(127, mul(y, y))
            isGe2 := shr(128, y)
            result := or(result, shl(8, isGe2))
            y := shr(isGe2, y)
            // ε ∈ [0, 1/4)

            y := shr(127, mul(y, y))
            isGe2 := shr(128, y)
            result := or(result, shl(7, isGe2))
            y := shr(isGe2, y)
            // ε ∈ [0, 1/8)

            y := shr(127, mul(y, y))
            isGe2 := shr(128, y)
            result := or(result, shl(6, isGe2))
            y := shr(isGe2, y)
            // ε ∈ [0, 1/16)

            y := shr(127, mul(y, y))
            isGe2 := shr(128, y)
            result := or(result, shl(5, isGe2))
            y := shr(isGe2, y)
            // ε ∈ [0, 1/32)

            y := shr(127, mul(y, y))
            isGe2 := shr(128, y)
            result := or(result, shl(4, isGe2))
            y := shr(isGe2, y)
            // ε ∈ [0, 1/64)

            y := shr(127, mul(y, y))
            isGe2 := shr(128, y)
            result := or(result, shl(3, isGe2))
            y := shr(isGe2, y)
            // ε ∈ [0, 1/128)

            y := shr(127, mul(y, y))
            isGe2 := shr(128, y)
            result := or(result, shl(2, isGe2))
            y := shr(isGe2, y)
            // ε ∈ [0, 1/256)

            y := shr(127, mul(y, y))
            isGe2 := shr(128, y)
            result := or(result, shl(1, isGe2))
            y := shr(isGe2, y)
            // ε ∈ [0, 1/512)

            y := shr(127, mul(y, y))
            isGe2 := shr(128, y)
            result := or(result, shl(0, isGe2))
            // ε ∈ [0, 1/1024)
            // x / 2^result ∈ [2^0, 2^(1/1024))

            // This means that when recovering `x` via 2^result, we'll undershoot by
            // at most 1 - 2^(-1/1024) = 0.067667%
        }
    }
}

/**
 * @notice Implements the binary logarithm with customizable precision
 * @param x A Q128.128 number
 * @param iters The number of fractional bits to compute. Must be <= 64
 * @return result log_2(x) as a Q8.64 number, precise up to `iters` fractional bits.
 * If `iters < 64` some of the less significant bits will be unused.
 * @dev Customizable `iters` carries a gas penalty relative to the unrolled version
 */
function log2(uint256 x, uint8 iters) pure returns (int256 result) {
    unchecked {
        uint256 n = msb(x);
        uint256 y = (n >= 128) ? x >> (n - 127) : x << (127 - n);
        result = (int256(n) - 128) << 64;

        assembly ("memory-safe") {
            for {
                let i := 1
            } lt(i, add(iters, 1)) {
                i := add(i, 1)
            } {
                y := shr(127, mul(y, y))
                let isGe2 := shr(128, y)
                result := or(result, shl(sub(64, i), isGe2))
                y := shr(isGe2, y)
            }
        }
    }
}

/// @notice Same as `log2(x)`, but with ε ∈ [-1/1024, 0) instead of [0, 1/1024)
function log2Up(uint256 x) pure returns (int256 result) {
    unchecked {
        result = log2(x) + 1; // 1 = int256(1 << (10 - 10))
    }
}

/// @notice Same as `log2(x, iters)`, but with ε ∈ [-2^-iters, 0) instead of [0, 2^-iters)
function log2Up(uint256 x, uint8 iters) pure returns (int256 result) {
    unchecked {
        result = log2(x, iters) + int256(1 << (64 - iters));
    }
}

/* solhint-disable code-complexity */

/**
 * @notice Implements binary exponentiation
 * @param x A Q8.10 number, e.g. the output of log2. WARNING: Behavior is undefined outside [-131072, 131072)
 * @return result 2^x as a Q128.128 number
 * @custom:math The math, for your convenience...
 * 2^x = 2^(n + f)                                                |  n ∈ ℤ, f ∈ [0, 1)
 *     = 2^n · 2^f
 *
 *     Noting that f can be written as ∑(f_i / 2^i)               | f_i ∈ {0, 1}
 *     where each f_i is determined by the bit at that position,
 *
 *     = 2^n · 2^(f_1 / 2^1) · 2^(f_2 / 2^2) · 2^(f_3 / 2^3) ... · 2^(f_n / 2^n)
 *
 * To compute the magic numbers, you can use this snippet:
 * ```python
 *  from decimal import *
 *  getcontext().prec = 50
 *
 *  magic = lambda p: hex(int((Decimal(2) ** Decimal(128 + p)).to_integral_exact(ROUND_DOWN)))
 *
 *  magic(1/2)  # >>> '0x16A09E667F3BCC908B2FB1366EA957D3E'
 *  magic(1/4)  # >>> '0x1306FE0A31B7152DE8D5A46305C85EDEC'
 * ```
 */
function exp2(int256 x) pure returns (uint256 result) {
    unchecked {
        result = (1 << 127);

        if (x & (1 << 9) > 0) result = (result * 0x16A09E667F3BCC908B2FB1366EA957D3E) >> 128;
        if (x & (1 << 8) > 0) result = (result * 0x1306FE0A31B7152DE8D5A46305C85EDEC) >> 128;
        if (x & (1 << 7) > 0) result = (result * 0x1172B83C7D517ADCDF7C8C50EB14A7920) >> 128;
        if (x & (1 << 6) > 0) result = (result * 0x10B5586CF9890F6298B92B71842A98364) >> 128;
        if (x & (1 << 5) > 0) result = (result * 0x1059B0D31585743AE7C548EB68CA417FE) >> 128;
        if (x & (1 << 4) > 0) result = (result * 0x102C9A3E778060EE6F7CACA4F7A29BDE9) >> 128;
        if (x & (1 << 3) > 0) result = (result * 0x10163DA9FB33356D84A66AE336DCDFA40) >> 128;
        if (x & (1 << 2) > 0) result = (result * 0x100B1AFA5ABCBED6129AB13EC11DC9544) >> 128;
        if (x & (1 << 1) > 0) result = (result * 0x10058C86DA1C09EA1FF19D294CF2F679C) >> 128;
        if (x & (1 << 0) > 0) result = (result * 0x1002C605E2E8CEC506D21BFC89A23A010) >> 128;

        // x ∈ [-128 << 10, 127 << 10)  ∴  (127 - (x >> 10)) > 0
        result = (result << 128) >> uint256(127 - (x >> 10));
    }
}

/* solhint-enable code-complexity */
