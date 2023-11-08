// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {FixedPointMathLib as SoladyMath} from "solady/utils/FixedPointMathLib.sol";

/// @title Volatility
/// @notice Provides functions that use Uniswap v3 to compute price volatility
/// @author Aloe Labs, Inc.
library Volatility {
    using SoladyMath for uint256;

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

    uint256 private constant _Q224Div1e18 = (uint256(1 << 224) * 1e6) / 1e24; // solhint-disable const-name-snakecase
    uint256 private constant _Q128Div1e18 = (uint256(1 << 128) * 1e6) / 1e24; // solhint-disable const-name-snakecase

    /**
     * @notice Estimates implied volatility using
     * [this math](https://lambert-guillaume.medium.com/on-chain-volatility-and-uniswap-v3-d031b98143d1).
     * @dev The return value can fit in uint128 if necessary
     * @param metadata The pool's metadata (may be cached)
     * @param sqrtMeanPriceX96 sqrt(TWAP) over some period. Likely from `Oracle.consult`
     * @param a The pool's cumulative feeGrowthGlobals some time in the past
     * @param b The pool's cumulative feeGrowthGlobals as of the current block
     * @param scale The timescale (in seconds) in which IV should be reported, e.g. hourly, daily, annualized
     * @return An estimate of the implied volatility scaled by 1e12
     */
    function estimate(
        PoolMetadata memory metadata,
        uint160 sqrtMeanPriceX96,
        FeeGrowthGlobals memory a,
        FeeGrowthGlobals memory b,
        uint32 scale
    ) internal pure returns (uint256) {
        unchecked {
            // Return early to avoid division by 0
            if (b.timestamp - a.timestamp == 0) return 0;

            // Goal:  IV = 2γ √(volume / valueOfLiquidity)
            //
            //  γ = √(γ₀γ₁)
            //  volume ≈ ((P · fgg0 / γ₀) + (fgg1 / γ₁)) · liquidity
            //  valueOfLiquidity = (tickSpacing · liquidity · √P) / 20000
            //
            //        IV = 2 √( 20000 · γ₀γ₁ · ((P · fgg0 / γ₀) + (fgg1 / γ₁)) / √P / tickSpacing )
            //           = 2 √( 20000 ·        ((P · fgg0 · γ₁) + (fgg1 · γ₀)) / √P / tickSpacing )
            //           = 2 √( 20000 ·        (fgg0 · γ₁ · √P  +  fgg1 · γ₀ / √P)  / tickSpacing )

            // Calculate average [fees per unit of liquidity] for this time period
            uint256 fgg0X128 = b.feeGrowthGlobal0X128 - a.feeGrowthGlobal0X128;
            uint256 fgg1X128 = b.feeGrowthGlobal1X128 - a.feeGrowthGlobal1X128;

            // Start math.
            // Also remove Q128 and instead scale by 1e24 (gammas have 1e6, and we pull 1e18 out of the denominator).
            uint256 fgg0Gamma1MulP = fgg0X128.fullMulDiv(uint256(metadata.gamma1) * sqrtMeanPriceX96, _Q224Div1e18);
            uint256 fgg1Gamma0DivP = fgg1X128.fullMulDiv(
                uint256(metadata.gamma0) << 96,
                sqrtMeanPriceX96 * _Q128Div1e18
            );

            // Make sure numerator won't overflow in the next step
            uint256 inner = (fgg0Gamma1MulP + fgg1Gamma0DivP).min(uint256(1 << 224) / 20_000);

            // Finish math and adjust to specified timescale
            return
                2 *
                SoladyMath.sqrt(
                    (20_000 * inner * scale) / (b.timestamp - a.timestamp) / uint256(int256(metadata.tickSpacing))
                );
        }
    }
}
