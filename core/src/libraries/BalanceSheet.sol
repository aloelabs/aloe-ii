// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {FixedPointMathLib as SoladyMath} from "solady/utils/FixedPointMathLib.sol";

import {
    MAX_LEVERAGE,
    LIQUIDATION_INCENTIVE,
    LIQUIDATION_GRACE_PERIOD,
    PROBE_SQRT_SCALER_MIN,
    PROBE_SQRT_SCALER_MAX,
    LTV_NUMERATOR
} from "./constants/Constants.sol";
import {exp1e12} from "./Exp.sol";
import {square, mulDiv128, mulDiv128Up} from "./MulDiv.sol";
import {TickMath} from "./TickMath.sol";

struct Assets {
    // The `Borrower`'s balance of `TOKEN0`, i.e. `TOKEN0.balanceOf(borrower)`, plus the amount of `TOKEN0`
    // underlying the `Borrower`'s Uniswap liquidity at `Prices.a`
    uint256 amount0AtA;
    // The `Borrower`'s balance of `TOKEN1`, i.e. `TOKEN1.balanceOf(borrower)`, plus the amount of `TOKEN1`
    // underlying the `Borrower`'s Uniswap liquidity at `Prices.a`
    uint256 amount1AtA;
    // The `Borrower`'s balance of `TOKEN0`, i.e. `TOKEN0.balanceOf(borrower)`, plus the amount of `TOKEN0`
    // underlying the `Borrower`'s Uniswap liquidity at `Prices.b`
    uint256 amount0AtB;
    // The `Borrower`'s balance of `TOKEN1`, i.e. `TOKEN1.balanceOf(borrower)`, plus the amount of `TOKEN1`
    // underlying the `Borrower`'s Uniswap liquidity at `Prices.b`
    uint256 amount1AtB;
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
        if (!_isSolvent(prices.a, assets.amount0AtA, assets.amount1AtA, liabilities0, liabilities1)) return false;
        if (!_isSolvent(prices.b, assets.amount0AtB, assets.amount1AtB, liabilities0, liabilities1)) return false;
        return true;
    }

    function isHealthy(
        Prices memory prices,
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

        uint256 priceX128;
        uint256 assets;
        uint256 liabilities;

        priceX128 = square(prices.a);
        assets = assets1 + mulDiv128(assets0, priceX128);
        liabilities = liabilities1 + mulDiv128Up(liabilities0, priceX128);
        if (liabilities > assets) return false;

        priceX128 = square(prices.b);
        assets = assets1 + mulDiv128(assets0, priceX128);
        liabilities = liabilities1 + mulDiv128Up(liabilities0, priceX128);
        if (liabilities > assets) return false;

        return true;
    }

    function _isSolvent(
        uint160 sqrtPriceX96,
        uint256 assets0,
        uint256 assets1,
        uint256 liabilities0,
        uint256 liabilities1
    ) private pure returns (bool) {
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
     * @param liabilities0 The amount of `TOKEN0` that the `Borrower` owes to `LENDER0`
     * @param liabilities1 The amount of `TOKEN1` that the `Borrower` owes to `LENDER1`
     * @param meanPriceX128 The current TWAP
     * // TODO:
     * @return incentive1 The incentive to pay out, denominated in `TOKEN1`
     */
    function computeLiquidationIncentive(
        uint256 liabilities0,
        uint256 liabilities1,
        uint256 meanPriceX128,
        uint256 auctionTime,
        uint16 closeFactor
    ) internal view returns (uint256 incentive1) {
        assembly ("memory-safe") {
            // Equivalent: `if (auctionTime != 0) auctionTime = block.timestamp - auctionTime;`
            auctionTime := mul(gt(auctionTime, 0), sub(timestamp(), auctionTime))
        }
        require(auctionTime > LIQUIDATION_GRACE_PERIOD, "Aloe: grace");

        unchecked {
            incentive1 = 0.08e8 * (auctionTime - LIQUIDATION_GRACE_PERIOD);
            if (auctionTime > 3 * LIQUIDATION_GRACE_PERIOD) {
                incentive1 -= 0.07354386e8 * (auctionTime - 3 * LIQUIDATION_GRACE_PERIOD);
            }
            incentive1 =
                (incentive1 * (liabilities1 + mulDiv128Up(liabilities0, meanPriceX128)) * closeFactor) /
                (1e8 * 10 minutes * 10_000);
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
