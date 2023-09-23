// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {FixedPointMathLib as SoladyMath} from "solady/utils/FixedPointMathLib.sol";

import {
    MAX_LEVERAGE,
    LIQUIDATION_INCENTIVE,
    PROBE_SQRT_SCALER_MIN,
    PROBE_SQRT_SCALER_MAX,
    LTV_NUMERATOR
} from "./constants/Constants.sol";
import {exp1e12} from "./Exp.sol";
import {square, mulDiv128, mulDiv128Up} from "./MulDiv.sol";
import {TickMath} from "./TickMath.sol";

struct Assets {
    uint256 fixed0;
    uint256 fixed1;
    uint256 fluid1A;
    uint256 fluid1B;
    uint256 fluid0C;
    uint256 fluid1C;
}

struct Prices {
    uint160 a;
    uint160 b;
    uint160 c;
}

/// @title BalanceSheet
/// @notice Provides functions for computing a `Borrower`'s health
/// @author Aloe Labs, Inc.
library BalanceSheet {
    using SoladyMath for uint256;

    function isHealthy(
        Prices memory prices,
        Assets memory mem,
        uint256 liabilities0,
        uint256 liabilities1
    ) internal pure returns (bool) {
        unchecked {
            // The optimizer eliminates the conditional in `divUp`; don't worry about gas golfing that
            liabilities0 +=
                liabilities0.divUp(MAX_LEVERAGE) +
                liabilities0.zeroFloorSub(mem.fixed0 + mem.fluid0C).divUp(LIQUIDATION_INCENTIVE);
            liabilities1 +=
                liabilities1.divUp(MAX_LEVERAGE) +
                liabilities1.zeroFloorSub(mem.fixed1 + mem.fluid1C).divUp(LIQUIDATION_INCENTIVE);
        }

        // combine
        uint256 priceX128;
        uint256 liabilities;
        uint256 assets;

        priceX128 = square(prices.a);
        liabilities = liabilities1 + mulDiv128Up(liabilities0, priceX128);
        assets = mem.fluid1A + mem.fixed1 + mulDiv128(mem.fixed0, priceX128);
        if (liabilities > assets) return false;

        priceX128 = square(prices.b);
        liabilities = liabilities1 + mulDiv128Up(liabilities0, priceX128);
        assets = mem.fluid1B + mem.fixed1 + mulDiv128(mem.fixed0, priceX128);
        if (liabilities > assets) return false;

        return true;
    }

    function computeProbePrices(
        uint56 metric,
        uint256 sqrtMeanPriceX96,
        uint256 iv,
        uint8 nSigma,
        uint8 manipulationThresholdDivisor
    ) internal pure returns (uint160 a, uint160 b, bool seemsLegit) {
        unchecked {
            uint256 sqrtScaler = uint256(exp1e12(int256((nSigma * iv) / 20))).clamp(
                PROBE_SQRT_SCALER_MIN,
                PROBE_SQRT_SCALER_MAX
            );

            seemsLegit = metric < _manipulationThreshold(_ltv(sqrtScaler), manipulationThresholdDivisor);

            a = uint160((sqrtMeanPriceX96 * 1e12).rawDiv(sqrtScaler).max(TickMath.MIN_SQRT_RATIO));
            b = uint160((sqrtMeanPriceX96 * sqrtScaler).rawDiv(1e12).min(TickMath.MAX_SQRT_RATIO));
        }
    }

    function computeLiquidationIncentive(
        uint256 assets0,
        uint256 assets1,
        uint256 liabilities0,
        uint256 liabilities1,
        uint256 meanPriceX128
    ) internal pure returns (uint256 incentive1) {
        unchecked {
            if (liabilities0 > assets0) {
                // shortfall is the amount that cannot be directly repaid using Borrower assets at this price
                uint256 shortfall = liabilities0 - assets0;
                // to cover it, a liquidator may have to use their own assets, taking on inventory risk.
                // to compensate them for this risk, they're allowed to seize some of the surplus asset.
                incentive1 += mulDiv128(shortfall, meanPriceX128) / LIQUIDATION_INCENTIVE;
            }

            if (liabilities1 > assets1) {
                // shortfall is the amount that cannot be directly repaid using Borrower assets at this price
                uint256 shortfall = liabilities1 - assets1;
                // to cover it, a liquidator may have to use their own assets, taking on inventory risk.
                // to compensate them for this risk, they're allowed to seize some of the surplus asset.
                incentive1 += shortfall / LIQUIDATION_INCENTIVE;
            }
        }
    }

    /// @dev Equivalent to \\( \frac{log_{1.0001} \left( \frac{10^{12}}{ltv} \right)}{\text{MANIPULATION_THRESHOLD_DIVISOR}} \\)
    function _manipulationThreshold(uint160 ltv, uint8 manipulationThresholdDivisor) private pure returns (uint24) {
        unchecked {
            return uint24(-TickMath.getTickAtSqrtRatio(ltv) - 778261) / (2 * manipulationThresholdDivisor);
        }
    }

    function _ltv(uint256 sqrtScaler) private pure returns (uint160 ltv) {
        unchecked {
            ltv = uint160(LTV_NUMERATOR.rawDiv(sqrtScaler * sqrtScaler));
        }
    }
}
