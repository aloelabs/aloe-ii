// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import {
    DEFAULT_N_SIGMA,
    CONSTRAINT_N_SIGMA_MIN,
    CONSTRAINT_N_SIGMA_MAX,
    CONSTRAINT_MANIPULATION_THRESHOLD_DIVISOR_MIN,
    CONSTRAINT_MANIPULATION_THRESHOLD_DIVISOR_MAX,
    LTV_MIN,
    PROBE_SQRT_SCALER_MIN,
    PROBE_SQRT_SCALER_MAX,
    IV_COLD_START
} from "src/libraries/constants/Constants.sol";
import {BalanceSheet, Assets, Prices, TickMath, square} from "src/libraries/BalanceSheet.sol";

import {FixedPointMathLib as SoladyMath} from "solady/utils/FixedPointMathLib.sol";

contract LibraryWrapper {
    function isHealthy(
        Prices memory prices,
        Assets memory mem,
        uint256 liabilities0,
        uint256 liabilities1
    ) external pure returns (bool) {
        return BalanceSheet.isHealthy(prices, mem, liabilities0, liabilities1);
    }
}

contract BalanceSheetTest is Test {
    function setUp() public {}

    function test_fuzz_alwaysHealthyWhenLiabilitiesAre0(
        uint128 fixed0,
        uint128 fixed1,
        uint128 fluid1A,
        uint128 fluid1B,
        uint128 fluid0C,
        uint128 fluid1C,
        uint160 a,
        uint160 b,
        uint160 c
    ) public {
        Assets memory assets = Assets(fixed0, fixed1, fluid1A, fluid1B, fluid0C, fluid1C);
        Prices memory prices = Prices(a, b, c);

        LibraryWrapper wrapper = new LibraryWrapper();
        try wrapper.isHealthy(prices, assets, 0, 0) returns (bool isHealthy) {
            assertTrue(isHealthy);
        } catch {
            vm.expectRevert(stdError.arithmeticError);
            wrapper.isHealthy(prices, assets, 0, 0);
        }
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
