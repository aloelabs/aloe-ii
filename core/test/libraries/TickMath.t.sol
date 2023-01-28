// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import {TickMath} from "src/libraries/TickMath.sol";

contract TickMathTest is Test {
    function setUp() public {}

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
}
