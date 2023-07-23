// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import {BalanceSheet, TickMath, mulDiv96} from "src/libraries/BalanceSheet.sol";

import {FixedPointMathLib as SoladyMath} from "solady/utils/FixedPointMathLib.sol";

contract BalanceSheetTest is Test {
    function setUp() public {}

    /// @dev See https://www.desmos.com/calculator/hrrpjqy4t1
    function test_spec_computeProbePrices() public {
        bool isSus;

        (, , isSus) = BalanceSheet.computeProbePrices(0, 0.00e18, 5, 87);
        assertFalse(isSus, "0.00 false");
        (, , isSus) = BalanceSheet.computeProbePrices(0, 0.00e18, 5, 88);
        assertTrue(isSus, "0.00 true");

        (, , isSus) = BalanceSheet.computeProbePrices(0, 0.01e18, 5, 87);
        assertFalse(isSus, "0.01 false");
        (, , isSus) = BalanceSheet.computeProbePrices(0, 0.01e18, 5, 88);
        assertTrue(isSus, "0.01 true");

        (, , isSus) = BalanceSheet.computeProbePrices(0, 0.02e18, 5, 132);
        assertFalse(isSus, "0.02 false");
        (, , isSus) = BalanceSheet.computeProbePrices(0, 0.02e18, 5, 133);
        assertTrue(isSus, "0.02 true");

        (, , isSus) = BalanceSheet.computeProbePrices(0, 0.03e18, 5, 180);
        assertFalse(isSus, "0.03 false");
        (, , isSus) = BalanceSheet.computeProbePrices(0, 0.03e18, 5, 181);
        assertTrue(isSus, "0.03 true");

        (, , isSus) = BalanceSheet.computeProbePrices(0, 0.04e18, 5, 230);
        assertFalse(isSus, "0.04 false");
        (, , isSus) = BalanceSheet.computeProbePrices(0, 0.04e18, 5, 231);
        assertTrue(isSus, "0.04 true");

        (, , isSus) = BalanceSheet.computeProbePrices(0, 0.05e18, 5, 284);
        assertFalse(isSus, "0.05 false");
        (, , isSus) = BalanceSheet.computeProbePrices(0, 0.05e18, 5, 285);
        assertTrue(isSus, "0.05 true");

        (, , isSus) = BalanceSheet.computeProbePrices(0, 0.06e18, 5, 341);
        assertFalse(isSus, "0.06 false");
        (, , isSus) = BalanceSheet.computeProbePrices(0, 0.06e18, 5, 342);
        assertTrue(isSus, "0.06 true");

        (, , isSus) = BalanceSheet.computeProbePrices(0, 0.07e18, 5, 403);
        assertFalse(isSus, "0.07 false");
        (, , isSus) = BalanceSheet.computeProbePrices(0, 0.07e18, 5, 404);
        assertTrue(isSus, "0.07 true");

        (, , isSus) = BalanceSheet.computeProbePrices(0, 0.08e18, 5, 470);
        assertFalse(isSus, "0.08 false");
        (, , isSus) = BalanceSheet.computeProbePrices(0, 0.08e18, 5, 471);
        assertTrue(isSus, "0.08 true");

        (, , isSus) = BalanceSheet.computeProbePrices(0, 0.09e18, 5, 542);
        assertFalse(isSus, "0.09 false");
        (, , isSus) = BalanceSheet.computeProbePrices(0, 0.09e18, 5, 543);
        assertTrue(isSus, "0.09 true");

        (, , isSus) = BalanceSheet.computeProbePrices(0, 0.10e18, 5, 622);
        assertFalse(isSus, "0.10 false");
        (, , isSus) = BalanceSheet.computeProbePrices(0, 0.10e18, 5, 623);
        assertTrue(isSus, "0.10 true");

        (, , isSus) = BalanceSheet.computeProbePrices(0, 0.11e18, 5, 710);
        assertFalse(isSus, "0.11 false");
        (, , isSus) = BalanceSheet.computeProbePrices(0, 0.11e18, 5, 711);
        assertTrue(isSus, "0.11 true");

        (, , isSus) = BalanceSheet.computeProbePrices(0, 0.12e18, 5, 808);
        assertFalse(isSus, "0.12 false");
        (, , isSus) = BalanceSheet.computeProbePrices(0, 0.12e18, 5, 809);
        assertTrue(isSus, "0.12 true");

        (, , isSus) = BalanceSheet.computeProbePrices(0, 0.13e18, 5, 919);
        assertFalse(isSus, "0.13 false");
        (, , isSus) = BalanceSheet.computeProbePrices(0, 0.13e18, 5, 920);
        assertTrue(isSus, "0.13 true");

        (, , isSus) = BalanceSheet.computeProbePrices(0, 0.14e18, 5, 1048);
        assertFalse(isSus, "0.14 false");
        (, , isSus) = BalanceSheet.computeProbePrices(0, 0.14e18, 5, 1049);
        assertTrue(isSus, "0.14 true");

        (, , isSus) = BalanceSheet.computeProbePrices(0, 0.15e18, 5, 1199);
        assertFalse(isSus, "0.15 false");
        (, , isSus) = BalanceSheet.computeProbePrices(0, 0.15e18, 5, 1200);
        assertTrue(isSus, "0.15 true");

        (, , isSus) = BalanceSheet.computeProbePrices(0, 0.16e18, 5, 1385);
        assertFalse(isSus, "0.16 false");
        (, , isSus) = BalanceSheet.computeProbePrices(0, 0.16e18, 5, 1386);
        assertTrue(isSus, "0.16 true");

        (, , isSus) = BalanceSheet.computeProbePrices(0, 0.17e18, 5, 1625);
        assertFalse(isSus, "0.17 false");
        (, , isSus) = BalanceSheet.computeProbePrices(0, 0.17e18, 5, 1626);
        assertTrue(isSus, "0.17 true");

        (, , isSus) = BalanceSheet.computeProbePrices(0, 0.18e18, 5, 1963);
        assertFalse(isSus, "0.18 false");
        (, , isSus) = BalanceSheet.computeProbePrices(0, 0.18e18, 5, 1964);
        assertTrue(isSus, "0.18 true");

        (, , isSus) = BalanceSheet.computeProbePrices(0, 0.19e18, 5, 1963);
        assertFalse(isSus, "0.19 false");
        (, , isSus) = BalanceSheet.computeProbePrices(0, 0.19e18, 5, 1964);
        assertTrue(isSus, "0.19 true");
    }

    function test_computeProbePrices(uint160 sqrtMeanPriceX96, uint256 sigma) public {
        // TODO: These bounds should be enforced somewhere. Related to https://github.com/aloelabs/aloe-ii/issues/66
        sqrtMeanPriceX96 = uint160(bound(sqrtMeanPriceX96, (1 << 56), TickMath.MAX_SQRT_RATIO / 1.0863e9));
        (uint256 a, uint256 b, ) = BalanceSheet.computeProbePrices(sqrtMeanPriceX96, sigma, 5, 0);

        uint256 price = mulDiv96(sqrtMeanPriceX96, sqrtMeanPriceX96);
        a = mulDiv96(a, a);
        b = mulDiv96(b, b);

        if (sigma < 0.01e18) sigma = 0.01e18;
        else if (sigma > 0.18e18) sigma = 0.18e18;

        assertApproxEqRel(a, price * (1e18 - 5 * sigma) / 1e18, 0.0001e18);
        assertApproxEqRel(b, price * (1e18 + 5 * sigma) / 1e18, 0.0001e18);
    }
}
