// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

contract InterestModel {
    function getAccrualFactor(uint256 elapsedTime, uint256 utilization) external returns (uint256 accrualFactor) {
        // TODO could use exp{APY * deltaT / 360.}
        // TODO use utilization to update PID controller

        accrualFactor = (utilization > 0.5e18 ? 0.00004e8 : 0.00002e8) * elapsedTime;
    }
}
