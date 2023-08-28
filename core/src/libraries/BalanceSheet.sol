// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {FixedPointMathLib as SoladyMath} from "solady/utils/FixedPointMathLib.sol";
import {SafeCastLib} from "solmate/utils/SafeCastLib.sol";

import {
    MIN_SIGMA,
    MAX_SIGMA,
    MAX_LEVERAGE,
    LIQUIDATION_INCENTIVE,
    MANIPULATION_THRESHOLD_DIVISOR
} from "./constants/Constants.sol";
import {mulDiv96} from "./LiquidityAmounts.sol";
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
    function isHealthy(
        Prices memory prices,
        Assets memory mem,
        uint256 liabilities0,
        uint256 liabilities1
    ) internal pure returns (bool) {
        (uint256 incentive1, ) = computeLiquidationIncentive(
            mem.fixed0 + mem.fluid0C, // total assets0 at `prices.c` (the TWAP)
            mem.fixed1 + mem.fluid1C, // total assets1 at `prices.c` (the TWAP)
            liabilities0,
            liabilities1,
            prices.c
        );
        return isHealthy(prices, mem, liabilities0, liabilities1, incentive1);
    }

    function isHealthy(
        Prices memory prices,
        Assets memory mem,
        uint256 liabilities0,
        uint256 liabilities1,
        uint256 incentive1
    ) internal pure returns (bool) {
        // The liquidation incentive is added to `liabilities1` because it's a potential liability, and we
        // don't want to re-evaluate it at the probe prices (as would happen if we added it to `liabilities0`).
        unchecked {
            liabilities0 += liabilities0 / MAX_LEVERAGE;
            liabilities1 += liabilities1 / MAX_LEVERAGE + incentive1;
        }

        // combine
        uint224 priceX96;
        uint256 liabilities;
        uint256 assets;

        priceX96 = uint224(mulDiv96(prices.a, prices.a));
        liabilities = liabilities1 + mulDiv96(liabilities0, priceX96);
        assets = mem.fluid1A + mem.fixed1 + mulDiv96(mem.fixed0, priceX96);
        if (liabilities > assets) return false;

        priceX96 = uint224(mulDiv96(prices.b, prices.b));
        liabilities = liabilities1 + mulDiv96(liabilities0, priceX96);
        assets = mem.fluid1B + mem.fixed1 + mulDiv96(mem.fixed0, priceX96);
        if (liabilities > assets) return false;

        return true;
    }

    function computeProbePrices(
        uint160 sqrtMeanPriceX96,
        uint256 sigma,
        uint256 n,
        uint56 metric
    ) internal pure returns (uint160 a, uint160 b, bool isSus) {
        unchecked {
            sigma = n * SoladyMath.clamp(sigma, MIN_SIGMA, MAX_SIGMA);
            isSus = metric > _manipulationThreshold(_effectiveCollateralFactor(sigma));

            a = uint160((sqrtMeanPriceX96 * SoladyMath.sqrt(1e18 - sigma)) / 1e9);
            b = SafeCastLib.safeCastTo160((sqrtMeanPriceX96 * SoladyMath.sqrt(1e18 + sigma)) / 1e9);
        }
    }

    function computeLiquidationIncentive(
        uint256 assets0,
        uint256 assets1,
        uint256 liabilities0,
        uint256 liabilities1,
        uint160 sqrtMeanPriceX96
    ) internal pure returns (uint256 incentive1, uint224 meanPriceX96) {
        unchecked {
            meanPriceX96 = uint224(mulDiv96(sqrtMeanPriceX96, sqrtMeanPriceX96));

            if (liabilities0 > assets0) {
                // shortfall is the amount that cannot be directly repaid using Borrower assets at this price
                uint256 shortfall = liabilities0 - assets0;
                // to cover it, a liquidator may have to use their own assets, taking on inventory risk.
                // to compensate them for this risk, they're allowed to seize some of the surplus asset.
                incentive1 += mulDiv96(shortfall, meanPriceX96) / LIQUIDATION_INCENTIVE;
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

    /// @dev Equivalent to \\( \frac{log_{1.0001} \left( \frac{10^{18}}{cf} \right)}{12} \\)
    /// assuming `MANIPULATION_THRESHOLD_DIVISOR` is 24
    function _manipulationThreshold(uint256 cf) private pure returns (uint24) {
        return uint24(-TickMath.getTickAtSqrtRatio(uint160(cf)) - 501937) / MANIPULATION_THRESHOLD_DIVISOR;
    }

    /// @dev Equivalent to \\( \frac{1 - σ}{1 + \frac{1}{liquidationIncentive} + \frac{1}{maxLeverage}} \\) where
    /// \\( σ = \frac{clampedAndScaledSigma}{10^{18}} \\) in floating point
    function _effectiveCollateralFactor(uint256 clampedAndScaledSigma) private pure returns (uint256 cf) {
        unchecked {
            cf =
                ((1e18 - clampedAndScaledSigma) * (LIQUIDATION_INCENTIVE * MAX_LEVERAGE)) /
                (LIQUIDATION_INCENTIVE * MAX_LEVERAGE + LIQUIDATION_INCENTIVE + MAX_LEVERAGE);
        }
    }
}
