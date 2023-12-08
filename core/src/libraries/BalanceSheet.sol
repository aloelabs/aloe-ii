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

struct AuctionAmounts {
    // The amount of `TOKEN0` sent to the liquidator in exchange for repaying `repay0` and `repay1`
    uint256 out0;
    // The amount of `TOKEN1` sent to the liquidator in exchange for repaying `repay0` and `repay1`
    uint256 out1;
    // The amount of `TOKEN0` the liquidator must send to `LENDER0` in order to complete the liquidation
    uint256 repay0;
    // The amount of `TOKEN1` the liquidator must send to `LENDER1` in order to complete the liquidation
    uint256 repay1;
}

struct Assets {
    // `TOKEN0.balanceOf(borrower)`, plus the amount of `TOKEN0` underlying its Uniswap liquidity at `Prices.a`
    uint256 amount0AtA;
    // `TOKEN1.balanceOf(borrower)`, plus the amount of `TOKEN1` underlying its Uniswap liquidity at `Prices.a`
    uint256 amount1AtA;
    // `TOKEN0.balanceOf(borrower)`, plus the amount of `TOKEN0` underlying its Uniswap liquidity at `Prices.b`
    uint256 amount0AtB;
    // `TOKEN1.balanceOf(borrower)`, plus the amount of `TOKEN1` underlying its Uniswap liquidity at `Prices.b`
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

    // During liquidation auctions, the usable fraction is given by S + (R / (N - t)) - (Q / (M + 1000000t)),
    // where `t` is the time elapsed since the end of the `LIQUIDATION_GRACE_PERIOD`.
    //
    // | time since warning |      t | usable fraction |
    // | ------------------ | ------ | --------------- |
    // | 0 minutes          |      0 |              0% |
    // | 1 minute           |      0 |              0% |
    // | 4 minutes          |      0 |              0% |
    // | 5 minutes          |      0 |              0% |
    // | 5 minutes + 12 sec |     12 |             42% |
    // | 5 minutes + 24 sec |     24 |             61% |
    // | 6 minutes          |     60 |             84% |
    // | 7 minutes          |    132 |             96% |
    // | 10 minutes         |    300 |            105% |
    // | 60 minutes         |   3300 |            112% |
    // | ~1 days            |  86100 |            115% |
    // | ~3 days            | 258900 |            125% |
    // | ~7 days            | 604500 |               ∞ |
    //
    uint256 private constant _Q = 22.8811827075e18;
    uint256 private constant _R = 103567.889099532e12;
    uint256 private constant _S = 0.95e12;
    uint256 private constant _M = 20.405429e6;
    uint256 private constant _N = 7 days - LIQUIDATION_GRACE_PERIOD;

    function computeAuctionAmounts(
        Prices memory prices,
        uint256 assets0,
        uint256 assets1,
        uint256 liabilities0,
        uint256 liabilities1,
        uint256 warnTime,
        uint256 closeFactor
    ) internal view returns (AuctionAmounts memory amounts, bool willBeHealthy) {
        // Compute `assets` and `liabilities` like in `BalanceSheet.isSolvent`, except we round up `assets`
        uint256 priceX128 = square(prices.c);
        uint256 liabilities = liabilities1 + mulDiv128Up(liabilities0, priceX128);
        uint256 assets = assets1 + mulDiv128Up(assets0, priceX128);

        unchecked {
            uint256 t = _auctionTime(warnTime);
            // If it's been less than 7 days since the `Warn`ing, the available incentives (`out0` and `out1`)
            // scale with `closeFactor` and increase over time according to `auctionCurve`.
            if (t < _N) {
                liabilities *= auctionCurve(t) * closeFactor;
                assets *= 1e16;

                amounts.out0 = liabilities.fullMulDiv(assets0, assets).min(assets0);
                amounts.out1 = liabilities.fullMulDiv(assets1, assets).min(assets1);
            }
            // After 7 days, `auctionCurve` is essentially infinite. Assuming `closeFactor != 0`, their product
            // would _also_ be infinite, so incentives are set to their maximum values. NOTE: The caller should
            // validate this assumption.
            else {
                amounts.out0 = assets0;
                amounts.out1 = assets1;
            }

            // Expected repay amounts always scale with `closeFactor`
            amounts.repay0 = (liabilities0 * closeFactor) / 10000;
            amounts.repay1 = (liabilities1 * closeFactor) / 10000;

            // Check if the account will end up healthy, assuming transfers/repays are successful
            willBeHealthy = isHealthy(
                prices,
                assets0 - amounts.out0,
                assets1 - amounts.out1,
                liabilities0 - amounts.repay0,
                liabilities1 - amounts.repay1
            );
        }
    }

    function auctionCurve(uint256 t) internal pure returns (uint256) {
        unchecked {
            return _S + (_R / (_N - t)) - (_Q / (_M + 1e6 * t));
        }
    }

    /**
     * @dev Checks whether a `Borrower` is healthy given the probe prices and its current assets and liabilities.
     * Should be used when `assets` at `prices.a` differ from those at `prices.b` (due to Uniswap positions).
     */
    function isHealthy(
        Prices memory prices,
        Assets memory assets,
        uint256 liabilities0,
        uint256 liabilities1
    ) internal pure returns (bool) {
        unchecked {
            uint256 augmented0;
            uint256 augmented1;

            // The optimizer eliminates the conditional in `divUp`; don't worry about gas golfing that
            augmented0 =
                liabilities0 +
                liabilities0.divUp(MAX_LEVERAGE) +
                liabilities0.zeroFloorSub(assets.amount0AtA).divUp(LIQUIDATION_INCENTIVE);
            augmented1 =
                liabilities1 +
                liabilities1.divUp(MAX_LEVERAGE) +
                liabilities1.zeroFloorSub(assets.amount1AtA).divUp(LIQUIDATION_INCENTIVE);

            if (!isSolvent(prices.a, assets.amount0AtA, assets.amount1AtA, augmented0, augmented1)) return false;

            augmented0 =
                liabilities0 +
                liabilities0.divUp(MAX_LEVERAGE) +
                liabilities0.zeroFloorSub(assets.amount0AtB).divUp(LIQUIDATION_INCENTIVE);
            augmented1 =
                liabilities1 +
                liabilities1.divUp(MAX_LEVERAGE) +
                liabilities1.zeroFloorSub(assets.amount1AtB).divUp(LIQUIDATION_INCENTIVE);

            if (!isSolvent(prices.b, assets.amount0AtB, assets.amount1AtB, augmented0, augmented1)) return false;

            return true;
        }
    }

    /**
     * @dev Checks whether a `Borrower` is healthy given the probe prices and its current assets and liabilities.
     * Can be used when `assets` at `prices.a` are the same as those at `prices.b` (no Uniswap positions).
     */
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

            if (!isSolvent(prices.a, assets0, assets1, liabilities0, liabilities1)) return false;
            if (!isSolvent(prices.b, assets0, assets1, liabilities0, liabilities1)) return false;
            return true;
        }
    }

    function isSolvent(
        uint160 sqrtPriceX96,
        uint256 assets0,
        uint256 assets1,
        uint256 liabilities0,
        uint256 liabilities1
    ) internal pure returns (bool) {
        uint256 priceX128 = square(sqrtPriceX96);
        uint256 liabilities = liabilities1 + mulDiv128Up(liabilities0, priceX128);
        uint256 assets = assets1 + mulDiv128(assets0, priceX128);
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

    function _auctionTime(uint256 warnTime) private view returns (uint256 auctionTime) {
        unchecked {
            return block.timestamp.zeroFloorSub(warnTime + LIQUIDATION_GRACE_PERIOD);
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
