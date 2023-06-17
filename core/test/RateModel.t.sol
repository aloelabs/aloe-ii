// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import {RateModel} from "src/RateModel.sol";

contract RateModelTest is Test {
    RateModel model;

    function setUp() public {
        model = new RateModel();
    }

    function test_yieldPerSecondIsWithinBounds(uint256 utilization) public {
        uint256 result = model.getYieldPerSecond(utilization, address(0));

        assertGe(result, 1e12);
        assertLe(result, 1000000060400);
    }

    function test_yieldPerSecondIncreasesMonotonically(uint256 utilization) public {
        vm.assume(utilization != 0);

        assertGe(
            model.getYieldPerSecond(utilization, address(0)),
            model.getYieldPerSecond(utilization - 1, address(0))
        );
    }

    function test_spec_getYieldPerSecond() public {
        assertEq(model.getYieldPerSecond(0.0e18, address(0)), 1000000000000); // 0.00% APY
        assertEq(model.getYieldPerSecond(0.1e18, address(0)), 1000000000067); // 0.21% APY
        assertEq(model.getYieldPerSecond(0.2e18, address(0)), 1000000000152); // 0.48% APY
        assertEq(model.getYieldPerSecond(0.3e18, address(0)), 1000000000261); // 0.82% APY
        assertEq(model.getYieldPerSecond(0.5e18, address(0)), 1000000000610); // 1.94% APY
        assertEq(model.getYieldPerSecond(0.6e18, address(0)), 1000000000915); // 2.93% APY
        assertEq(model.getYieldPerSecond(0.7e18, address(0)), 1000000001423); // 4.59% APY
        assertEq(model.getYieldPerSecond(0.8e18, address(0)), 1000000002440); // 8.00% APY
        assertEq(model.getYieldPerSecond(0.9e18, address(0)), 1000000005491); // 18.9% APY
        assertEq(model.getYieldPerSecond(0.999e18, address(0)), 1000000060400); // 572% APY
    }
}
