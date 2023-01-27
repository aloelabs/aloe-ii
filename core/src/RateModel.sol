// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

/// @title RateModel
/// @author Aloe Labs, Inc.
/// @dev "Test everything; hold fast what is good." - 1 Thessalonians 5:21
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
