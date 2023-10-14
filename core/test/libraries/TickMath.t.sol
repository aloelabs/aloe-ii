// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import {TickMath} from "src/libraries/TickMath.sol";

contract TickMathTest is Test {
    function setUp() public {}

    function test_fuzz_memoryGetTickAtSqrtRatio(uint160 sqrtPriceX96) public {
        if (sqrtPriceX96 < TickMath.MIN_SQRT_RATIO) sqrtPriceX96 = TickMath.MIN_SQRT_RATIO;
        else if (sqrtPriceX96 >= TickMath.MAX_SQRT_RATIO) sqrtPriceX96 = TickMath.MAX_SQRT_RATIO - 1;

        vm.expectSafeMemory(0x00, 0x60);
        TickMath.getTickAtSqrtRatio(sqrtPriceX96);
    }

    function test_fuzz_floor(int24 tick, uint8 tickSpacing) public {
        if (tick > TickMath.MAX_TICK || tick < TickMath.MIN_TICK) return;
        if (tickSpacing == 0) return;
        int24 _tickSpacing = int24(uint24(tickSpacing));

        int24 flooredTick = TickMath.floor(tick, _tickSpacing);

        assertEq(flooredTick % _tickSpacing, 0);
        assertLe(flooredTick, tick);
    }

    function test_spec_floor() public {
        assertEq(TickMath.floor(10, 10), 10);
        assertEq(TickMath.floor(9, 10), 0);
        assertEq(TickMath.floor(1, 10), 0);
        assertEq(TickMath.floor(0, 10), 0);
        assertEq(TickMath.floor(-1, 10), -10);
        assertEq(TickMath.floor(-9, 10), -10);
        assertEq(TickMath.floor(-10, 10), -10);
        assertEq(TickMath.floor(-11, 10), -20);

        assertEq(TickMath.floor(3, 1), 3);
        assertEq(TickMath.floor(-3, 1), -3);
    }

    function test_fuzz_ceil(int24 tick, uint8 tickSpacing) public {
        if (tick > TickMath.MAX_TICK || tick < TickMath.MIN_TICK) return;
        if (tickSpacing == 0) return;
        int24 _tickSpacing = int24(uint24(tickSpacing));

        int24 flooredTick = TickMath.ceil(tick, _tickSpacing);

        assertEq(flooredTick % _tickSpacing, 0);
        assertGe(flooredTick, tick);
    }

    function test_spec_ceil() public {
        assertEq(TickMath.ceil(11, 10), 20);
        assertEq(TickMath.ceil(10, 10), 10);
        assertEq(TickMath.ceil(1, 10), 10);
        assertEq(TickMath.ceil(0, 10), 0);
        assertEq(TickMath.ceil(-1, 10), 0);
        assertEq(TickMath.ceil(-9, 10), 0);
        assertEq(TickMath.ceil(-10, 10), -10);
        assertEq(TickMath.ceil(-11, 10), -10);

        assertEq(TickMath.ceil(3, 1), 3);
        assertEq(TickMath.ceil(-3, 1), -3);
    }

    /// forge-config: default.fuzz.runs = 16384
    function test_comparitive_getTickAtSqrtRatio(uint160 sqrtPriceX96) public {
        if (sqrtPriceX96 < TickMath.MIN_SQRT_RATIO) {
            vm.expectRevert(bytes("R"));
            TickMath.getTickAtSqrtRatio(sqrtPriceX96);
            vm.expectRevert(bytes("R"));
            getTickAtSqrtRatioOriginal(sqrtPriceX96);
            sqrtPriceX96 = TickMath.MIN_SQRT_RATIO;
        } else if (sqrtPriceX96 >= TickMath.MAX_SQRT_RATIO) {
            vm.expectRevert(bytes("R"));
            TickMath.getTickAtSqrtRatio(sqrtPriceX96);
            vm.expectRevert(bytes("R"));
            getTickAtSqrtRatioOriginal(sqrtPriceX96);
            sqrtPriceX96 = TickMath.MAX_SQRT_RATIO - 1;
        }

        int24 a = TickMath.getTickAtSqrtRatio(sqrtPriceX96);
        int24 b = getTickAtSqrtRatioOriginal(sqrtPriceX96);

        assertEq(a, b);
    }

    /// forge-config: default.fuzz.runs = 16384
    function test_comparitive_getSqrtRatioAtTick(int24 tick) public {
        if (tick < TickMath.MIN_TICK) {
            vm.expectRevert(bytes("T"));
            TickMath.getSqrtRatioAtTick(tick);
            vm.expectRevert(bytes("T"));
            getSqrtRatioAtTickOriginal(tick);
            tick = TickMath.MIN_TICK;
        } else if (tick > TickMath.MAX_TICK) {
            vm.expectRevert(bytes("T"));
            TickMath.getSqrtRatioAtTick(tick);
            vm.expectRevert(bytes("T"));
            getSqrtRatioAtTickOriginal(tick);
            tick = TickMath.MAX_TICK;
        }

        uint256 a = TickMath.getSqrtRatioAtTick(int24(tick));
        uint256 b = getSqrtRatioAtTickOriginal(int24(tick));

        assertEq(a, b);
    }
}

