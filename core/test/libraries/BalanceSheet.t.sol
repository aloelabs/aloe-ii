// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

import "forge-std/Test.sol";

import {FixedPointMathLib as SoladyMath} from "solady/utils/FixedPointMathLib.sol";

import {
    DEFAULT_N_SIGMA,
    CONSTRAINT_N_SIGMA_MIN,
    CONSTRAINT_N_SIGMA_MAX,
    CONSTRAINT_MANIPULATION_THRESHOLD_DIVISOR_MIN,
    CONSTRAINT_MANIPULATION_THRESHOLD_DIVISOR_MAX,
    LIQUIDATION_GRACE_PERIOD,
    LTV_MIN,
    PROBE_SQRT_SCALER_MIN,
    PROBE_SQRT_SCALER_MAX,
    IV_COLD_START
} from "src/libraries/constants/Constants.sol";
import {BalanceSheet, AuctionAmounts, Assets, Prices, TickMath, square} from "src/libraries/BalanceSheet.sol";
import {LiquidityAmounts} from "src/libraries/LiquidityAmounts.sol";

contract LibraryWrapper {
    function auctionTime(uint256 warnTime) external view returns (uint256) {
        return BalanceSheet.auctionTime(warnTime);
    }

    function computeAuctionAmounts(
        uint160 sqrtPriceX96,
        uint256 assets0,
        uint256 assets1,
        uint256 liabilities0,
        uint256 liabilities1,
        uint256 t,
        uint256 closeFactor
    ) external pure returns (AuctionAmounts memory) {
        return
            BalanceSheet.computeAuctionAmounts(
                sqrtPriceX96,
                assets0,
                assets1,
                liabilities0,
                liabilities1,
                t,
                closeFactor
            );
    }

    function isHealthy(
        Prices memory prices,
        Assets memory mem,
        uint256 liabilities0,
        uint256 liabilities1
    ) external pure returns (bool) {
        return BalanceSheet.isHealthy(prices, mem, liabilities0, liabilities1);
    }

    function isHealthy(
        Prices memory prices,
        uint256 assets0,
        uint256 assets1,
        uint256 liabilities0,
        uint256 liabilities1
    ) external pure returns (bool) {
        return BalanceSheet.isHealthy(prices, assets0, assets1, liabilities0, liabilities1);
    }

    function isSolvent(
        uint160 sqrtPriceX96,
        uint256 assets0,
        uint256 assets1,
        uint256 liabilities0,
        uint256 liabilities1
    ) external pure returns (bool) {
        return BalanceSheet.isSolvent(sqrtPriceX96, assets0, assets1, liabilities0, liabilities1);
    }
}

