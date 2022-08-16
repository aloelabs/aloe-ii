// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

import "forge-std/Test.sol";

import {FullMath} from "src/libraries/FullMath.sol";
import {TickMath} from "src/libraries/TickMath.sol";
import {Volatility} from "src/libraries/Volatility.sol";

contract VolatilityTest is Test {
    function setUp() public {}

    function test_spec_estimate24H() public {
        Volatility.PoolMetadata memory metadata = Volatility.PoolMetadata(3600, 3000, 3000, 60);
        Volatility.PoolData memory data = Volatility.PoolData(
            1278673744380353403099539498152303, // sqrtPriceX96
            193789, // currentTick
            193730, // arithmeticMeanTick
            44521837137365694357186, // _secondsPerLiquidityX128
            3600, // _oracleLookback
            19685271204911047580 // poolLiquidity
        );
        uint256 dailyIV = Volatility.estimate24H(
            metadata,
            data,
            Volatility.FeeGrowthGlobals(
                1501955347902231987349614320458936,
                527278396421895291380335427321388844898052,
                0
            ),
            Volatility.FeeGrowthGlobals(
                1501968291161650295867029090958139,
                527315901327546020416261134123578344760082,
                8640
            )
        );
        assertEq(dailyIV, 20405953567249984); // 2.041%

        dailyIV = Volatility.estimate24H(
            metadata,
            data,
            Volatility.FeeGrowthGlobals(0, 0, 0),
            Volatility.FeeGrowthGlobals(
                1501968291161650295867029090958139,
                527315901327546020416261134123578344760082,
                uint32(block.timestamp)
            )
        );
        assertEq(dailyIV, 7014901299979332); // 0.701%

        dailyIV = Volatility.estimate24H(
            metadata,
            data,
            Volatility.FeeGrowthGlobals(
                1501955347902231987349614320458936,
                527278396421895291380335427321388844898052,
                0
            ),
            Volatility.FeeGrowthGlobals(
                1501955347902231987349614320458936,
                527278396421895291380335427321388844898052,
                8640
            )
        );
        assertEq(dailyIV, 0); // 0%

        dailyIV = Volatility.estimate24H(
            metadata,
            data,
            Volatility.FeeGrowthGlobals(
                1501955347902231987349614320458936,
                527278396421895291380335427321388844898052,
                0
            ),
            Volatility.FeeGrowthGlobals(
                1501955347902231987349614320458936,
                527278396421895291380335427321388844898052,
                uint32(block.timestamp)
            )
        );
        assertEq(dailyIV, 0); // 0%
    }

    function testFail_estimate24H() public pure {
        Volatility.PoolMetadata memory metadata = Volatility.PoolMetadata(3600, 3000, 3000, 60);
        Volatility.PoolData memory data = Volatility.PoolData(
            1278673744380353403099539498152303, // sqrtPriceX96
            193789, // currentTick
            193730, // arithmeticMeanTick
            44521837137365694357186, // _secondsPerLiquidityX128
            3600, // _oracleLookback
            19685271204911047580 // poolLiquidity
        );
        Volatility.estimate24H(
            metadata,
            data,
            Volatility.FeeGrowthGlobals(
                1501955347902231987349614320458936,
                527278396421895291380335427321388844898052,
                0
            ),
            Volatility.FeeGrowthGlobals(
                1501968291161650295867029090958139,
                527315901327546020416261134123578344760082,
                0
            )
        );
    }

    function test_estimate24H(
        uint128 tickLiquidity,
        int16 tick,
        int8 tickMeanOffset,
        uint192 a,
        uint192 b,
        uint48 c,
        uint48 d
    ) public pure {
        Volatility.PoolMetadata memory metadata = Volatility.PoolMetadata(3600, 3000, 3000, 60);
        Volatility.PoolData memory data = Volatility.PoolData(
            TickMath.getSqrtRatioAtTick(tick), // sqrtPriceX96
            tick, // currentTick
            tick + int24(tickMeanOffset), // arithmeticMeanTick
            44521837137365694357186, // secondsPerLiquidityX128
            3600, // oracleLookback
            tickLiquidity // tickLiquidity
        );
        Volatility.estimate24H(
            metadata,
            data,
            Volatility.FeeGrowthGlobals(a, b, 0),
            Volatility.FeeGrowthGlobals(uint256(a) + uint256(c), uint256(b) + uint256(d), 7777)
        );
    }

    function test_spec_amount0ToAmount1() public {
        uint256 amount1;

        amount1 = Volatility.amount0ToAmount1(0, 1000);
        assertEq(amount1, 0);
        amount1 = Volatility.amount0ToAmount1(0, -1000);
        assertEq(amount1, 0);
        amount1 = Volatility.amount0ToAmount1(type(uint128).max, 1000);
        assertEq(amount1, 376068295634136240002369832470443982846);
        amount1 = Volatility.amount0ToAmount1(type(uint128).max, -1000);
        assertEq(amount1, 307901757690220954445983032426008412159);
        amount1 = Volatility.amount0ToAmount1(4000000000, 193325); // ~ 4000 USDC
        assertEq(amount1, 994576722964113793); // ~ 1 ETH
    }

    function test_amount0ToAmount1(uint128 amount0, int16 tick) public {
        uint256 amount1 = Volatility.amount0ToAmount1(amount0, tick);

        if (amount0 == 0) {
            assertEq(amount1, 0);
            return;
        }
        if (amount0 < 1e6) return;

        uint256 priceX96Actual = FullMath.mulDiv(amount1, 2**96, amount0);

        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(tick);
        uint256 priceX96Expected = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, 2**96);

        if (-30000 < tick && tick < 30000) {
            assertLe(priceX96Actual / priceX96Expected, 1);
            assertLe(priceX96Expected / priceX96Actual, 1);
        }
    }

    function test_spec_computeRevenueGamma() public {
        uint128 revenueGamma = Volatility.computeRevenueGamma(11111111111, 222222222222, 3975297179, 5000, 100);
        assertEq(revenueGamma, 26);
    }

    function test_computeRevenueGamma(
        uint256 feeGrowthGlobalAX128,
        uint256 feeGrowthGlobalBX128,
        uint160 secondsPerLiquidityX128
    ) public pure {
        if (secondsPerLiquidityX128 == 0) return;
        Volatility.computeRevenueGamma(feeGrowthGlobalAX128, feeGrowthGlobalBX128, secondsPerLiquidityX128, 5000, 100);
    }

    function test_spec_computeTickTVL() public {
        uint256 tickTVL;
        tickTVL = Volatility.computeTickTVLX64(1, 19000, TickMath.getSqrtRatioAtTick(19000), 100000000000);
        assertEq(tickTVL, 238460396558056720196173824);
        tickTVL = Volatility.computeTickTVLX64(10, 19000, TickMath.getSqrtRatioAtTick(19000), 9763248618769789);
        assertEq(tickTVL, 232762454487181009148555451957248);
        tickTVL = Volatility.computeTickTVLX64(60, -19000, TickMath.getSqrtRatioAtTick(-19000), 100000000000);
        assertEq(tickTVL, 2138446074761944812648136704);
        tickTVL = Volatility.computeTickTVLX64(60, -3000, TickMath.getSqrtRatioAtTick(-3000), 999999999);
        assertEq(tickTVL, 47558380999913911951032320);
    }

    function test_computeTickTVL(
        int24 currentTick,
        uint8 tickSpacing,
        uint128 tickLiquidity
    ) public {
        if (tickSpacing == 0) return; // Always true in the real world
        int24 _tickSpacing = int24(uint24(tickSpacing));

        if (currentTick < TickMath.MIN_TICK) currentTick = TickMath.MIN_TICK + _tickSpacing;
        if (currentTick > TickMath.MAX_TICK) currentTick = TickMath.MAX_TICK - _tickSpacing;
        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(currentTick);

        // Ensure it doesn't revert
        uint256 tickTVL = Volatility.computeTickTVLX64(_tickSpacing, currentTick, sqrtPriceX96, tickLiquidity);

        // Check that it's non-zero in cases where we don't expect truncation
        int24 lowerBound = TickMath.MIN_TICK / 2;
        int24 upperBound = TickMath.MAX_TICK / 2;
        if (tickLiquidity > 1_000_000 && currentTick < lowerBound && currentTick > upperBound) assertGt(tickTVL, 0);
    }
}