/// @dev Original Uniswap implementation
function getSqrtRatioAtTickOriginal(int24 tick) pure returns (uint160 sqrtPriceX96) {
    uint256 absTick = tick < 0 ? uint256(-int256(tick)) : uint256(int256(tick));
    require(absTick <= uint256(uint24(TickMath.MAX_TICK)), "T");

    uint256 ratio = absTick & 0x1 != 0 ? 0xfffcb933bd6fad37aa2d162d1a594001 : 0x100000000000000000000000000000000;
    unchecked {
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

        if (tick > 0) ratio = type(uint256).max / ratio;

        // this divides by 1<<32 rounding up to go from a Q128.128 to a Q128.96.
        // we then downcast because we know the result always fits within 160 bits due to our tick input constraint
        // we round up in the division so getTickAtSqrtRatio of the output price is always consistent
        sqrtPriceX96 = uint160((ratio >> 32) + (ratio % (1 << 32) == 0 ? 0 : 1));
    }
}

/// @dev Original Uniswap implementation
function getTickAtSqrtRatioOriginal(uint160 sqrtPriceX96) pure returns (int24 tick) {
    // second inequality must be < because the price can never reach the price at the max tick
    require(sqrtPriceX96 >= TickMath.MIN_SQRT_RATIO && sqrtPriceX96 < TickMath.MAX_SQRT_RATIO, "R");
    uint256 ratio = uint256(sqrtPriceX96) << 32;

    uint256 r = ratio;
    uint256 msb = 0;

    assembly {
        let f := shl(7, gt(r, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF))
        msb := or(msb, f)
        r := shr(f, r)
    }
    assembly {
        let f := shl(6, gt(r, 0xFFFFFFFFFFFFFFFF))
        msb := or(msb, f)
        r := shr(f, r)
    }
    assembly {
        let f := shl(5, gt(r, 0xFFFFFFFF))
        msb := or(msb, f)
        r := shr(f, r)
    }
    assembly {
        let f := shl(4, gt(r, 0xFFFF))
        msb := or(msb, f)
        r := shr(f, r)
    }
    assembly {
        let f := shl(3, gt(r, 0xFF))
        msb := or(msb, f)
        r := shr(f, r)
    }
    assembly {
        let f := shl(2, gt(r, 0xF))
        msb := or(msb, f)
        r := shr(f, r)
    }
    assembly {
        let f := shl(1, gt(r, 0x3))
        msb := or(msb, f)
        r := shr(f, r)
    }
    assembly {
        let f := gt(r, 0x1)
        msb := or(msb, f)
    }

    if (msb >= 128) r = ratio >> (msb - 127);
    else r = ratio << (127 - msb);

    int256 log_2 = (int256(msb) - 128) << 64;

    assembly {
        r := shr(127, mul(r, r))
        let f := shr(128, r)
        log_2 := or(log_2, shl(63, f))
        r := shr(f, r)
    }
    assembly {
        r := shr(127, mul(r, r))
        let f := shr(128, r)
        log_2 := or(log_2, shl(62, f))
        r := shr(f, r)
    }
    assembly {
        r := shr(127, mul(r, r))
        let f := shr(128, r)
        log_2 := or(log_2, shl(61, f))
        r := shr(f, r)
    }
    assembly {
        r := shr(127, mul(r, r))
        let f := shr(128, r)
        log_2 := or(log_2, shl(60, f))
        r := shr(f, r)
    }
    assembly {
        r := shr(127, mul(r, r))
        let f := shr(128, r)
        log_2 := or(log_2, shl(59, f))
        r := shr(f, r)
    }
    assembly {
        r := shr(127, mul(r, r))
        let f := shr(128, r)
        log_2 := or(log_2, shl(58, f))
        r := shr(f, r)
    }
    assembly {
        r := shr(127, mul(r, r))
        let f := shr(128, r)
        log_2 := or(log_2, shl(57, f))
        r := shr(f, r)
    }
    assembly {
        r := shr(127, mul(r, r))
        let f := shr(128, r)
        log_2 := or(log_2, shl(56, f))
        r := shr(f, r)
    }
    assembly {
        r := shr(127, mul(r, r))
        let f := shr(128, r)
        log_2 := or(log_2, shl(55, f))
        r := shr(f, r)
    }
    assembly {
        r := shr(127, mul(r, r))
        let f := shr(128, r)
        log_2 := or(log_2, shl(54, f))
        r := shr(f, r)
    }
    assembly {
        r := shr(127, mul(r, r))
        let f := shr(128, r)
        log_2 := or(log_2, shl(53, f))
        r := shr(f, r)
    }
    assembly {
        r := shr(127, mul(r, r))
        let f := shr(128, r)
        log_2 := or(log_2, shl(52, f))
        r := shr(f, r)
    }
    assembly {
        r := shr(127, mul(r, r))
        let f := shr(128, r)
        log_2 := or(log_2, shl(51, f))
        r := shr(f, r)
    }
    assembly {
        r := shr(127, mul(r, r))
        let f := shr(128, r)
        log_2 := or(log_2, shl(50, f))
    }

    int256 log_sqrt10001 = log_2 * 255738958999603826347141; // 128.128 number

    int24 tickLow = int24((log_sqrt10001 - 3402992956809132418596140100660247210) >> 128);
    int24 tickHi = int24((log_sqrt10001 + 291339464771989622907027621153398088495) >> 128);

    tick = tickLow == tickHi ? tickLow : TickMath.getSqrtRatioAtTick(tickHi) <= sqrtPriceX96 ? tickHi : tickLow;
}
