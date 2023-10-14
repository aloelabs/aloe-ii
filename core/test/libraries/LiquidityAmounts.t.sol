// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";

import {LiquidityAmounts} from "src/libraries/LiquidityAmounts.sol";
import {msb} from "src/libraries/Log2.sol";
import {TickMath} from "src/libraries/TickMath.sol";

contract LiquidityAmountsTest is Test {
    function setUp() public {}

    function test_spec_getAmountsForLiquidity() public {
        uint160 current = 79226859512860901259714;
        uint160 lower = TickMath.getSqrtRatioAtTick(-290188);
        uint160 upper = TickMath.getSqrtRatioAtTick(-262460);
        uint128 liquidity = 998992023844159;

        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(current, lower, upper, liquidity);
        assertEq(amount0, 499522173722583583538);
        assertEq(amount1, 499487993);
    }

    function test_fuzz_getAmountsForLiquidity(
        uint160 sqrtPrice,
        uint160 sqrtLower,
        uint160 sqrtUpper,
        uint128 liquidity
    ) public {
        sqrtPrice = TickMath.MIN_SQRT_RATIO + (sqrtPrice % (TickMath.MAX_SQRT_RATIO - TickMath.MIN_SQRT_RATIO));
        sqrtLower = TickMath.MIN_SQRT_RATIO + (sqrtLower % (TickMath.MAX_SQRT_RATIO - TickMath.MIN_SQRT_RATIO));
        sqrtUpper = TickMath.MIN_SQRT_RATIO + (sqrtUpper % (TickMath.MAX_SQRT_RATIO - TickMath.MIN_SQRT_RATIO));

        if (sqrtLower > sqrtUpper) (sqrtLower, sqrtUpper) = (sqrtUpper, sqrtLower);

        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPrice,
            sqrtLower,
            sqrtUpper,
            liquidity
        );
        assertLe(amount0, type(uint192).max);
        assertLe(amount1, type(uint192).max);
    }

    function testFfi_getValuesOfLiquidity(
        uint160 sqrtPrice,
        uint160 sqrtLower,
        uint160 sqrtUpper,
        uint128 liquidity
    ) public {
        sqrtPrice = uint160(bound(sqrtPrice, TickMath.MIN_SQRT_RATIO, TickMath.MAX_SQRT_RATIO));
        sqrtLower = uint160(bound(sqrtLower, TickMath.MIN_SQRT_RATIO, TickMath.MAX_SQRT_RATIO));
        sqrtUpper = uint160(bound(sqrtUpper, TickMath.MIN_SQRT_RATIO, TickMath.MAX_SQRT_RATIO));

        vm.assume(sqrtLower != sqrtUpper);
        if (sqrtLower > sqrtUpper) (sqrtLower, sqrtUpper) = (sqrtUpper, sqrtLower);

        string[] memory cmds = new string[](6);
        cmds[0] = "python";
        cmds[1] = "test/libraries/LiquidityAmounts.py";
        cmds[2] = vm.toString(sqrtPrice);
        cmds[3] = vm.toString(sqrtLower);
        cmds[4] = vm.toString(sqrtUpper);
        cmds[5] = vm.toString(liquidity);
        bytes memory result = vm.ffi(cmds);

        (uint256 expected0, uint256 expected1) = abi.decode(result, (uint256, uint256));
        (uint256 value0, uint256 value1) = LiquidityAmounts.getValuesOfLiquidity(
            sqrtPrice,
            sqrtLower,
            sqrtUpper,
            liquidity
        );

        if (expected0 == 0) {
            assertEq(value0, expected0);
        } else if (sqrtPrice / 100 > TickMath.MIN_SQRT_RATIO && uint256(sqrtPrice) * 100 < TickMath.MAX_SQRT_RATIO) {
            if (sqrtPrice <= sqrtLower) {
                assertApproxEqRel(value0, expected0, 0.001e18);
            } else {
                assertApproxEqRel(value0, expected0, 0.000001e18);
            }
        } else {
            assertLe(value0, (expected0 * 101) / 100);
        }

        assertApproxEqRel(value1, expected1, 0.000001e18);
    }
}
