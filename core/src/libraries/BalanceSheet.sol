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

struct Balance {
    // An amount of `TOKEN0`
    uint256 amount0;
    // An amount of `TOKEN1`
    uint256 amount1;
}

struct Assets {
    // The `Borrower`'s balances at `Prices.a` (including underlying amounts of Uniswap positions)
    Balance a;
    // The `Borrower`'s balances at `Prices.b` (including underlying amounts of Uniswap positions)
    Balance b;
}

struct Prices {
    // Some sqrtPriceX96 *less* than the current TWAP
    uint160 a;
    // Some sqrtPriceX96 *greater* than the current TWAP
    uint160 b;
    // The current TWAP, expressed as a sqrtPriceX96
    uint160 c;
}

/// @title BalanceSheet
/// @notice Provides functions for computing a `Borrower`'s health
/// @author Aloe Labs, Inc.
library BalanceSheet {
    using SoladyMath for uint256;

    /// @dev Checks whether a `Borrower` is healthy given the probe prices and its current assets and liabilities
    function isHealthy(
        Prices memory prices,
        Assets memory assets,
        uint256 liabilities0,
        uint256 liabilities1
    ) internal pure returns (bool) {
        if (!isSolvent(prices.a, assets.a.amount0, assets.a.amount1, liabilities0, liabilities1)) return false;
        if (!isSolvent(prices.b, assets.b.amount0, assets.b.amount1, liabilities0, liabilities1)) return false;
        return true;
    }

    function isSolvent(
        uint160 sqrtPriceX96,
        uint256 assets0,
        uint256 assets1,
        uint256 liabilities0,
        uint256 liabilities1
    ) internal pure returns (bool) {
        unchecked {
            // The optimizer eliminates the conditional in `divUp`; don't worry about gas golfing that
            liabilities0 +=
                liabilities0.divUp(MAX_LEVERAGE) +
                liabilities0.zeroFloorSub(assets0).divUp(LIQUIDATION_INCENTIVE);
            liabilities1 +=
                liabilities1.divUp(MAX_LEVERAGE) +
                liabilities1.zeroFloorSub(assets1).divUp(LIQUIDATION_INCENTIVE);
        }

        uint256 priceX128 = square(sqrtPriceX96);
        uint256 assets = assets1 + mulDiv128(assets0, priceX128);
        uint256 liabilities = liabilities1 + mulDiv128Up(liabilities0, priceX128);
        return assets >= liabilities;
    }

    /**
     * Given data from the `ORACLE` (first 3 args) and parameters from the `FACTORY` (last 2 args), computes
     * the probe prices at which to check the account's health
     * @param metric The manipulation metric (from oracle)
     * @param sqrtMeanPriceX96 The current TWAP, expressed as a sqrtPriceX96 (from oracle)
     * @param iv The estimated implied volatility, expressed as a 1e12 percentage (from oracle)
     * @param nSigma The number of standard deviations of price movement to account for (from factory)
     * @param manipulationThresholdDivisor Helps compute the manipulation threshold (from factory). See `Constants.sol`
     * @return a \\( \text{TWAP} \cdot e^{-n \cdot \sigma} \\) expressed as a sqrtPriceX96
     * @return b \\( \text{TWAP} \cdot e^{+n \cdot \sigma} \\) expressed as a sqrtPriceX96
     * @return seemsLegit Whether the Uniswap TWAP has been manipulated enough to create bad debt at the effective LTV
     */
    function computeProbePrices(
        uint56 metric,
        uint256 sqrtMeanPriceX96,
        uint256 iv,
        uint8 nSigma,
        uint8 manipulationThresholdDivisor
    ) internal pure returns (uint160 a, uint160 b, bool seemsLegit) {
        unchecked {
            // Essentially sqrt(e^{nSigma*iv}). Note the `Factory` defines `nSigma` with an extra factor of 10
            uint256 sqrtScaler = uint256(exp1e12(int256((nSigma * iv) / 20))).clamp(
                PROBE_SQRT_SCALER_MIN,
                PROBE_SQRT_SCALER_MAX
            );

            seemsLegit = metric < _manipulationThreshold(_ltv(sqrtScaler), manipulationThresholdDivisor);

            a = uint160((sqrtMeanPriceX96 * 1e12).rawDiv(sqrtScaler).max(TickMath.MIN_SQRT_RATIO));
            b = uint160((sqrtMeanPriceX96 * sqrtScaler).rawDiv(1e12).min(TickMath.MAX_SQRT_RATIO));
        }
    }

    /**
     * @notice Computes the liquidation incentive that would be paid out if a liquidator closes the account
     * using a swap with `strain = 1`
     * @param assets0 The amount of `TOKEN0` held/controlled by the `Borrower` at the current TWAP
     * @param assets1 The amount of `TOKEN1` held/controlled by the `Borrower` at the current TWAP
     * @param liabilities0 The amount of `TOKEN0` that the `Borrower` owes to `LENDER0`
     * @param liabilities1 The amount of `TOKEN1` that the `Borrower` owes to `LENDER1`
     * @param meanPriceX128 The current TWAP
     * @return incentive1 The incentive to pay out, denominated in `TOKEN1`
     */
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

    /**
     * @notice The effective LTV implied by `sqrtScaler`. This LTV is accurate for fixed assets and out-of-range
     * Uniswap positions, but not for in-range Uniswap positions (impermanent losses make their effective LTV
     * slightly smaller).
     */
    function _ltv(uint256 sqrtScaler) private pure returns (uint160 ltv) {
        unchecked {
            ltv = uint160(LTV_NUMERATOR.rawDiv(sqrtScaler * sqrtScaler));
        }
    }
}
