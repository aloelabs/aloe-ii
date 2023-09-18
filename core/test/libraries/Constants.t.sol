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

        assertGt(LTV_MIN, TickMath.MIN_SQRT_RATIO);
    }
}
