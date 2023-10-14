// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import {MAX_LEVERAGE} from "src/libraries/constants/Constants.sol";
import {IRateModel, RateModel, SafeRateLib} from "src/RateModel.sol";

contract EvilRateModel is IRateModel {
    function getYieldPerSecond(uint256 utilization, address) external view returns (uint256) {
        console2.log(gasleft());

        if (utilization % 3 == 0) return type(uint256).max;
        else if (utilization % 3 == 1) {
            while (true) {
                utilization = gasleft();
            }
            return utilization;
        }
        revert();
    }
}

contract RateModelTest is Test {
    using SafeRateLib for RateModel;
    using SafeRateLib for IRateModel;

    RateModel model;

    function setUp() public {
        model = new RateModel();
    }

    function test_spec_getYieldPerSecond() public {
        assertEq(model.getYieldPerSecond(0.0e18, address(0)), 0); // 0.00% APY
        assertEq(model.getYieldPerSecond(0.1e18, address(0)), 67); // 0.21% APY
        assertEq(model.getYieldPerSecond(0.2e18, address(0)), 152); // 0.48% APY
        assertEq(model.getYieldPerSecond(0.3e18, address(0)), 261); // 0.82% APY
        assertEq(model.getYieldPerSecond(0.5e18, address(0)), 610); // 1.94% APY
        assertEq(model.getYieldPerSecond(0.6e18, address(0)), 915); // 2.93% APY
        assertEq(model.getYieldPerSecond(0.7e18, address(0)), 1423); // 4.59% APY
        assertEq(model.getYieldPerSecond(0.8e18, address(0)), 2440); // 8.00% APY
        assertEq(model.getYieldPerSecond(0.9e18, address(0)), 5491); // 18.9% APY
        assertEq(model.getYieldPerSecond(0.999e18, address(0)), 60400); // 572% APY
    }

    function test_spec_getAccrualFactor() public {
        assertEq(model.getAccrualFactor(0, 0), 1e12);
        assertEq(model.getAccrualFactor(0, 13), 1e12);
        assertEq(model.getAccrualFactor(0, 365 days), 1e12);

        assertEq(model.getAccrualFactor(0.1e18, 0), 1e12);
        assertEq(model.getAccrualFactor(0.1e18, 13), 1000000000871);
        assertEq(model.getAccrualFactor(0.1e18, 1 days), 1000005788813);
        assertEq(model.getAccrualFactor(0.1e18, 1 weeks), 1000040522394);
        assertEq(model.getAccrualFactor(0.1e18, 365 days), 1000040522394);

        assertEq(model.getAccrualFactor(0.8e18, 0), 1e12);
        assertEq(model.getAccrualFactor(0.8e18, 13), 1000000031720);
        assertEq(model.getAccrualFactor(0.8e18, 1 days), 1000210838121);
        assertEq(model.getAccrualFactor(0.8e18, 1 weeks), 1001476800691);
        assertEq(model.getAccrualFactor(0.8e18, 365 days), 1001476800691);

        assertEq(model.getAccrualFactor(0.999e18, 0), 1e12);
        assertEq(model.getAccrualFactor(0.999e18, 13), 1000000785200);
        assertEq(model.getAccrualFactor(0.999e18, 1 days), 1005232198483);
        assertEq(model.getAccrualFactor(0.999e18, 1 weeks), 1037205322874);
        assertEq(model.getAccrualFactor(0.999e18, 365 days), 1037205322874);
    }

    function test_fuzz_accrualFactorRevert(uint256 elapsedTime, uint256 utilization) public {
        uint256 result = RateModel(address(0)).getAccrualFactor(utilization, elapsedTime);
        assertEq(result, 1e12);
    }

    function test_fuzz_accrualFactorBehavesDespiteEvilModel(uint256 elapsedTime, uint256 utilization) public {
        IRateModel evilModel = new EvilRateModel();

        uint256 before = gasleft();
        uint256 result = evilModel.getAccrualFactor(utilization, elapsedTime);
        assertLe(before - gasleft(), 105000);

        assertGe(result, 1e12);
        assertLt(result, 1.533e12);
    }

    function test_fuzz_accrualFactorIsWithinBounds(uint256 elapsedTime, uint256 utilization) public {
        uint256 result = model.getAccrualFactor(utilization, elapsedTime);

        assertGe(result, 1e12);
        assertLt(result, 1.5e12);

        // Single-block accrual factor should always be less than 1 + 1 / MAX_LEVERAGE so liquidators
        // have time to respond to interest updates
        result = model.getAccrualFactor(utilization, 13 seconds);
        assertLt(result, 1e12 + 1e12 / MAX_LEVERAGE);
    }

    function test_fuzz_accrualFactorIncreasesMonotonically(uint256 utilization) public {
        vm.assume(utilization != 0);

        assertGe(model.getAccrualFactor(utilization, 13), model.getAccrualFactor(utilization - 1, 13));
    }

    function test_fuzz_yieldPerSecondIsWithinBounds(uint256 utilization) public {
        uint256 result = model.getYieldPerSecond(utilization, address(0));

        assertGe(result, 0);
        assertLe(result, 60400);
    }

    function test_fuzz_yieldPerSecondIncreasesMonotonically(uint256 utilization) public {
        vm.assume(utilization != 0);

        assertGe(
            model.getYieldPerSecond(utilization, address(0)),
            model.getYieldPerSecond(utilization - 1, address(0))
        );
    }
}
