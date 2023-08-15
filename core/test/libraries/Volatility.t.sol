// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";

import {Volatility, Oracle, TickMath} from "src/libraries/Volatility.sol";

contract VolatilityTest is Test {
    function setUp() public {}

    function test_spec_estimate() public {
        Volatility.PoolMetadata memory metadata = Volatility.PoolMetadata(3000, 3000, 60);
        Oracle.PoolData memory data = Oracle.PoolData(
            1278673744380353403099539498152303, // sqrtPriceX96
            193789, // currentTick
            TickMath.getSqrtRatioAtTick(193730), // arithmeticMeanTick
            44521837137365694357186, // _secondsPerLiquidityX128
            3600, // _oracleLookback
            19685271204911047580 // poolLiquidity
        );
        uint256 dailyIV = Volatility.estimate(
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
            ),
            1 days
        );
        assertEq(dailyIV, 20405953567249984); // 2.041%

        dailyIV = Volatility.estimate(
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
            ),
            1 hours
        );
        assertEq(dailyIV, 4165347829168579); // 0.417%

        dailyIV = Volatility.estimate(
            metadata,
            data,
            Volatility.FeeGrowthGlobals(0, 0, 0),
            Volatility.FeeGrowthGlobals(
                1501968291161650295867029090958139,
                527315901327546020416261134123578344760082,
                uint32(1660599905)
            ),
            1 days
        );
        assertEq(dailyIV, 6970260198990240); // 0.697%

        dailyIV = Volatility.estimate(
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
            ),
            1 days
        );
        assertEq(dailyIV, 0); // 0%

        dailyIV = Volatility.estimate(
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
                uint32(1660599905)
            ),
            1 days
        );
        assertEq(dailyIV, 0); // 0%
    }

    function test_estimate(
        uint128 tickLiquidity,
        int16 tick,
        int8 tickMeanOffset,
        uint192 a,
        uint192 b,
        uint48 c,
        uint48 d
    ) public pure {
        Volatility.PoolMetadata memory metadata = Volatility.PoolMetadata(3000, 3000, 60);
        Oracle.PoolData memory data = Oracle.PoolData(
            TickMath.getSqrtRatioAtTick(tick), // sqrtPriceX96
            tick, // currentTick
            TickMath.getSqrtRatioAtTick(tick + int24(tickMeanOffset)), // arithmeticMeanTick
            44521837137365694357186, // secondsPerLiquidityX128
            3600, // oracleLookback
            tickLiquidity // tickLiquidity
        );
        Volatility.estimate(
            metadata,
            data,
            Volatility.FeeGrowthGlobals(a, b, 0),
            Volatility.FeeGrowthGlobals(uint256(a) + uint256(c), uint256(b) + uint256(d), 7777),
            1 days
        );
    }

    function test_spec_amount0ToAmount1() public {
        uint256 amount1;

        amount1 = Volatility.amount0ToAmount1(0, TickMath.getSqrtRatioAtTick(1000));
        assertEq(amount1, 0);
        amount1 = Volatility.amount0ToAmount1(0, TickMath.getSqrtRatioAtTick(-1000));
        assertEq(amount1, 0);
        amount1 = Volatility.amount0ToAmount1(type(uint128).max, TickMath.getSqrtRatioAtTick(1000));
        assertEq(amount1, 376068295634136240002369832470443982846);
        amount1 = Volatility.amount0ToAmount1(type(uint128).max, TickMath.getSqrtRatioAtTick(-1000));
        assertEq(amount1, 307901757690220954445983032426008412159);
        amount1 = Volatility.amount0ToAmount1(4000000000, TickMath.getSqrtRatioAtTick(193325)); // ~ 4000 USDC
        assertEq(amount1, 994576722964113793); // ~ 1 ETH
    }

    function test_amount0ToAmount1(uint128 amount0, int16 tick) public {
        uint256 amount1 = Volatility.amount0ToAmount1(amount0, TickMath.getSqrtRatioAtTick(tick));

        if (amount0 == 0) {
            assertEq(amount1, 0);
            return;
        }
        if (amount0 < 1e6) return;

        uint256 priceX96Actual = Math.mulDiv(amount1, 2 ** 96, amount0);

        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(tick);
        uint256 priceX96Expected = Math.mulDiv(sqrtPriceX96, sqrtPriceX96, 2 ** 96);

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

    function test_noRevert_computeTickTVLX64(
        uint8 tier,
        int24 tick,
        uint128 liquidity
    ) public pure {
        int24 tickSpacing;
        tier = tier % 4;
        if (tier == 0) tickSpacing = 1;
        else if (tier == 1) tickSpacing = 10;
        else if (tier == 2) tickSpacing = 60;
        else if (tier == 3) tickSpacing = 100;

        if (tick < TickMath.MIN_TICK + tickSpacing) tick = TickMath.MIN_TICK + tickSpacing;
        else if (tick > TickMath.MAX_TICK - tickSpacing) tick = TickMath.MAX_TICK - tickSpacing;

        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(tick);

        Volatility.computeTickTVLX64(
            tickSpacing,
            tick,
            sqrtPriceX96,
            liquidity
        );
    }

    function test_noRevert_computeRevenueGamma(
        uint256 feeGrowthGlobalAX128,
        uint224 feeGrowthGlobalDeltaX128,
        uint160 secondsPerLiquidityX128,
        uint32 secondsAgo,
        uint24 gamma
    ) public pure {
        // NOTE: Important assumption here, since this value only changes when ticks are crossed!
        vm.assume(secondsPerLiquidityX128 != 0);

        gamma = gamma % 1e6;

        uint256 feeGrowthGlobalBX128;
        unchecked {
            feeGrowthGlobalBX128 = feeGrowthGlobalAX128 + feeGrowthGlobalDeltaX128;
        }

        Volatility.computeRevenueGamma(
            feeGrowthGlobalAX128,
            feeGrowthGlobalBX128,
            secondsPerLiquidityX128,
            secondsAgo,
            gamma
        );
    }

    function test_noRevert_estimate(
        uint32 feeGrowthSampleAge,
        uint256 feeGrowthGlobalA0X128,
        uint256 feeGrowthGlobalA1X128,
        uint224 feeGrowthGlobalDelta0X128,
        uint224 feeGrowthGlobalDelta1X128,
        uint48 gammas,
        int24 tick,
        int24 arithmeticMeanTick,
        uint160 secondsPerLiquidityX128,
        uint32 oracleLookback,
        uint128 tickLiquidity,
        uint32 scale
    ) public view {
        scale = uint32(bound(scale, 1 minutes, 2 days));
        oracleLookback = uint32(bound(oracleLookback, 15 seconds, 1 days));

        Volatility.PoolMetadata memory metadata = Volatility.PoolMetadata(
            uint24(gammas % (1 << 24)),
            uint24(gammas >> 24),
            0
        );
        {
            // reusing randomness to avoid stack-too-deep
            uint256 tier = feeGrowthSampleAge % 4;
            if (tier == 0) metadata.tickSpacing = 1;
            else if (tier == 1) metadata.tickSpacing = 10;
            else if (tier == 2) metadata.tickSpacing = 60;
            else if (tier == 3) metadata.tickSpacing = 100;
        }

        tick = boundTick(tick, metadata.tickSpacing);
        arithmeticMeanTick = boundTick(arithmeticMeanTick, metadata.tickSpacing);
        Oracle.PoolData memory data = Oracle.PoolData(
            TickMath.getSqrtRatioAtTick(tick),
            tick,
            TickMath.getSqrtRatioAtTick(arithmeticMeanTick),
            secondsPerLiquidityX128,
            oracleLookback,
            tickLiquidity
        );

        Volatility.FeeGrowthGlobals memory a;
        Volatility.FeeGrowthGlobals memory b;
        unchecked {
            a.feeGrowthGlobal0X128 = feeGrowthGlobalA0X128;
            a.feeGrowthGlobal1X128 = feeGrowthGlobalA1X128;
            a.timestamp = 0;
            b.feeGrowthGlobal0X128 = feeGrowthGlobalA0X128 + feeGrowthGlobalDelta0X128;
            b.feeGrowthGlobal1X128 = feeGrowthGlobalA1X128 + feeGrowthGlobalDelta1X128;
            b.timestamp = feeGrowthSampleAge;
        }

        Volatility.estimate(metadata, data, a, b, scale);
    }

    function boundTick(int24 tick, int24 tickSpacing) private pure returns (int24) {
        if (tick < TickMath.MIN_TICK + tickSpacing) return TickMath.MIN_TICK + tickSpacing;
        else if (tick > TickMath.MAX_TICK - tickSpacing) return TickMath.MAX_TICK - tickSpacing;
        else return tick;
    }
}
