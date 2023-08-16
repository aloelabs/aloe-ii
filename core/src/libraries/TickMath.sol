// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.17;

import {msb} from "./Log2.sol";

/// @title Math library for computing sqrt prices from ticks and vice versa
/// @notice Computes sqrt price for ticks of size 1.0001, i.e. \\(\sqrt{1.0001^{tick}}\\) as fixed point Q64.96 numbers. Supports
/// prices between \\(2^{-128}\\) and \\(2^{128}\\)
/// @author Aloe Labs, Inc.
/// @author Modified from [Uniswap](https://github.com/Uniswap/v3-core/blob/main/contracts/libraries/TickMath.sol) and
/// [Aperture Finance](https://github.com/Aperture-Finance/uni-v3-lib/blob/main/src/TickMath.sol)
library TickMath {
    /// @dev The minimum tick that may be passed to `getSqrtRatioAtTick` computed from \\( log_{1.0001}2^{-128} \\)
    int24 internal constant MIN_TICK = -887272;
    /// @dev The maximum tick that may be passed to `getSqrtRatioAtTick` computed from \\( log_{1.0001}2^{128} \\)
    int24 internal constant MAX_TICK = 887272;

    /// @dev The minimum value that can be returned from `getSqrtRatioAtTick`. Equivalent to `getSqrtRatioAtTick(MIN_TICK)`
    uint160 internal constant MIN_SQRT_RATIO = 4295128739;
    /// @dev The maximum value that can be returned from `getSqrtRatioAtTick`. Equivalent to `getSqrtRatioAtTick(MAX_TICK)`
    uint160 internal constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;
    /// @dev A threshold used for optimized bounds check, equals `MAX_SQRT_RATIO - MIN_SQRT_RATIO - 1`
    uint160 private constant MAX_SQRT_RATIO_MINUS_MIN_SQRT_RATIO_MINUS_ONE =
        1461446703485210103287273052203988822378723970342 - 4295128739 - 1;

    /* solhint-disable code-complexity */

    /// @notice Calculates \\( \sqrt{1.0001^{tick}} * 2^{96} \\)
    /// @dev Throws if |tick| > max tick
    /// @param tick The input tick for the above formula
    /// @return sqrtPriceX96 A Fixed point Q64.96 number representing the sqrt of the ratio of the two assets (token1/token0)
    /// at the given tick
    function getSqrtRatioAtTick(int24 tick) internal pure returns (uint160 sqrtPriceX96) {
        unchecked {
            int256 tick256;
            uint256 absTick;

            assembly ("memory-safe") {
                // sign extend to make tick an int256 in twos complement
                tick256 := signextend(2, tick)

                // compute absolute value (in-lined method from solady)
                // --> mask = 0 if x >= 0 else -1
                let mask := sub(0, slt(tick256, 0))
                // --> If x >= 0, |x| = x = 0 ^ x
                // --> If x < 0, |x| = ~~|x| = ~(-|x| - 1) = ~(x - 1) = -1 ^ (x - 1)
                // --> Either case, |x| = mask ^ (x + mask)
                absTick := xor(mask, add(mask, tick256))

                // Equivalent: if (absTick > MAX_TICK) revert("T")
                if gt(absTick, MAX_TICK) {
                    // selector "Error(string)", [0x1c, 0x20)
                    mstore(0, 0x08c379a0)
                    // abi encoding offset
                    mstore(0x20, 0x20)
                    // reason string length 1 and 'T', [0x5f, 0x61)
                    mstore(0x41, 0x0154)
                    // 4 byte selector + 32 byte offset + 32 byte length + 1 byte reason
                    revert(0x1c, 0x45)
                }
            }

            // Equivalent: ratio = 2**128 / sqrt(1.0001) if absTick & 0x1 else 1 << 128
            uint256 ratio;
            assembly ("memory-safe") {
                ratio := and(
                    shr(
                        // 128 if absTick & 0x1 else 0
                        shl(7, and(absTick, 0x1)),
                        // upper 128 bits of 2**256 / sqrt(1.0001) where the 128th bit is 1
                        0xfffcb933bd6fad37aa2d162d1a59400100000000000000000000000000000000
                    ),
                    0x1ffffffffffffffffffffffffffffffff // mask lower 129 bits
                )
            }
            // Iterate through 1st to 19th bit of absTick because MAX_TICK < 2**20
            // Equivalent to:
            //      for i in range(1, 20):
            //          if absTick & 2 ** i:
            //              ratio = ratio * (2 ** 128 / 1.0001 ** (2 ** (i - 1))) / 2 ** 128
            if (absTick & 0x2 != 0) ratio = (ratio * 0xfff97272373d413259a46990580e213a) >> 128;
            if (absTick & 0x4 != 0) ratio = (ratio * 0xfff2e50f5f656932ef12357cf3c7fdcc) >> 128;
            if (absTick & 0x8 != 0) ratio = (ratio * 0xffe5caca7e10e4e61c3624eaa0941cd0) >> 128;
            if (absTick & 0x10 != 0) ratio = (ratio * 0xffcb9843d60f6159c9db58835c926644) >> 128;
            if (absTick & 0x20 != 0) ratio = (ratio * 0xff973b41fa98c081472e6896dfb254c0) >> 128;
            if (absTick & 0x40 != 0) ratio = (ratio * 0xff2ea16466c96a3843ec78b326b52861) >> 128;
            if (absTick & 0x80 != 0) ratio = (ratio * 0xfe5dee046a99a2a811c461f1969c3053) >> 128;
            if (absTick & 0x100 != 0) ratio = (ratio * 0xfcbe86c7900a88aedcffc83b479aa3a4) >> 128;
            if (absTick & 0x200 != 0) ratio = (ratio * 0xf987a7253ac413176f2b074cf7815e54) >> 128;
            if (absTick & 0x400 != 0) ratio = (ratio * 0xf3392b0822b70005940c7a398e4b70f3) >> 128;
            if (absTick & 0x800 != 0) ratio = (ratio * 0xe7159475a2c29b7443b29c7fa6e889d9) >> 128;
            if (absTick & 0x1000 != 0) ratio = (ratio * 0xd097f3bdfd2022b8845ad8f792aa5825) >> 128;
            if (absTick & 0x2000 != 0) ratio = (ratio * 0xa9f746462d870fdf8a65dc1f90e061e5) >> 128;
            if (absTick & 0x4000 != 0) ratio = (ratio * 0x70d869a156d2a1b890bb3df62baf32f7) >> 128;
            if (absTick & 0x8000 != 0) ratio = (ratio * 0x31be135f97d08fd981231505542fcfa6) >> 128;
            if (absTick & 0x10000 != 0) ratio = (ratio * 0x9aa508b5b7a84e1c677de54f3e99bc9) >> 128;
            if (absTick & 0x20000 != 0) ratio = (ratio * 0x5d6af8dedb81196699c329225ee604) >> 128;
            if (absTick & 0x40000 != 0) ratio = (ratio * 0x2216e584f5fa1ea926041bedfe98) >> 128;
            if (absTick & 0x80000 != 0) ratio = (ratio * 0x48a170391f7dc42444e8fa2) >> 128;

            // Equivalent: if (tick > 0) ratio = type(uint256).max / ratio
            assembly ("memory-safe") {
                if sgt(tick256, 0) {
                    ratio := div(not(0), ratio)
                }
            }

            // this divides by 1<<32 rounding up to go from a Q128.128 to a Q128.96.
            // we then downcast because we know the result always fits within 160 bits due to our tick input constraint
            // we round up in the division so getTickAtSqrtRatio of the output price is always consistent
            assembly ("memory-safe") {
                sqrtPriceX96 := shr(32, add(ratio, 0xffffffff))
            }
        }
    }

    /* solhint-enable code-complexity */

    /// @notice Calculates the greatest tick value such that getRatioAtTick(tick) <= ratio
    /// @dev Throws in case sqrtPriceX96 < MIN_SQRT_RATIO, as MIN_SQRT_RATIO is the lowest value getRatioAtTick may
    /// ever return.
    /// @param sqrtPriceX96 The sqrt ratio for which to compute the tick as a Q64.96
    /// @return tick The greatest tick for which the ratio is less than or equal to the input ratio
    function getTickAtSqrtRatio(uint160 sqrtPriceX96) internal pure returns (int24 tick) {
        // Equivalent: require(sqrtPriceX96 >= MIN_SQRT_RATIO && sqrtPriceX96 < MAX_SQRT_RATIO, "R")
        assembly ("memory-safe") {
            // if sqrtPriceX96 < MIN_SQRT_RATIO, the `sub` underflows and `gt` is true
            // if sqrtPriceX96 >= MAX_SQRT_RATIO, sqrtPriceX96 - MIN_SQRT_RATIO > MAX_SQRT_RATIO - MAX_SQRT_RATIO - 1
            if gt(sub(sqrtPriceX96, MIN_SQRT_RATIO), MAX_SQRT_RATIO_MINUS_MIN_SQRT_RATIO_MINUS_ONE) {
                // selector "Error(string)", [0x1c, 0x20)
                mstore(0, 0x08c379a0)
                // abi encoding offset
                mstore(0x20, 0x20)
                // reason string length 1 and 'R', [0x5f, 0x61)
                mstore(0x41, 0x0152)
                // 4 byte selector + 32 byte offset + 32 byte length + 1 byte reason
                revert(0x1c, 0x45)
            }
        }

        // Compute the integer part of the logarithm
        // n ∈ [32, 160) so it could fit in uint8 if we wanted
        uint256 n = msb(sqrtPriceX96);

        int256 log_2;
        assembly ("memory-safe") {
            log_2 := shl(64, sub(n, 96))
            let r := shr(sub(n, 31), shl(96, sqrtPriceX96))

            r := shr(127, mul(r, r))
            let f := shr(128, r)
            log_2 := or(log_2, shl(63, f))
            r := shr(f, r)

            r := shr(127, mul(r, r))
            f := shr(128, r)
            log_2 := or(log_2, shl(62, f))
            r := shr(f, r)

            r := shr(127, mul(r, r))
            f := shr(128, r)
            log_2 := or(log_2, shl(61, f))
            r := shr(f, r)

            r := shr(127, mul(r, r))
            f := shr(128, r)
            log_2 := or(log_2, shl(60, f))
            r := shr(f, r)

            r := shr(127, mul(r, r))
            f := shr(128, r)
            log_2 := or(log_2, shl(59, f))
            r := shr(f, r)

            r := shr(127, mul(r, r))
            f := shr(128, r)
            log_2 := or(log_2, shl(58, f))
            r := shr(f, r)

            r := shr(127, mul(r, r))
            f := shr(128, r)
            log_2 := or(log_2, shl(57, f))
            r := shr(f, r)

            r := shr(127, mul(r, r))
            f := shr(128, r)
            log_2 := or(log_2, shl(56, f))
            r := shr(f, r)

            r := shr(127, mul(r, r))
            f := shr(128, r)
            log_2 := or(log_2, shl(55, f))
            r := shr(f, r)

            r := shr(127, mul(r, r))
            f := shr(128, r)
            log_2 := or(log_2, shl(54, f))
            r := shr(f, r)

            r := shr(127, mul(r, r))
            f := shr(128, r)
            log_2 := or(log_2, shl(53, f))
            r := shr(f, r)

            r := shr(127, mul(r, r))
            f := shr(128, r)
            log_2 := or(log_2, shl(52, f))
            r := shr(f, r)

            r := shr(127, mul(r, r))
            f := shr(128, r)
            log_2 := or(log_2, shl(51, f))
            r := shr(f, r)

            r := shr(127, mul(r, r))
            f := shr(128, r)
            log_2 := or(log_2, shl(50, f))
        }

        unchecked {
            int256 log_sqrt10001 = log_2 * 255738958999603826347141; // 128.128 number

            int24 tickLow = int24((log_sqrt10001 - 3402992956809132418596140100660247210) >> 128);
            tick = int24((log_sqrt10001 + 291339464771989622907027621153398088495) >> 128);

            // Equivalent: tick = tickLow == tickHi ? tickLow : getSqrtRatioAtTick(tickHi) <= sqrtPriceX96 ? tickHi : tickLow
            if (tickLow != tick) {
                uint160 sqrtRatioAtTickHi = getSqrtRatioAtTick(tick);
                assembly ("memory-safe") {
                    tick := sub(tick, gt(sqrtRatioAtTickHi, sqrtPriceX96))
                }
            }
        }
    }

    /// @notice Rounds down to the nearest tick where tick % tickSpacing == 0
    /// @param tick The tick to round
    /// @param tickSpacing The tick spacing to round to
    /// @return the floored tick
    /// @dev Ensure tick +/- tickSpacing does not overflow or underflow int24
    function floor(int24 tick, int24 tickSpacing) internal pure returns (int24) {
        int24 mod = tick % tickSpacing;

        unchecked {
            if (mod >= 0) return tick - mod;
            return tick - mod - tickSpacing;
        }
    }

    /// @notice Rounds up to the nearest tick where tick % tickSpacing == 0
    /// @param tick The tick to round
    /// @param tickSpacing The tick spacing to round to
    /// @return the ceiled tick
    /// @dev Ensure tick +/- tickSpacing does not overflow or underflow int24
    function ceil(int24 tick, int24 tickSpacing) internal pure returns (int24) {
        int24 mod = tick % tickSpacing;

        unchecked {
            if (mod > 0) return tick - mod + tickSpacing;
            return tick - mod;
        }
    }
}
