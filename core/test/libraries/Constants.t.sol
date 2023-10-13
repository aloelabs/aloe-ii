// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import "src/libraries/constants/Constants.sol";
import {TickMath} from "src/libraries/TickMath.sol";

contract ConstantsTest is Test {
    function setUp() public {}

    function test_spec() external {
        assertEq(LTV_NUMERATOR, 947867298578199052132701421800947867);
        assertEq(LTV_MIN, 0.100000000000e12);
        assertEq(LTV_MAX, 0.900000000001e12);

        // finding LTV and applying getTickAtSqrtRatio
        assertGt(LTV_NUMERATOR / (PROBE_SQRT_SCALER_MAX * PROBE_SQRT_SCALER_MAX), TickMath.MIN_SQRT_RATIO);
        assertLt(LTV_NUMERATOR / (PROBE_SQRT_SCALER_MIN * PROBE_SQRT_SCALER_MIN), TickMath.MAX_SQRT_RATIO);
        assertGt(LTV_MIN, TickMath.MIN_SQRT_RATIO);
        assertLt(LTV_MAX, TickMath.MAX_SQRT_RATIO);

        // manipulation threshold subtraction and casting
        assertGe(-TickMath.getTickAtSqrtRatio(uint160(LTV_MIN)), 778261);
        assertGe(-TickMath.getTickAtSqrtRatio(uint160(LTV_MAX)), 778261);
    }
}
