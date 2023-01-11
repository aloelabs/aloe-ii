// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

// TODO (when switching to PID controller)
// - will need both view and non-view versions of this
// - use utilization to update PID controller
// - each Lender gets needs its own RateModel in order for PID controller state to work well. Could still point to single proxy for logic though.
contract RateModel {
    uint256 private constant A = 6.1010463348e20;

    uint256 private constant B = 1e12 - A / 1e18;

    function getAccrualFactor(uint256 elapsedTime, uint256 utilization) external pure returns (uint256) {
        unchecked {
            uint256 rate = computeYieldPerSecond(utilization);

            if (elapsedTime > 1 weeks) elapsedTime = 1 weeks;

            return FixedPointMathLib.rpow(rate, elapsedTime, 1e12);
        }
    }

    function computeYieldPerSecond(uint256 utilization) public pure returns (uint256) {
        unchecked {
            return (utilization < 0.99e18) ? B + A / (1e18 - utilization) : 1000000060400;
        }
    }
}
