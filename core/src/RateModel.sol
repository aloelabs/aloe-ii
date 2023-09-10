// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {MAX_RATE, ONE} from "./libraries/constants/Constants.sol";

interface IRateModel {
    /**
     * @notice Specifies the percentage yield per second for a `lender`. Need not be a pure function
     * of `utilization`. To convert to APY: `(1 + returnValue / 1e12) ** secondsPerYear - 1`
     * @param utilization The `lender`'s total borrows divided by total assets, scaled up by 1e18
     * @param lender The `Lender` to examine
     * @return The percentage yield per second, scaled up by 1e12
     */
    function getYieldPerSecond(uint256 utilization, address lender) external view returns (uint256);
}

/// @title RateModel
/// @author Aloe Labs, Inc.
/// @dev "Test everything; hold fast what is good." - 1 Thessalonians 5:21
contract RateModel is IRateModel {
    uint256 private constant _A = 6.1010463348e20;

    uint256 private constant _B = _A / 1e18;

    /// @inheritdoc IRateModel
    function getYieldPerSecond(uint256 utilization, address) external pure returns (uint256) {
        unchecked {
            return (utilization < 0.99e18) ? _A / (1e18 - utilization) - _B : 60400;
        }
    }
}

library SafeRateLib {
    using FixedPointMathLib for uint256;

    function getAccrualFactor(IRateModel rateModel, uint256 utilization, uint256 dt) internal view returns (uint256) {
        uint256 rate;

        // Essentially `rate = rateModel.getYieldPerSecond(utilization, address(this)) ?? 0`, i.e. if the call
        // fails, we set `rate = 0` instead of reverting. Solidity's try/catch could accomplish the same thing,
        // but this is slightly more gas efficient.
        bytes memory encodedCall = abi.encodeCall(IRateModel.getYieldPerSecond, (utilization, address(this)));
        assembly ("memory-safe") {
            let success := staticcall(100000, rateModel, add(encodedCall, 32), mload(encodedCall), 0, 32)
            rate := mul(success, mload(0))
        }

        return _computeAccrualFactor(rate, dt);
    }

    function _computeAccrualFactor(uint256 rate, uint256 dt) private pure returns (uint256) {
        if (rate > MAX_RATE) rate = MAX_RATE;
        if (dt > 1 weeks) dt = 1 weeks;

        unchecked {
            return (ONE + rate).rpow(dt, ONE);
        }
    }
}
