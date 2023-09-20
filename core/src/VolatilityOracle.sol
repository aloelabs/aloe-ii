// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {IUniswapV3Pool} from "v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {
    IV_SCALE,
    IV_COLD_START,
    IV_CHANGE_PER_UPDATE,
    UNISWAP_AVG_WINDOW,
    FEE_GROWTH_AVG_WINDOW,
    FEE_GROWTH_ARRAY_LENGTH,
    FEE_GROWTH_SAMPLE_PERIOD
} from "./libraries/constants/Constants.sol";
import {Oracle} from "./libraries/Oracle.sol";
import {Volatility} from "./libraries/Volatility.sol";

/// @title VolatilityOracle
/// @author Aloe Labs, Inc.
/// @dev "Test everything; hold fast what is good." - 1 Thessalonians 5:21
contract VolatilityOracle {
    event Update(IUniswapV3Pool indexed pool, uint160 sqrtMeanPriceX96, uint256 iv);

    struct LastWrite {
        uint8 index;
        uint32 time;
        uint216 iv;
    }

    mapping(IUniswapV3Pool => Volatility.PoolMetadata) public cachedMetadata;

    mapping(IUniswapV3Pool => Volatility.FeeGrowthGlobals[FEE_GROWTH_ARRAY_LENGTH]) public feeGrowthGlobals;

    mapping(IUniswapV3Pool => LastWrite) public lastWrites;

    function prepare(IUniswapV3Pool pool) external {
        cachedMetadata[pool] = _getPoolMetadata(pool);

        if (lastWrites[pool].time == 0) {
            feeGrowthGlobals[pool][0] = _getFeeGrowthGlobalsNow(pool);
            lastWrites[pool] = LastWrite({index: 0, time: uint32(block.timestamp), iv: IV_COLD_START});
        }
    }

    function update(IUniswapV3Pool pool, uint40 seed) external returns (uint56, uint160, uint256) {
        unchecked {
            // Read `lastWrite` info from storage
            LastWrite memory lastWrite = lastWrites[pool];
            require(lastWrite.time > 0);

            // We need to call `Oracle.consult` even if we're going to return early, so go ahead and do it
            (Oracle.PoolData memory data, uint56 metric) = Oracle.consult(pool, seed);

            // If fewer than `FEE_GROWTH_SAMPLE_PERIOD` seconds have elapsed, return early.
            // We still fetch the latest TWAP, but we do not sample feeGrowthGlobals or update IV.
            if (block.timestamp - lastWrite.time < FEE_GROWTH_SAMPLE_PERIOD) {
                return (metric, data.sqrtMeanPriceX96, lastWrite.iv);
            }

            // Populate remaining `PoolData` fields
            data.oracleLookback = UNISWAP_AVG_WINDOW;
            data.tickLiquidity = pool.liquidity();

            // Populate `FeeGrowthGlobals`
            Volatility.FeeGrowthGlobals[FEE_GROWTH_ARRAY_LENGTH] storage arr = feeGrowthGlobals[pool];
            Volatility.FeeGrowthGlobals memory a = _getFeeGrowthGlobalsOld(arr, lastWrite.index);
            Volatility.FeeGrowthGlobals memory b = _getFeeGrowthGlobalsNow(pool);

            // Default to using the existing IV
            uint256 iv = lastWrite.iv;
            // Only update IV if the feeGrowthGlobals samples are approximately `FEE_GROWTH_AVG_WINDOW` hours apart
            if (
                _isInInterval({
                    min: FEE_GROWTH_AVG_WINDOW - FEE_GROWTH_SAMPLE_PERIOD / 2,
                    x: b.timestamp - a.timestamp,
                    max: FEE_GROWTH_AVG_WINDOW + FEE_GROWTH_SAMPLE_PERIOD / 2
                })
            ) {
                // Estimate, then clamp so it lies within [previous - maxChange, previous + maxChange]
                iv = Volatility.estimate(cachedMetadata[pool], data, a, b, IV_SCALE);

                if (iv > lastWrite.iv + IV_CHANGE_PER_UPDATE) iv = lastWrite.iv + IV_CHANGE_PER_UPDATE;
                else if (iv + IV_CHANGE_PER_UPDATE < lastWrite.iv) iv = lastWrite.iv - IV_CHANGE_PER_UPDATE;
            }

            // Store the new feeGrowthGlobals sample and update `lastWrites`
            uint8 next = uint8((lastWrite.index + 1) % FEE_GROWTH_ARRAY_LENGTH);
            arr[next] = b;
            lastWrites[pool] = LastWrite(next, uint32(block.timestamp), uint216(iv));

            emit Update(pool, data.sqrtMeanPriceX96, iv);
            return (metric, data.sqrtMeanPriceX96, iv);
        }
    }

    function consult(IUniswapV3Pool pool, uint40 seed) external view returns (uint56, uint160, uint256) {
        (Oracle.PoolData memory data, uint56 metric) = Oracle.consult(pool, seed);
        return (metric, data.sqrtMeanPriceX96, lastWrites[pool].iv);
    }

    function _getPoolMetadata(IUniswapV3Pool pool) private view returns (Volatility.PoolMetadata memory metadata) {
        (, , uint16 observationIndex, uint16 observationCardinality, , uint8 feeProtocol, ) = pool.slot0();
        // We want observations from `UNISWAP_AVG_WINDOW` and `UNISWAP_AVG_WINDOW * 2` seconds ago. Since observation
        // frequency varies with `pool` usage, we apply an extra 3x safety factor. If `pool` usage increases,
        // oracle cardinality may need to be increased as well. This should be monitored off-chain.
        require(
            Oracle.getMaxSecondsAgo(pool, observationIndex, observationCardinality) > UNISWAP_AVG_WINDOW * 6,
            "Aloe: cardinality"
        );

        uint24 fee = pool.fee();
        metadata.gamma0 = fee;
        metadata.gamma1 = fee;
        unchecked {
            if (feeProtocol % 16 != 0) metadata.gamma0 -= fee / (feeProtocol % 16);
            if (feeProtocol >> 4 != 0) metadata.gamma1 -= fee / (feeProtocol >> 4);
        }

        metadata.tickSpacing = pool.tickSpacing();
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
        Volatility.FeeGrowthGlobals[FEE_GROWTH_ARRAY_LENGTH] storage arr,
        uint256 index
    ) private view returns (Volatility.FeeGrowthGlobals memory) {
        uint256 target = block.timestamp - FEE_GROWTH_AVG_WINDOW;

        // See if the newest sample is nearest to `target`
        Volatility.FeeGrowthGlobals memory sample = arr[index];
        if (sample.timestamp <= target) return sample;

        // See if the oldest sample is nearest to `target`
        uint256 next = (index + 1) % FEE_GROWTH_ARRAY_LENGTH;
        sample = arr[next];
        if (sample.timestamp >= target) return sample;

        // Now that we've checked the edges, we know the best sample lies somewhere within the array.
        return _binarySearch(arr, next, target);
    }

    function _binarySearch(
        Volatility.FeeGrowthGlobals[FEE_GROWTH_ARRAY_LENGTH] storage arr,
        uint256 l,
        uint256 target
    ) private view returns (Volatility.FeeGrowthGlobals memory) {
        Volatility.FeeGrowthGlobals memory beforeOrAt;
        Volatility.FeeGrowthGlobals memory atOrAfter;

        unchecked {
            uint256 r = l + (FEE_GROWTH_ARRAY_LENGTH - 1);
            uint256 i;
            while (true) {
                i = (l + r) / 2;

                beforeOrAt = arr[i % FEE_GROWTH_ARRAY_LENGTH];
                atOrAfter = arr[(i + 1) % FEE_GROWTH_ARRAY_LENGTH];

                if (_isInInterval(beforeOrAt.timestamp, target, atOrAfter.timestamp)) break;

                if (target < beforeOrAt.timestamp) r = i - 1;
                else l = i + 1;
            }

            uint256 errorA = target - beforeOrAt.timestamp;
            uint256 errorB = atOrAfter.timestamp - target;

            return errorB < errorA ? atOrAfter : beforeOrAt;
        }
    }

    function _isInInterval(uint256 min, uint256 x, uint256 max) private pure returns (bool) {
        return min <= x && x <= max;
    }
}
