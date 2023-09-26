// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";
import {FixedPointMathLib as SoladyMath} from "solady/utils/FixedPointMathLib.sol";

import {square, mulDiv96, mulDiv128, mulDiv224} from "./MulDiv.sol";
import {Oracle} from "./Oracle.sol";
import {TickMath} from "./TickMath.sol";

/// @title Volatility
/// @notice Provides functions that use Uniswap v3 to compute price volatility
/// @author Aloe Labs, Inc.
library Volatility {
    struct PoolMetadata {
        // the overall fee minus the protocol fee for token0, times 1e6
        uint24 gamma0;
        // the overall fee minus the protocol fee for token1, times 1e6
        uint24 gamma1;
        // the pool tick spacing
        int24 tickSpacing;
    }

    struct FeeGrowthGlobals {
        // the fee growth as a Q128.128 fees of token0 collected per unit of liquidity for the entire life of the pool
        uint256 feeGrowthGlobal0X128;
        // the fee growth as a Q128.128 fees of token1 collected per unit of liquidity for the entire life of the pool
        uint256 feeGrowthGlobal1X128;
        // the block timestamp at which feeGrowthGlobal0X128 and feeGrowthGlobal1X128 were last updated
        uint32 timestamp;
    }

    /**
     * @notice Estimates implied volatility using
     * [this math](https://lambert-guillaume.medium.com/on-chain-volatility-and-uniswap-v3-d031b98143d1).
     * @dev The return value can fit in uint128 if necessary
     * @param metadata The pool's metadata (may be cached)
     * @param data A summary of the pool's state from `pool.slot0` `pool.observe` and `pool.liquidity`
     * @param a The pool's cumulative feeGrowthGlobals some time in the past
     * @param b The pool's cumulative feeGrowthGlobals as of the current block
     * @param scale The timescale (in seconds) in which IV should be reported, e.g. hourly, daily, annualized
     * @return An estimate of the implied volatility scaled by 1e12
     */
    function estimate(
        PoolMetadata memory metadata,
        Oracle.PoolData memory data,
        FeeGrowthGlobals memory a,
        FeeGrowthGlobals memory b,
        uint32 scale
    ) internal pure returns (uint256) {
        uint256 tickTvl = computeTickTvl(metadata.tickSpacing, data.currentTick, data.sqrtPriceX96, data.tickLiquidity);

        // Return early to avoid division by 0
        if (data.secondsPerLiquidityX128 == 0 || b.timestamp - a.timestamp == 0 || tickTvl == 0) return 0;

        uint256 revenue0Gamma1 = computeRevenueGamma(
            a.feeGrowthGlobal0X128,
            b.feeGrowthGlobal0X128,
            data.secondsPerLiquidityX128,
            data.oracleLookback,
            metadata.gamma1
        );
        uint256 revenue1Gamma0 = computeRevenueGamma(
            a.feeGrowthGlobal1X128,
            b.feeGrowthGlobal1X128,
            data.secondsPerLiquidityX128,
            data.oracleLookback,
            metadata.gamma0
        );
        // This is an approximation. Ideally the fees earned during each swap would be multiplied by the price
        // *at that swap*. But for prices simulated with GBM and swap sizes either normally or uniformly distributed,
        // the error you get from using geometric mean price is <1% even with high drift and volatility.
        uint256 volumeGamma0Gamma1 = revenue1Gamma0 + amount0ToAmount1(revenue0Gamma1, data.sqrtMeanPriceX96);
        // Clamp to prevent overflow later on
        if (volumeGamma0Gamma1 > (1 << 128)) volumeGamma0Gamma1 = (1 << 128);

        unchecked {
            // Scale volume to the target time frame, divide by `tickTvl`, and sqrt for final result
            return SoladyMath.sqrt((4e24 * volumeGamma0Gamma1 * scale) / (b.timestamp - a.timestamp) / tickTvl);
        }
    }

    /**
     * @notice Computes an `amount1` that (at `tick`) is equivalent in worth to the provided `amount0`
     * @param amount0 The amount of token0 to convert
     * @param sqrtPriceX96 The sqrt(price) at which the conversion should hold true
     * @return amount1 An equivalent amount of token1
     */
    function amount0ToAmount1(uint256 amount0, uint160 sqrtPriceX96) internal pure returns (uint256 amount1) {
        uint256 priceX128 = square(sqrtPriceX96);
        amount1 = mulDiv128(amount0, priceX128);
    }

    /**
     * @notice Computes pool revenue using feeGrowthGlobal accumulators, then scales it down by a factor of gamma
     * @param feeGrowthGlobalAX128 The value of feeGrowthGlobal (either 0 or 1) at time A
     * @param feeGrowthGlobalBX128 The value of feeGrowthGlobal (either 0 or 1, but matching) at time B (B > A)
     * @param secondsPerLiquidityX128 The difference in the secondsPerLiquidity accumulator from `secondsAgo` seconds ago until now
     * @param secondsAgo The oracle lookback period that was used to find `secondsPerLiquidityX128`
     * @param gamma The fee factor to scale by
     * @return Revenue over the period from `block.timestamp - secondsAgo` to `block.timestamp`, scaled down by a factor of gamma
     */
    function computeRevenueGamma(
        uint256 feeGrowthGlobalAX128,
        uint256 feeGrowthGlobalBX128,
        uint160 secondsPerLiquidityX128,
        uint32 secondsAgo,
        uint24 gamma
    ) internal pure returns (uint256) {
        unchecked {
            uint256 delta;

            if (feeGrowthGlobalBX128 >= feeGrowthGlobalAX128) {
                // feeGrowthGlobal has increased from time A to time B
                delta = feeGrowthGlobalBX128 - feeGrowthGlobalAX128;
            } else {
                // feeGrowthGlobal has overflowed between time A and time B
                delta = type(uint256).max - feeGrowthGlobalAX128 + feeGrowthGlobalBX128;
            }

            return Math.mulDiv(delta, secondsAgo * uint256(gamma), secondsPerLiquidityX128 * uint256(1e6));
        }
    }

    /**
     * @notice Computes the value of liquidity available at the current tick, denominated in token1
     * @param tickSpacing The pool tick spacing (from pool.tickSpacing())
     * @param tick The current tick (from pool.slot0())
     * @param sqrtPriceX96 The current price (from pool.slot0())
     * @param liquidity The liquidity depth at currentTick (from pool.liquidity())
     */
    function computeTickTvl(
        int24 tickSpacing,
        int24 tick,
        uint160 sqrtPriceX96,
        uint128 liquidity
    ) internal pure returns (uint256 tickTvl) {
        unchecked {
            tick = TickMath.floor(tick, tickSpacing);

            tickTvl = _getValueOfLiquidity(
                sqrtPriceX96,
                TickMath.getSqrtRatioAtTick(tick),
                TickMath.getSqrtRatioAtTick(tick + tickSpacing),
                liquidity
            );
        }
    }

    /**
     * @notice Computes the value of the liquidity in terms of token1
     * @dev The return value can fit in uint193 if necessary
     * @param sqrtRatioX96 A sqrt price representing the current pool prices
     * @param sqrtRatioAX96 A sqrt price representing the lower tick boundary
     * @param sqrtRatioBX96 A sqrt price representing the upper tick boundary
     * @param liquidity The liquidity being valued
     * @return value The total value of `liquidity`, in terms of token1
     */
    function _getValueOfLiquidity(
        uint160 sqrtRatioX96,
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint128 liquidity
    ) private pure returns (uint256 value) {
        assert(sqrtRatioAX96 <= sqrtRatioX96 && sqrtRatioX96 <= sqrtRatioBX96);

        unchecked {
            uint256 numerator = Math.mulDiv(uint256(liquidity) << 128, sqrtRatioX96, sqrtRatioBX96);

            value =
                mulDiv224(numerator, sqrtRatioBX96 - sqrtRatioX96) +
                mulDiv96(liquidity, sqrtRatioX96 - sqrtRatioAX96);
        }
    }
}
