// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

// TODO (when switching to PID controller)
// - will need both view and non-view versions of this
// - use utilization to update PID controller
// - each Lender gets needs its own InterestModel in order for PID controller state to work well. Could still point to single proxy for logic though.
contract InterestModel {
    uint256 private constant A = 6.1010463348e20;

    uint256 private constant B = 1e12 - A / 1e18;

    function getAccrualFactor(uint256 elapsedTime, uint256 utilization) external pure returns (uint256) {
        unchecked {
            uint256 interestRate;

            if (utilization < 0.99e18) {
                interestRate = computeYieldPerSecond(utilization);
            } else {
                interestRate = 1000000060400;
            }

            if (elapsedTime > 1 weeks) elapsedTime = 1 weeks;

            return FixedPointMathLib.rpow(interestRate, elapsedTime, 1e12);
        }
    }

    function computeYieldPerSecond(uint256 utilization) public pure returns (uint256) {
        unchecked {
            return B + A / (1e18 - utilization);
        }
    }
}
