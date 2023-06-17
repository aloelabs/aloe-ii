// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

interface IRateModel {
    /**
     * @notice Specifies the percentage yield per second for a `lender`. Need not be a pure function
     * of `utilization`. To convert to APY: `(returnValue / 1e12) ** secondsPerYear - 1`
     * @param utilization The `lender`'s total borrows divided by total assets, scaled up by 1e18
     * @param lender The `Lender` to examine
     * @return The percentage yield per second, scaled up by 1e12, plus 1e12
     */
    function getYieldPerSecond(uint256 utilization, address lender) external view returns (uint256);
}

/// @title RateModel
/// @author Aloe Labs, Inc.
/// @dev "Test everything; hold fast what is good." - 1 Thessalonians 5:21
contract RateModel is IRateModel {
    uint256 private constant A = 6.1010463348e20;

    uint256 private constant B = 1e12 - A / 1e18;

    /// @inheritdoc IRateModel
    function getYieldPerSecond(uint256 utilization, address) external pure returns (uint256) {
        unchecked {
            return (utilization < 0.99e18) ? B + A / (1e18 - utilization) : 1000000060400;
        }
    }
}
