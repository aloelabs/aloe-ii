// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import {
    DEFAULT_N_SIGMA,
    CONSTRAINT_N_SIGMA_MIN,
    CONSTRAINT_N_SIGMA_MAX,
    LTV_MIN,
    PROBE_PERCENT_MIN,
    PROBE_PERCENT_MAX,
    IV_COLD_START
} from "src/libraries/constants/Constants.sol";
import {BalanceSheet, TickMath, square} from "src/libraries/BalanceSheet.sol";

import {FixedPointMathLib as SoladyMath} from "solady/utils/FixedPointMathLib.sol";

contract BalanceSheetTest is Test {
    function setUp() public {}

    /// @dev See https://www.desmos.com/calculator/hrrpjqy4t1
    function test_spec_computeProbePrices() public {
        bool isSus;

        (, , isSus) = BalanceSheet.computeProbePrices(0, 0.00e12, 50, 87);
        assertFalse(isSus, "0.00 false");
        (, , isSus) = BalanceSheet.computeProbePrices(0, 0.00e12, 50, 88);
        assertTrue(isSus, "0.00 true");

        (, , isSus) = BalanceSheet.computeProbePrices(0, 0.01e12, 50, 87);
        assertFalse(isSus, "0.01 false");
        (, , isSus) = BalanceSheet.computeProbePrices(0, 0.01e12, 50, 88);
        assertTrue(isSus, "0.01 true");

        (, , isSus) = BalanceSheet.computeProbePrices(0, 0.02e12, 50, 132);
        assertFalse(isSus, "0.02 false");
        (, , isSus) = BalanceSheet.computeProbePrices(0, 0.02e12, 50, 133);
        assertTrue(isSus, "0.02 true");

        (, , isSus) = BalanceSheet.computeProbePrices(0, 0.03e12, 50, 180);
        assertFalse(isSus, "0.03 false");
        (, , isSus) = BalanceSheet.computeProbePrices(0, 0.03e12, 50, 181);
        assertTrue(isSus, "0.03 true");

        (, , isSus) = BalanceSheet.computeProbePrices(0, 0.04e12, 50, 230);
        assertFalse(isSus, "0.04 false");
        (, , isSus) = BalanceSheet.computeProbePrices(0, 0.04e12, 50, 231);
        assertTrue(isSus, "0.04 true");

        (, , isSus) = BalanceSheet.computeProbePrices(0, 0.05e12, 50, 284);
        assertFalse(isSus, "0.05 false");
        (, , isSus) = BalanceSheet.computeProbePrices(0, 0.05e12, 50, 285);
        assertTrue(isSus, "0.05 true");

        (, , isSus) = BalanceSheet.computeProbePrices(0, 0.06e12, 50, 341);
        assertFalse(isSus, "0.06 false");
        (, , isSus) = BalanceSheet.computeProbePrices(0, 0.06e12, 50, 342);
        assertTrue(isSus, "0.06 true");

        (, , isSus) = BalanceSheet.computeProbePrices(0, 0.07e12, 50, 403);
        assertFalse(isSus, "0.07 false");
        (, , isSus) = BalanceSheet.computeProbePrices(0, 0.07e12, 50, 404);
        assertTrue(isSus, "0.07 true");

        (, , isSus) = BalanceSheet.computeProbePrices(0, 0.08e12, 50, 470);
        assertFalse(isSus, "0.08 false");
        (, , isSus) = BalanceSheet.computeProbePrices(0, 0.08e12, 50, 471);
        assertTrue(isSus, "0.08 true");

        (, , isSus) = BalanceSheet.computeProbePrices(0, 0.09e12, 50, 542);
        assertFalse(isSus, "0.09 false");
        (, , isSus) = BalanceSheet.computeProbePrices(0, 0.09e12, 50, 543);
        assertTrue(isSus, "0.09 true");

        (, , isSus) = BalanceSheet.computeProbePrices(0, 0.10e12, 50, 622);
        assertFalse(isSus, "0.10 false");
        (, , isSus) = BalanceSheet.computeProbePrices(0, 0.10e12, 50, 623);
        assertTrue(isSus, "0.10 true");

        (, , isSus) = BalanceSheet.computeProbePrices(0, 0.11e12, 50, 710);
        assertFalse(isSus, "0.11 false");
        (, , isSus) = BalanceSheet.computeProbePrices(0, 0.11e12, 50, 711);
        assertTrue(isSus, "0.11 true");

        (, , isSus) = BalanceSheet.computeProbePrices(0, 0.12e12, 50, 808);
        assertFalse(isSus, "0.12 false");
        (, , isSus) = BalanceSheet.computeProbePrices(0, 0.12e12, 50, 809);
        assertTrue(isSus, "0.12 true");

        (, , isSus) = BalanceSheet.computeProbePrices(0, 0.13e12, 50, 919);
        assertFalse(isSus, "0.13 false");
        (, , isSus) = BalanceSheet.computeProbePrices(0, 0.13e12, 50, 920);
        assertTrue(isSus, "0.13 true");

        (, , isSus) = BalanceSheet.computeProbePrices(0, 0.14e12, 50, 1048);
        assertFalse(isSus, "0.14 false");
        (, , isSus) = BalanceSheet.computeProbePrices(0, 0.14e12, 50, 1049);
        assertTrue(isSus, "0.14 true");

        (, , isSus) = BalanceSheet.computeProbePrices(0, 0.15e12, 50, 1199);
        assertFalse(isSus, "0.15 false");
        (, , isSus) = BalanceSheet.computeProbePrices(0, 0.15e12, 50, 1200);
        assertTrue(isSus, "0.15 true");

        (, , isSus) = BalanceSheet.computeProbePrices(0, 0.16e12, 50, 1385);
        assertFalse(isSus, "0.16 false");
        (, , isSus) = BalanceSheet.computeProbePrices(0, 0.16e12, 50, 1386);
        assertTrue(isSus, "0.16 true");

        (, , isSus) = BalanceSheet.computeProbePrices(0, 0.17e12, 50, 1625);
        assertFalse(isSus, "0.17 false");
        (, , isSus) = BalanceSheet.computeProbePrices(0, 0.17e12, 50, 1626);
        assertTrue(isSus, "0.17 true");

        (, , isSus) = BalanceSheet.computeProbePrices(0, 0.18e12, 50, 1918);
        assertFalse(isSus, "0.18 false");
        (, , isSus) = BalanceSheet.computeProbePrices(0, 0.18e12, 50, 1919);
        assertTrue(isSus, "0.18 true");

        (, , isSus) = BalanceSheet.computeProbePrices(0, 0.19e12, 50, 1918);
        assertFalse(isSus, "0.19 false");
        (, , isSus) = BalanceSheet.computeProbePrices(0, 0.19e12, 50, 1919);
        assertTrue(isSus, "0.19 true");

        (, , isSus) = BalanceSheet.computeProbePrices(0, IV_COLD_START, 50, 1918);
        assertFalse(isSus, "cold start false");
        (, , isSus) = BalanceSheet.computeProbePrices(0, IV_COLD_START, 50, 1919);
        assertTrue(isSus, "cold start true");
    }

    function test_computeProbePrices(uint160 sqrtMeanPriceX96, uint256 iv, uint256 nSigma) public {
        // The lower bound is related to how precise our assertion is. For prices to be correct within 0.01%,
        // the sqrtPrice must be >= 2^40 (approximately). Calculations for that are here:
        // https://www.desmos.com/calculator/gfbkcnt0vs
        // The upper bound is due to the fact that the result (specifically `b`) must fit in uint160. The maximum
        // volatility factor is 1 + IV_AWARE_PROBE_PERCENT_MAX, so we divide `TickMath.MAX_SQRT_RATIO` by
        // sqrt(1e12 + IV_AWARE_PROBE_PERCENT_MAX)
        sqrtMeanPriceX96 = uint160(
            bound(sqrtMeanPriceX96, (1 << 40), (uint256(TickMath.MAX_SQRT_RATIO) * 1e6) / 1376408)
        );
        nSigma = uint160(bound(nSigma, CONSTRAINT_N_SIGMA_MIN, CONSTRAINT_N_SIGMA_MAX));

        (uint256 a, uint256 b, ) = BalanceSheet.computeProbePrices(sqrtMeanPriceX96, iv, nSigma, 0);

        uint256 price = square(sqrtMeanPriceX96);
        a = square(uint160(a));
        b = square(uint160(b));

        if (iv < PROBE_PERCENT_MIN * 10 / nSigma) iv = PROBE_PERCENT_MIN * 10 / nSigma;
        else if (iv > PROBE_PERCENT_MAX * 10 / nSigma) iv = PROBE_PERCENT_MAX * 10 / nSigma;

        assertApproxEqRel(a, SoladyMath.fullMulDiv(price, 1e12 - (nSigma * iv) / 10, 1e12), 0.0001e18);
        assertApproxEqRel(b, SoladyMath.fullMulDiv(price, 1e12 + (nSigma * iv) / 10, 1e12), 0.0001e18);
    }

    function test_constants() public {
        // Just checking that things are reasonable
        assertEqDecimal(PROBE_PERCENT_MIN, 50500000000, 12);
        assertEqDecimal(PROBE_PERCENT_MAX, 894500000000, 12);

        // Necessary for iv scaling not to overflow
        assertLt(PROBE_PERCENT_MIN, 1 << 128);
        assertLt(PROBE_PERCENT_MAX, 1 << 128);

        // Necessary for collateral factor computation to work
        assertGt(LTV_MIN, TickMath.MIN_SQRT_RATIO);
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