contract BalanceSheetTest is Test {
    LibraryWrapper wrapper;

    function setUp() public {
        wrapper = new LibraryWrapper();
    }

    // TODO: (for Borrower) test that liquidate() fails if the liquidator doesn't pay back at least in0 or in1 (for all close factors)

    function test_computeAuctionAmountsBoundaries(
        uint160 sqrtPriceX96,
        uint104 assets0,
        uint104 assets1,
        uint104 liabilities0,
        uint104 liabilities1,
        uint256 warnTime,
        uint256 closeFactor
    ) external {
        vm.assume(assets0 > 0 && assets1 > 0);
        vm.warp(10000000000);

        warnTime = bound(warnTime, block.timestamp - LIQUIDATION_GRACE_PERIOD + 1, block.timestamp);
        closeFactor = bound(closeFactor, 0, 10000);

        vm.expectRevert(bytes("Aloe: grace"));
        wrapper.auctionTime(warnTime);

        warnTime = block.timestamp - 7 days;
        AuctionAmounts memory amounts = BalanceSheet.computeAuctionAmounts(
            sqrtPriceX96,
            assets0,
            assets1,
            liabilities0,
            liabilities1,
            BalanceSheet.auctionTime(warnTime),
            closeFactor
        );
        assertEq(amounts.out0, (assets0 * closeFactor) / 10_000);
        assertEq(amounts.out1, (assets1 * closeFactor) / 10_000);
    }

    function test_computeAuctionAmountsProportionality(
        uint160 sqrtPriceX96,
        uint104 assets0,
        uint104 assets1,
        uint104 liabilities0,
        uint104 liabilities1,
        uint256 warnTime,
        uint256 closeFactor
    ) external {
        assets0 = uint104(bound(assets0, 1 << 32, type(uint104).max));
        assets1 = uint104(bound(assets1, 1 << 32, type(uint104).max));
        vm.assume(assets0 > 0 && assets1 > 0);
        vm.warp(10000000000);

        warnTime = bound(warnTime, block.timestamp - 7 days, block.timestamp - LIQUIDATION_GRACE_PERIOD);
        closeFactor = bound(closeFactor, 0, 10000);

        AuctionAmounts memory amounts = BalanceSheet.computeAuctionAmounts(
            sqrtPriceX96,
            assets0,
            assets1,
            liabilities0,
            liabilities1,
            BalanceSheet.auctionTime(warnTime),
            closeFactor
        );

        uint256 denom = assets1 + SoladyMath.fullMulDiv(assets0, square(sqrtPriceX96), 1 << 128);
        if (denom == 0) return;
        uint256 oldRatio = (1e18 * uint256(assets1)) / denom;

        console2.log(assets0, assets1);

        assets0 -= uint104(amounts.out0);
        assets1 -= uint104(amounts.out1);

        console2.log(assets0, assets1);

        denom = assets1 + SoladyMath.fullMulDiv(assets0, square(sqrtPriceX96), 1 << 128);
        if (denom == 0) return;
        uint256 newRatio = (1e18 * uint256(assets1)) / denom;

        assertApproxEqAbs(newRatio, oldRatio, 0.0001e18);
    }

    function test_spec_computeAuctionAmounts() external {
        vm.warp(10000000000);

        AuctionAmounts memory amounts;

        amounts = BalanceSheet.computeAuctionAmounts(1 << 96, 1e18, 0, 1e18, 0, 7 days - 5 minutes, 0);
        assertEq(amounts.out0, 0);
        assertEq(amounts.out1, 0);
        assertEq(amounts.repay0, 0);
        assertEq(amounts.repay1, 0);

        amounts = BalanceSheet.computeAuctionAmounts(1 << 96, 1e18, 0, 1e18, 0, 7 days - 5 minutes, 10000);
        assertEq(amounts.out0, 1e18);
        assertEq(amounts.out1, 0);
        assertEq(amounts.repay0, 1e18);
        assertEq(amounts.repay1, 0);

        amounts = BalanceSheet.computeAuctionAmounts(1 << 96, 1e18, 2e18, 0.5e18, 0.5e18, 3 minutes, 10000);
        assertEq(amounts.out0, 335734917596000000);
        assertEq(amounts.out1, 671469835192000000);
        assertEq(amounts.repay0, 0.5e18);
        assertEq(amounts.repay1, 0.5e18);

        amounts = BalanceSheet.computeAuctionAmounts(1 << 96, 1e18, 2e18, 0.5e18, 0.5e18, 55 minutes, 10000);
        assertEq(amounts.out0, 371792510098000000);
        assertEq(amounts.out1, 743585020196000000);
    }

    function test_healthConcavity(
        uint128 fixed0,
        uint128 fixed1,
        uint128 liabilities0,
        uint128 liabilities1,
        uint160[6] memory p,
        uint96[2] memory liquidities
    ) public {
        vm.assume(p[0] > 0 && p[1] > 0);

        p[0] = uint160(bound(p[0], TickMath.MIN_SQRT_RATIO + 1, TickMath.MAX_SQRT_RATIO - 1));
        p[1] = uint160(bound(p[1], p[0], TickMath.MAX_SQRT_RATIO - 1));

        p[2] = uint160(bound(p[2], p[0], p[1]));
        p[3] = uint160(bound(p[3], p[2], TickMath.MAX_SQRT_RATIO - 1));

        p[4] = uint160(bound(p[4], TickMath.MIN_SQRT_RATIO + 1, p[0]));
        p[5] = uint160(bound(p[5], p[4], p[1]));

        uint256 i;
        while (i < 32) {
            Assets memory assets = _getAssets(fixed0, fixed1, p, liquidities);

            try wrapper.isHealthy(Prices(p[0], p[1], 0), assets, liabilities0, liabilities1) returns (bool isHealthy) {
                if (isHealthy) {
                    i = 0;
                    while (p[0] < p[1] && i < 256) {
                        isHealthy = wrapper.isHealthy(Prices(p[0], p[1], 0), assets, liabilities0, liabilities1);
                        assertTrue(isHealthy);

                        p[0] = uint160(SoladyMath.min(uint256(p[0]) * 2, type(uint160).max));
                        p[1] = uint160(uint256(p[1]) / 2);

                        i++;
                    }
                    console2.log("Runs:", i);
                    break;
                }
            } catch {
                vm.assume(false);
                break;
            }

            fixed0 = uint128(uint256(fixed0) * 2);
            fixed1 = uint128(uint256(fixed1) * 2);
            liabilities0 = liabilities0 / 2;
            liabilities1 = liabilities0 / 2;

            i++;
        }
    }

    function _getAssets(
        uint256 fixed0,
        uint256 fixed1,
        uint160[6] memory p,
        uint96[2] memory liquidities
    ) private pure returns (Assets memory assets) {
        assets.amount0AtA = assets.amount0AtB = fixed0;
        assets.amount1AtA = assets.amount1AtB = fixed1;

        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(p[0], p[2], p[3], liquidities[0]);
        assets.amount0AtA += amount0;
        assets.amount1AtA += amount1;
        (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(p[1], p[2], p[3], liquidities[0]);
        assets.amount0AtB += amount0;
        assets.amount1AtB += amount1;

        (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(p[0], p[4], p[5], liquidities[1]);
        assets.amount0AtA += amount0;
        assets.amount1AtA += amount1;
        (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(p[1], p[4], p[5], liquidities[1]);
        assets.amount0AtB += amount0;
        assets.amount1AtB += amount1;
    }

    function test_fuzz_alwaysHealthyWhenLiabilitiesAre0(
        uint128 amount0AtA,
        uint128 amount1AtA,
        uint128 amount0AtB,
        uint128 amount1AtB,
        uint160 a,
        uint160 b,
        uint160 c
    ) public {
        Assets memory assets = Assets(amount0AtA, amount1AtA, amount0AtB, amount1AtB);
        Prices memory prices = Prices(a, b, c);

        try wrapper.isHealthy(prices, assets, 0, 0) returns (bool isHealthy) {
            assertTrue(isHealthy);
        } catch {
            vm.expectRevert(0xae47f702);
            wrapper.isHealthy(prices, assets, 0, 0);
        }

        try wrapper.isHealthy(prices, amount0AtA, amount1AtA, 0, 0) returns (bool isHealthy) {
            assertTrue(isHealthy);
        } catch {
            vm.expectRevert(0xae47f702);
            wrapper.isHealthy(prices, amount0AtA, amount1AtA, 0, 0);
        }
    }

    function test_fuzz_alwaysSolventWhenLiabilitiesAre0(uint160 sqrtPriceX96, uint128 amount0, uint128 amount1) public {
        try wrapper.isSolvent(sqrtPriceX96, amount0, amount1, 0, 0) returns (bool isHealthy) {
            assertTrue(isHealthy);
        } catch {
            vm.expectRevert(0xae47f702);
            wrapper.isSolvent(sqrtPriceX96, amount0, amount1, 0, 0);
        }
    }

    function test_fuzz_auctionCurve(uint256 t) external {
        t = bound(t, 1, 7 days - 5 minutes - 1);
        uint256 f = BalanceSheet.auctionCurve(t);
        assertGt(f, 0);
        assertLe(f, 103568.839061681797e12);
    }

    function test_spec_auctionCurveA() public {
        assertEq(BalanceSheet.auctionCurve(0 seconds), 0);
        assertEq(BalanceSheet.auctionCurve(12 seconds), 0.415240559229e12);
        assertEq(BalanceSheet.auctionCurve(24 seconds), 0.606056042223e12);
        assertEq(BalanceSheet.auctionCurve(36 seconds), 0.715682709971e12);
        assertEq(BalanceSheet.auctionCurve(48 seconds), 0.786848126590e12);
        assertEq(BalanceSheet.auctionCurve(60 seconds), 0.836772585073e12);
        assertEq(BalanceSheet.auctionCurve(2 minutes), 0.958397119151e12);
        assertEq(BalanceSheet.auctionCurve(168 seconds), 0.999929300389e12);
        assertEq(BalanceSheet.auctionCurve(3 minutes), 1.007204752788e12);
        assertEq(BalanceSheet.auctionCurve(4 minutes), 1.033528701917e12);
        assertEq(BalanceSheet.auctionCurve(5 minutes), 1.050000037841e12);
        assertEq(BalanceSheet.auctionCurve(10 minutes), 1.084617392593e12);
        assertEq(BalanceSheet.auctionCurve(710 seconds), 1.090202965242e12);
        assertEq(BalanceSheet.auctionCurve(15 minutes), 1.096723751201e12);
    }

    function test_spec_auctionCurveB() public {
        assertEq(BalanceSheet.auctionCurve(30 minutes), 1.109270590650e12);
        assertEq(BalanceSheet.auctionCurve(60 minutes), 1.116034555698e12);
        assertEq(BalanceSheet.auctionCurve(1 days), 1.149634653251e12);
        assertEq(BalanceSheet.auctionCurve(2 days), 1.189774687552e12);
        assertEq(BalanceSheet.auctionCurve(3 days), 1.249847696897e12);
        assertEq(BalanceSheet.auctionCurve(4 days), 1.349964268391e12);
        assertEq(BalanceSheet.auctionCurve(5 days), 1.550340596798e12);
        assertEq(BalanceSheet.auctionCurve(6 days), 2.152834947272e12);
        assertEq(BalanceSheet.auctionCurve(7 days - 5 minutes - 1), 103568.839061681797e12);
    }

    /// @dev See https://www.desmos.com/calculator/l7kp0j3kgl
    function test_spec_computeProbePrices() public {
        bool seemsLegit;

        (, , seemsLegit) = BalanceSheet.computeProbePrices(86, 0, 0.00e12, 50, 12);
        assertTrue(seemsLegit, "0.00 true");
        (, , seemsLegit) = BalanceSheet.computeProbePrices(87, 0, 0.00e12, 50, 12);
        assertFalse(seemsLegit, "0.00 false");

        (, , seemsLegit) = BalanceSheet.computeProbePrices(86, 0, 0.01e12, 50, 12);
        assertTrue(seemsLegit, "0.01 true");
        (, , seemsLegit) = BalanceSheet.computeProbePrices(87, 0, 0.01e12, 50, 12);
        assertFalse(seemsLegit, "0.01 false");

        (, , seemsLegit) = BalanceSheet.computeProbePrices(127, 0, 0.02e12, 50, 12);
        assertTrue(seemsLegit, "0.02 true");
        (, , seemsLegit) = BalanceSheet.computeProbePrices(128, 0, 0.02e12, 50, 12);
        assertFalse(seemsLegit, "0.02 false");

        (, , seemsLegit) = BalanceSheet.computeProbePrices(168, 0, 0.03e12, 50, 12);
        assertTrue(seemsLegit, "0.03 true");
        (, , seemsLegit) = BalanceSheet.computeProbePrices(169, 0, 0.03e12, 50, 12);
        assertFalse(seemsLegit, "0.03 false");

        (, , seemsLegit) = BalanceSheet.computeProbePrices(210, 0, 0.04e12, 50, 12);
        assertTrue(seemsLegit, "0.04 true");
        (, , seemsLegit) = BalanceSheet.computeProbePrices(211, 0, 0.04e12, 50, 12);
        assertFalse(seemsLegit, "0.04 false");

        (, , seemsLegit) = BalanceSheet.computeProbePrices(252, 0, 0.05e12, 50, 12);
        assertTrue(seemsLegit, "0.05 true");
        (, , seemsLegit) = BalanceSheet.computeProbePrices(253, 0, 0.05e12, 50, 12);
        assertFalse(seemsLegit, "0.05 false");

        (, , seemsLegit) = BalanceSheet.computeProbePrices(293, 0, 0.06e12, 50, 12);
        assertTrue(seemsLegit, "0.06 true");
        (, , seemsLegit) = BalanceSheet.computeProbePrices(294, 0, 0.06e12, 50, 12);
        assertFalse(seemsLegit, "0.06 false");

        (, , seemsLegit) = BalanceSheet.computeProbePrices(335, 0, 0.07e12, 50, 12);
        assertTrue(seemsLegit, "0.07 true");
        (, , seemsLegit) = BalanceSheet.computeProbePrices(336, 0, 0.07e12, 50, 12);
        assertFalse(seemsLegit, "0.07 false");

        (, , seemsLegit) = BalanceSheet.computeProbePrices(377, 0, 0.08e12, 50, 12);
        assertTrue(seemsLegit, "0.08 true");
        (, , seemsLegit) = BalanceSheet.computeProbePrices(378, 0, 0.08e12, 50, 12);
        assertFalse(seemsLegit, "0.08 false");

        (, , seemsLegit) = BalanceSheet.computeProbePrices(418, 0, 0.09e12, 50, 12);
        assertTrue(seemsLegit, "0.09 true");
        (, , seemsLegit) = BalanceSheet.computeProbePrices(419, 0, 0.09e12, 50, 12);
        assertFalse(seemsLegit, "0.09 false");

        (, , seemsLegit) = BalanceSheet.computeProbePrices(460, 0, 0.10e12, 50, 12);
        assertTrue(seemsLegit, "0.10 true");
        (, , seemsLegit) = BalanceSheet.computeProbePrices(461, 0, 0.10e12, 50, 12);
        assertFalse(seemsLegit, "0.10 false");

        (, , seemsLegit) = BalanceSheet.computeProbePrices(502, 0, 0.11e12, 50, 12);
        assertTrue(seemsLegit, "0.11 true");
        (, , seemsLegit) = BalanceSheet.computeProbePrices(503, 0, 0.11e12, 50, 12);
        assertFalse(seemsLegit, "0.11 false");

        (, , seemsLegit) = BalanceSheet.computeProbePrices(543, 0, 0.12e12, 50, 12);
        assertTrue(seemsLegit, "0.12 true");
        (, , seemsLegit) = BalanceSheet.computeProbePrices(544, 0, 0.12e12, 50, 12);
        assertFalse(seemsLegit, "0.12 false");

        (, , seemsLegit) = BalanceSheet.computeProbePrices(585, 0, 0.13e12, 50, 12);
        assertTrue(seemsLegit, "0.13 true");
        (, , seemsLegit) = BalanceSheet.computeProbePrices(586, 0, 0.13e12, 50, 12);
        assertFalse(seemsLegit, "0.13 false");

        (, , seemsLegit) = BalanceSheet.computeProbePrices(627, 0, 0.14e12, 50, 12);
        assertTrue(seemsLegit, "0.14 true");
        (, , seemsLegit) = BalanceSheet.computeProbePrices(628, 0, 0.14e12, 50, 12);
        assertFalse(seemsLegit, "0.14 false");

        (, , seemsLegit) = BalanceSheet.computeProbePrices(668, 0, 0.15e12, 50, 12);
        assertTrue(seemsLegit, "0.15 true");
        (, , seemsLegit) = BalanceSheet.computeProbePrices(669, 0, 0.15e12, 50, 12);
        assertFalse(seemsLegit, "0.15 false");

        (, , seemsLegit) = BalanceSheet.computeProbePrices(710, 0, 0.16e12, 50, 12);
        assertTrue(seemsLegit, "0.16 true");
        (, , seemsLegit) = BalanceSheet.computeProbePrices(711, 0, 0.16e12, 50, 12);
        assertFalse(seemsLegit, "0.16 false");

        (, , seemsLegit) = BalanceSheet.computeProbePrices(752, 0, 0.17e12, 50, 12);
        assertTrue(seemsLegit, "0.17 true");
        (, , seemsLegit) = BalanceSheet.computeProbePrices(753, 0, 0.17e12, 50, 12);
        assertFalse(seemsLegit, "0.17 false");

        (, , seemsLegit) = BalanceSheet.computeProbePrices(793, 0, 0.18e12, 50, 12);
        assertTrue(seemsLegit, "0.18 true");
        (, , seemsLegit) = BalanceSheet.computeProbePrices(794, 0, 0.18e12, 50, 12);
        assertFalse(seemsLegit, "0.18 false");

        (, , seemsLegit) = BalanceSheet.computeProbePrices(835, 0, 0.19e12, 50, 12);
        assertTrue(seemsLegit, "0.19 true");
        (, , seemsLegit) = BalanceSheet.computeProbePrices(836, 0, 0.19e12, 50, 12);
        assertFalse(seemsLegit, "0.19 false");
    }

    function test_fuzz_computeProbePrices(uint160 sqrtMeanPriceX96, uint256 iv, uint8 nSigma, uint8 mtd) public {
        // The lower bound is related to how precise our assertion is. For prices to be correct within 0.01%,
        // the sqrtPrice must be >= 2^40 (approximately). Calculations for that are here:
        // https://www.desmos.com/calculator/suq1f7yswt
        // The upper bound is due to the fact that the result (specifically `b`) must fit in uint160. The maximum
        // volatility factor is 1 + IV_AWARE_PROBE_PERCENT_MAX, so we divide `TickMath.MAX_SQRT_RATIO` by
        // sqrt(1e12 + IV_AWARE_PROBE_PERCENT_MAX)
        sqrtMeanPriceX96 = uint160(
            bound(sqrtMeanPriceX96, (1 << 41), (uint256(TickMath.MAX_SQRT_RATIO) * 1e12) / PROBE_SQRT_SCALER_MAX)
        );
        // This is valid because of the sqrt in `Volatility` library
        iv = bound(iv, 0, type(uint128).max);
        nSigma = uint8(bound(nSigma, CONSTRAINT_N_SIGMA_MIN, CONSTRAINT_N_SIGMA_MAX));
        mtd = uint8(
            bound(mtd, CONSTRAINT_MANIPULATION_THRESHOLD_DIVISOR_MIN, CONSTRAINT_MANIPULATION_THRESHOLD_DIVISOR_MAX)
        );

        (uint256 a, uint256 b, ) = BalanceSheet.computeProbePrices(0, sqrtMeanPriceX96, iv, nSigma, mtd);

        uint256 price = square(sqrtMeanPriceX96);
        a = square(uint160(a));
        b = square(uint160(b));

        uint256 delta = (nSigma * iv) / 10;
        uint256 scaler = delta >= 135305999368893 ? type(uint256).max : uint256(SoladyMath.expWad(int256(delta * 1e6)));
        scaler = SoladyMath.clamp(
            scaler,
            (PROBE_SQRT_SCALER_MIN * PROBE_SQRT_SCALER_MIN) / 1e6,
            (PROBE_SQRT_SCALER_MAX * PROBE_SQRT_SCALER_MAX) / 1e6
        );

        assertApproxEqRel(a, SoladyMath.fullMulDiv(price, 1e18, scaler), 0.0001e18);
        assertApproxEqRel(b, SoladyMath.fullMulDiv(price, scaler, 1e18), 0.0001e18);
    }

    /// @dev We have to override this because we need 512 bit multiplication in the assertion
    function assertApproxEqRel(
        uint256 a,
        uint256 b,
        uint256 maxPercentDelta // An 18 decimal fixed point number, where 1e18 == 100%
    ) internal override {
        if (b == 0) return assertEq(a, b); // If the expected is 0, actual must be too.

        uint256 percentDelta = _percentDelta(a, b);

        if (percentDelta > maxPercentDelta) {
            emit log("Error: a ~= b not satisfied [uint]");
            emit log_named_uint("    Expected", b);
            emit log_named_uint("      Actual", a);
            emit log_named_decimal_uint(" Max % Delta", maxPercentDelta, 18);
            emit log_named_decimal_uint("     % Delta", percentDelta, 18);
            fail();
        }
    }

    function _percentDelta(uint256 a, uint256 b) private pure returns (uint256) {
        uint256 absDelta = stdMath.delta(a, b);

        return SoladyMath.fullMulDivUp(absDelta, 1e18, b);
    }
}
