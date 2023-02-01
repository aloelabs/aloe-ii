// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {IUniswapV3Pool} from "v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {MAX_SIGMA, IV_SCALE, IV_CHANGE_PER_SECOND, ORACLE_LOOKBACK, FEE_GROWTH_GLOBALS_SAMPLE_PERIOD} from "./libraries/constants/Constants.sol";
import {Oracle} from "./libraries/Oracle.sol";
import {Volatility} from "./libraries/Volatility.sol";

/// @title VolatilityOracle
/// @author Aloe Labs, Inc.
/// @dev "Test everything; hold fast what is good." - 1 Thessalonians 5:21
contract VolatilityOracle {
    struct LastWrite {
        uint8 index;
        uint32 time;
        uint216 iv;
    }

    mapping(IUniswapV3Pool => Volatility.PoolMetadata) public cachedMetadata;

    mapping(IUniswapV3Pool => Volatility.FeeGrowthGlobals[60]) public feeGrowthGlobals;

    mapping(IUniswapV3Pool => LastWrite) public lastWrites;

    function prepare(IUniswapV3Pool pool) external {
        cachedMetadata[pool] = _getPoolMetadata(pool);

        if (lastWrites[pool].time == 0) {
            feeGrowthGlobals[pool][0] = _getFeeGrowthGlobalsNow(pool);
            lastWrites[pool] = LastWrite({index: 0, time: uint32(block.timestamp), iv: uint216(MAX_SIGMA)});
        }
    }

    function update(IUniswapV3Pool pool) external returns (uint160, uint256) {
        unchecked {
            // Read `lastWrite` info from storage
            LastWrite memory lastWrite = lastWrites[pool];

            // If fewer than `VOLATILITY_SAMPLE_PERIOD` seconds have elapsed, return early. We
            // still fetch the latest TWAP, but we do not sample feeGrowthGlobals or update IV
            uint256 timeSinceLastWrite = block.timestamp - lastWrite.time;
            if (timeSinceLastWrite < FEE_GROWTH_GLOBALS_SAMPLE_PERIOD) {
                (uint160 sqrtMeanPriceX96, ) = Oracle.consult(pool, ORACLE_LOOKBACK);
                return (sqrtMeanPriceX96, lastWrite.iv);
            }

            // Prepare to call all getters
            Volatility.FeeGrowthGlobals[60] storage arr = feeGrowthGlobals[pool];

            // Call all getters
            Volatility.PoolData memory data = _getPoolData(pool);
            Volatility.FeeGrowthGlobals memory a = _getFeeGrowthGlobalsOld(arr, lastWrite.index);
            Volatility.FeeGrowthGlobals memory b = _getFeeGrowthGlobalsNow(pool);

            // Default to using the existing IV
            uint256 iv = lastWrite.iv;
            // Only update IV if the feeGrowthGlobals samples are approximately 1 hour apart
            if (
                isInInterval({
                    min: 1 hours - 5 minutes, // NOTE: Keeping constants in-line because they're related to arr.length
                    x: b.timestamp - a.timestamp,
                    max: 1 hours + 5 minutes
                })
            ) {
                // Estimate, then clamp so it lies within [previous - maxChange, previous + maxChange]
                iv = Volatility.estimate(cachedMetadata[pool], data, a, b, IV_SCALE);

                uint256 maxChange = timeSinceLastWrite * IV_CHANGE_PER_SECOND;
                if (iv > lastWrite.iv + maxChange) iv = lastWrite.iv + maxChange;
                else if (iv + maxChange < lastWrite.iv) iv = lastWrite.iv - maxChange;
            }

            // Store the new feeGrowthGlobals sample and update `lastWrites`
            uint8 next = uint8((lastWrite.index + 1) % 60);
            arr[next] = b;
            lastWrites[pool] = LastWrite(next, uint32(block.timestamp), uint216(iv));

            return (data.sqrtMeanPriceX96, iv);
        }
    }

    function consult(IUniswapV3Pool pool) external view returns (uint160, uint256) {
        (uint160 sqrtMeanPriceX96, ) = Oracle.consult(pool, ORACLE_LOOKBACK);
        return (sqrtMeanPriceX96, lastWrites[pool].iv);
    }

    function _getPoolMetadata(IUniswapV3Pool pool) private view returns (Volatility.PoolMetadata memory metadata) {
        (, , uint16 observationIndex, uint16 observationCardinality, , uint8 feeProtocol, ) = pool.slot0();
        // If block times are inconsistent, `maxSecondsAgo` from oracle may be inflated. Divide by 2 to be extra safe.
        metadata.maxSecondsAgo = Oracle.getMaxSecondsAgo(pool, observationIndex, observationCardinality) / 2;
        require(metadata.maxSecondsAgo > ORACLE_LOOKBACK, "Aloe: cardinality");

        uint24 fee = pool.fee();
        metadata.gamma0 = fee;
        metadata.gamma1 = fee;
        unchecked {
            if (feeProtocol % 16 != 0) metadata.gamma0 -= fee / (feeProtocol % 16);
            if (feeProtocol >> 4 != 0) metadata.gamma1 -= fee / (feeProtocol >> 4);
        }

        metadata.tickSpacing = pool.tickSpacing();
    }

    function _getPoolData(IUniswapV3Pool pool) private view returns (Volatility.PoolData memory data) {
        (uint160 sqrtPriceX96, int24 currentTick, , , , , ) = pool.slot0();
        (uint160 sqrtMeanPriceX96, uint160 secondsPerLiquidityX128) = Oracle.consult(pool, ORACLE_LOOKBACK);
        data = Volatility.PoolData(
            sqrtPriceX96,
            currentTick,
            sqrtMeanPriceX96,
            secondsPerLiquidityX128,
            ORACLE_LOOKBACK,
            pool.liquidity()
        );
    }

    function _getFeeGrowthGlobalsNow(IUniswapV3Pool pool) private view returns (Volatility.FeeGrowthGlobals memory) {
        return
            Volatility.FeeGrowthGlobals(
                pool.feeGrowthGlobal0X128(),
                pool.feeGrowthGlobal1X128(),
                uint32(block.timestamp)
            );
    }

    function _getFeeGrowthGlobalsOld(
        Volatility.FeeGrowthGlobals[60] storage arr,
        uint256 index
    ) private view returns (Volatility.FeeGrowthGlobals memory) {
        uint256 target = block.timestamp - 1 hours;

        // See if the newest sample is nearest to `target`
        Volatility.FeeGrowthGlobals memory sample = arr[index];
        if (sample.timestamp <= target) return sample;

        // See if the oldest sample is nearest to `target`
        uint256 next = (index + 1) % 60;
        sample = arr[next];
        if (sample.timestamp >= target) return sample;

        // Now that we've checked the edges, we know the best sample lies somewhere within the array.
        return _binarySearch(arr, next, target);
    }

    function _binarySearch(
        Volatility.FeeGrowthGlobals[60] storage arr,
        uint256 l,
        uint256 target
    ) private view returns (Volatility.FeeGrowthGlobals memory) {
        Volatility.FeeGrowthGlobals memory beforeOrAt;
        Volatility.FeeGrowthGlobals memory atOrAfter;

        unchecked {
            uint256 r = l + 59;
            uint256 i;
            while (true) {
                i = (l + r) / 2;

                beforeOrAt = arr[i % 60];
                atOrAfter = arr[(i + 1) % 60];

                if (isInInterval(beforeOrAt.timestamp, target, atOrAfter.timestamp)) break;
                if (beforeOrAt.timestamp <= target) {
                    l = i + 1;
                } else {
                    r = i - 1;
                }
            }

            uint256 errorA = target - beforeOrAt.timestamp;
            uint256 errorB = atOrAfter.timestamp - target;

            return errorB < errorA ? atOrAfter : beforeOrAt;
        }
    }

    function isInInterval(uint256 min, uint256 x, uint256 max) private pure returns (bool) {
        return min <= x && x <= max;
    }
}
