// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.17;

import {FixedPointMathLib as SoladyMath} from "solady/utils/FixedPointMathLib.sol";
import {IUniswapV3Pool} from "v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {UNISWAP_AVG_WINDOW} from "./constants/Constants.sol";
import {TickMath} from "./TickMath.sol";

/// @title Oracle
/// @notice Provides functions to integrate with V3 pool oracle
/// @author Aloe Labs, Inc.
/// @author Modified from Uniswap (https://github.com/Uniswap/v3-periphery/blob/main/contracts/libraries/OracleLibrary.sol)
library Oracle {
    /**
     * @notice Calculates time-weighted means of tick and liquidity for a given Uniswap V3 pool
     * @param pool Address of the pool that we want to observe
     * @return metric If the price was manipulated at any point in the past `UNISWAP_AVG_WINDOW` seconds, then at
     * some point in that period, this value will spike. It may still be high now, or (if the attacker is smart and
     * well-financed) it may have returned to nominal.
     * @return sqrtMeanPriceX96 The sqrt(geometricMeanPrice) over the past `UNISWAP_AVG_WINDOW` seconds
     * @return secondsPerLiquidityX128 The change in seconds per liquidity over the past `UNISWAP_AVG_WINDOW` seconds
     */
    function consult(
        IUniswapV3Pool pool
    ) internal view returns (uint56 metric, uint160 sqrtMeanPriceX96, uint160 secondsPerLiquidityX128) {
        uint32[] memory secondsAgos = new uint32[](3);
        secondsAgos[0] = UNISWAP_AVG_WINDOW * 2;
        secondsAgos[1] = UNISWAP_AVG_WINDOW;
        secondsAgos[2] = 0;

        (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s) = pool.observe(
            secondsAgos
        );
        secondsPerLiquidityX128 = secondsPerLiquidityCumulativeX128s[2] - secondsPerLiquidityCumulativeX128s[1];

        unchecked {
            // Compute arithmetic mean tick over the interval [-2w, 0)
            int256 meanTick0To2W = (tickCumulatives[2] - tickCumulatives[0]) / int32(UNISWAP_AVG_WINDOW * 2);
            // Compute arithmetic mean tick over the interval [-2w, -w]
            int256 meanTickWTo2W = (tickCumulatives[1] - tickCumulatives[0]) / int32(UNISWAP_AVG_WINDOW);
            //                                         i                 i-2w                       i-w               i-2w
            //        meanTick0To2W - meanTickWTo2W = (∑ tick_n * dt_n - ∑ tick_n * dt_n) / (2T) - (∑ tick_n * dt_n - ∑ tick_n * dt_n) / T
            //                                         n=0               n=0                        n=0               n=0
            //
            //                                        i                   i-w
            // 2T * (meanTick0To2W - meanTickWTo2W) = ∑ tick_n * dt_n  - 2∑ tick_n * dt_n
            //                                        n=i-2w              n=i-2w
            //
            //                                        i                   i-w
            //                                      = ∑ tick_n * dt_n  -  ∑ tick_n * dt_n
            //                                        n=i-w               n=i-2w
            //
            // Thus far all values have been "true". We now assume that some manipulated value `manip_n` is added to each `tick_n`
            //
            //                                        i                               i-w
            //                                      = ∑ (tick_n + manip_n) * dt_n  -  ∑ (tick_n + manip_n) * dt_n
            //                                        n=i-w                           n=i-2w
            //
            //                                        i                   i-w                 i                    i-w
            //                                      = ∑ tick_n * dt_n  -  ∑ tick_n * dt_n  +  ∑ manip_n * dt_n  -  ∑ manip_n * dt_n
            //                                        n=i-w               n=i-2w              n=i-w                n=i-2w
            //
            //        meanTick0To2W - meanTickWTo2W = (meanTick0ToW_true - meanTickWTo2W_true) / 2  +  (sumManip0ToW - sumManipWTo2W) / (2T)
            //
            // For short time periods and reasonable market conditions, (meanTick0ToW_true - meanTickWTo2W_true) ≈ 0
            //
            //                                      ≈ (sumManip0ToW - sumManipWTo2W) / (2T)
            //
            // The TWAP we care about (see a few lines down) is measured over the interval [-w, 0). The result we've
            // just derived contains `sumManip0ToW`, which is the sum of all manipulation in that same interval. As
            // such, we use it as a metric for detecting manipulation. NOTE: If an attacker manipulates things to
            // the same extent in the prior interval [-2w, -w), the metric will be 0. To guard against this, we must
            // to watch the metric over the entire window. Even though it may be 0 *now*, it will have risen past a
            // threshold at *some point* in the past `UNISWAP_AVG_WINDOW` seconds.
            metric = uint56(SoladyMath.dist(meanTick0To2W, meanTickWTo2W));

            // Compute arithmetic mean tick over `UNISWAP_AVG_WINDOW`, always rounding down to -inf
            int256 delta = tickCumulatives[2] - tickCumulatives[1];
            int256 meanTick0ToW = delta / int32(UNISWAP_AVG_WINDOW);
            assembly ("memory-safe") {
                // Equivalent: if (delta < 0 && (delta % UNISWAP_AVG_WINDOW != 0)) meanTick0ToW--;
                meanTick0ToW := sub(meanTick0ToW, and(slt(delta, 0), iszero(iszero(smod(delta, UNISWAP_AVG_WINDOW)))))
            }
            sqrtMeanPriceX96 = TickMath.getSqrtRatioAtTick(int24(meanTick0ToW));
        }
    }

    /**
     * @notice Searches for oracle observations nearest to the `target` time. If `target` lies between two existing
     * observations, linearly interpolate between them. If `target` is newer than the most recent observation,
     * we interpolate between the most recent one and a hypothetical one taken at the current block.
     * @dev As long as `target <= block.timestamp`, return values should match what you'd get from Uniswap:
     * ```
     *   uint32[] memory secondsAgos = new uint32[](1);
     *   secondsAgos[0] = block.timestamp - target;
     *   (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s) = pool.observe(
     *     secondsAgos
     *   );
     * ```
     * @param pool The Uniswap pool to examine
     * @param target The timestamp of the desired observation
     * @param seed The index of `pool.observations` where we start our search. Can be determined off-chain to make
     * this method more efficient than Uniswap's binary search.
     * @param tick The current tick (from pool.slot0())
     * @param observationIndex The current observation index (from pool.slot0())
     * @param observationCardinality The current observation cardinality (from pool.slot0())
     * @param liquidity The current liquidity depth at `tick` (from pool.liquidity());
     * @return tickCumulative The tick * time elapsed since `pool` was first initialized
     * @return secondsPerLiquidityCumulativeX128 The time elapsed / max(1, liquidity) since `pool` was first initialized
     */
    function observe(
        IUniswapV3Pool pool,
        uint32 target,
        uint256 seed,
        int24 tick,
        uint16 observationIndex,
        uint16 observationCardinality,
        uint128 liquidity
    ) internal view returns (int56, uint160) {
        unchecked {
            seed %= observationCardinality;
            (uint32 timeL, int56 tickCumL, uint160 liqCumL, ) = pool.observations(seed);

            for (uint256 i = 0; i < observationCardinality; i++) {                
                if (timeL == target) {
                    return (tickCumL, liqCumL);
                }

                if (timeL < target && seed == observationIndex) {
                    uint56 delta = uint56(target - timeL);
                    return (
                        tickCumL + tick * int56(delta),
                        liqCumL + (uint160(delta) << 128) / (liquidity > 0 ? liquidity : 1)
                    );
                }

                seed = (seed + 1) % observationCardinality;
                (uint32 timeR, int56 tickCumR, uint160 liqCumR, ) = pool.observations(seed);

                if (timeL < target && target < timeR) {
                    uint56 delta = uint56(target - timeL);
                    uint56 denom = uint56(timeR - timeL);
                    // Uniswap divides before multiplying, so we do too
                    return (
                        tickCumL + ((tickCumR - tickCumL) / int56(denom)) * int56(delta),
                        liqCumL + uint160(((liqCumR - liqCumL) * delta) / denom)
                    );
                }

                (timeL, tickCumL, liqCumL) = (timeR, tickCumR, liqCumR);
            }

            revert("OLD");
        }
    }

    /**
     * @notice Given a pool, returns the number of seconds ago of the oldest stored observation
     * @param pool Address of Uniswap V3 pool that we want to observe
     * @param observationIndex The observation index from pool.slot0()
     * @param observationCardinality The observationCardinality from pool.slot0()
     * @dev (, , uint16 observationIndex, uint16 observationCardinality, , , ) = pool.slot0();
     * @return secondsAgo The number of seconds ago that the oldest observation was stored
     */
    function getMaxSecondsAgo(
        IUniswapV3Pool pool,
        uint16 observationIndex,
        uint16 observationCardinality
    ) internal view returns (uint32 secondsAgo) {
        require(observationCardinality != 0, "NI");

        unchecked {
            (uint32 observationTimestamp, , , bool initialized) = pool.observations(
                (observationIndex + 1) % observationCardinality
            );

            // The next index might not be initialized if the cardinality is in the process of increasing
            // In this case the oldest observation is always in index 0
            if (!initialized) {
                (observationTimestamp, , , ) = pool.observations(0);
            }

            secondsAgo = uint32(block.timestamp) - observationTimestamp;
        }
    }
}
