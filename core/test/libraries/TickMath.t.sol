// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import {TickMath} from "src/libraries/TickMath.sol";

contract TickMathTest is Test {
    function setUp() public {}

    function test_memoryGetTickAtSqrtRatio(uint160 sqrtPriceX96) public {
        if (sqrtPriceX96 < TickMath.MIN_SQRT_RATIO) sqrtPriceX96 = TickMath.MIN_SQRT_RATIO;
        else if (sqrtPriceX96 >= TickMath.MAX_SQRT_RATIO) sqrtPriceX96 = TickMath.MAX_SQRT_RATIO - 1;

        vm.expectSafeMemory(0x00, 0x60);
        TickMath.getTickAtSqrtRatio(sqrtPriceX96);
    }

    function test_floor(int24 tick, uint8 tickSpacing) public {
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

    function test_ceil(int24 tick, uint8 tickSpacing) public {
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

    function test_getTickAtSqrtRatio(uint160 sqrtPriceX96) public {
        if (sqrtPriceX96 < TickMath.MIN_SQRT_RATIO) {
            vm.expectRevert(bytes("R"));
            TickMath.getTickAtSqrtRatio(sqrtPriceX96);
            sqrtPriceX96 = TickMath.MIN_SQRT_RATIO;
        } else if (sqrtPriceX96 >= TickMath.MAX_SQRT_RATIO) {
            vm.expectRevert(bytes("R"));
            TickMath.getTickAtSqrtRatio(sqrtPriceX96);
            sqrtPriceX96 = TickMath.MAX_SQRT_RATIO - 1;
        }

        int24 a = TickMath.getTickAtSqrtRatio(sqrtPriceX96);
        int24 b = getTickAtSqrtRatio(sqrtPriceX96);

        assertEq(a, b);
    }
}

/// @dev Original Uniswap implementation
function getTickAtSqrtRatio(uint160 sqrtPriceX96) pure returns (int24 tick) {
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
