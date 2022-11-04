// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

import "solmate/utils/FixedPointMathLib.sol";

contract InterestModel {
    // TODO will need both view and non-view versions of this
    function getAccrualFactor(uint256 elapsedTime, uint256 utilization) external view returns (uint256 accrualFactor) {
        // TODO use utilization to update PID controller
        // TODO each Kitty gets needs its own InterestModel in order for PID controller state to work well. Could still point to single proxy for logic though.

        // If utilization > 50%, use 4% APY. 2% APY otherwise.
        uint256 interestRate = utilization > 0.5e18 ? 1.24e3 : 6.27e2; // ((1 + r) ^ (1 / SECONDS_IN_YEAR) - 1) * 1e12

        unchecked {
            accrualFactor = FixedPointMathLib.rpow(1e12 + interestRate, elapsedTime, 1e12) - 1e12;
        }
    }
}
