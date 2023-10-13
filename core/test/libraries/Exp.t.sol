// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import {FixedPointMathLib as SoladyMath} from "solady/utils/FixedPointMathLib.sol";

import {exp1e12} from "src/libraries/Exp.sol";

contract ExpTest is Test {
    function setUp() public {}

    function test_comparative(int256 input) external {
        input = bound(input, -28324168296488 + 1, 135305999368893 - 1);

        int256 expected = SoladyMath.expWad(input * 1e6) / 1e6;
        int256 actual = exp1e12(input);

        // Equal out to the first 18 sig figs
        assertApproxEqRel(actual, expected, 1);
    }

    function test_bounds() external {
        assertEq(exp1e12(-28324168296488 + 0), 0);
        assertEq(exp1e12(-28324168296488 + 1), 0);
        assertEq(
            exp1e12(149121509926857 - 1),
            57896044618570924033038090251570834612273709678020728724140821450240425059140
        );
        assertEq(exp1e12(149121509926857 - 0), type(int256).max);
        assertEq(exp1e12(type(int256).max), type(int256).max);
    }

    function test_positive(int256 input) external {
        input = bound(input, 0, 135305999368893 - 1);
        assertGt(exp1e12(input), 0);
    }

    function test_specA() external {
        assertEq(exp1e12(0.00e12), 1.000000000000e12);
        assertEq(exp1e12(0.01e12), 1.010050167084e12);
        assertEq(exp1e12(0.02e12), 1.020201340026e12);
        assertEq(exp1e12(0.03e12), 1.030454533953e12);
        assertEq(exp1e12(0.04e12), 1.040810774192e12);
        assertEq(exp1e12(0.05e12), 1.051271096376e12);
        assertEq(exp1e12(0.06e12), 1.061836546545e12);
        assertEq(exp1e12(0.07e12), 1.072508181254e12);
        assertEq(exp1e12(0.08e12), 1.083287067674e12);
        assertEq(exp1e12(0.09e12), 1.094174283705e12);
        assertEq(exp1e12(0.10e12), 1.105170918075e12);
    }

    function test_specB() external {
        assertEq(exp1e12(0.11e12), 1.116278070458e12);
        assertEq(exp1e12(0.12e12), 1.127496851579e12);
        assertEq(exp1e12(0.13e12), 1.138828383324e12);
        assertEq(exp1e12(0.14e12), 1.150273798857e12);
        assertEq(exp1e12(0.15e12), 1.161834242728e12);
        assertEq(exp1e12(0.16e12), 1.173510870991e12);
        assertEq(exp1e12(0.17e12), 1.185304851320e12);
        assertEq(exp1e12(0.18e12), 1.197217363121e12);
        assertEq(exp1e12(0.19e12), 1.209249597657e12);
        assertEq(exp1e12(0.20e12), 1.221402758160e12);
    }

    function test_specC() external {
        assertEq(exp1e12(0.30e12), 1.349858807576e12);
        assertEq(exp1e12(0.40e12), 1.491824697641e12);
        assertEq(exp1e12(0.50e12), 1.648721270700e12);
        assertEq(exp1e12(0.60e12), 1.822118800390e12);
        assertEq(exp1e12(0.70e12), 2.013752707470e12);
        assertEq(exp1e12(0.80e12), 2.225540928492e12);
        assertEq(exp1e12(0.90e12), 2.459603111156e12);
        assertEq(exp1e12(1.00e12), 2.718281828459e12);
    }
}
