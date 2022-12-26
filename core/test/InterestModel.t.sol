// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

import "forge-std/Test.sol";

import {InterestModel} from "src/InterestModel.sol";

contract RateModelTest is Test {
    InterestModel model;

    function setUp() public {
        model = new InterestModel();
    }

    function test_neverReverts(uint256 elapsedTime, uint256 utilization) public {
        model.computeYieldPerSecond(utilization % (1e18 - 1));
        uint256 result = model.getAccrualFactor(elapsedTime, utilization);

        assertGe(result, 1e12);
        assertLt(result, 2e12);
    }
}
