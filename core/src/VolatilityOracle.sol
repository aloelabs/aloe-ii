// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {IUniswapV3Pool} from "v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {
    IV_SCALE,
    IV_COLD_START,
    IV_CHANGE_PER_UPDATE,
    IV_EMA_GAIN_POS,
    IV_EMA_GAIN_NEG,
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
    event Update(IUniswapV3Pool indexed pool, uint160 sqrtMeanPriceX96, uint104 iv);

    struct LastWrite {
        uint8 index;
        uint40 time;
        uint104 oldIV;
        uint104 newIV;
    }

    mapping(IUniswapV3Pool => Volatility.PoolMetadata) public cachedMetadata;

    mapping(IUniswapV3Pool => Volatility.FeeGrowthGlobals[FEE_GROWTH_ARRAY_LENGTH]) public feeGrowthGlobals;

    mapping(IUniswapV3Pool => LastWrite) public lastWrites;

    function prepare(IUniswapV3Pool pool) external {
        cachedMetadata[pool] = _getPoolMetadata(pool);

        if (lastWrites[pool].time == 0) {
            feeGrowthGlobals[pool][0] = _getFeeGrowthGlobalsNow(pool);
            lastWrites[pool] = LastWrite(0, uint40(block.timestamp), IV_COLD_START, IV_COLD_START);
        }
    }

    function update(IUniswapV3Pool pool, uint40 seed) external returns (uint56, uint160, uint256) {
        unchecked {
            // Read `lastWrite` info from storage
            LastWrite memory lastWrite = lastWrites[pool];
            require(lastWrite.time > 0);

            // We need to call `Oracle.consult` even if we're going to return early, so go ahead and do it
            (uint56 metric, uint160 sqrtMeanPriceX96) = Oracle.consult(pool, seed);

            // If fewer than `FEE_GROWTH_SAMPLE_PERIOD` seconds have elapsed, return early.
            // We still fetch the latest TWAP, but we do not sample feeGrowthGlobals or update IV.
            if (block.timestamp - lastWrite.time < FEE_GROWTH_SAMPLE_PERIOD) {
                return (metric, sqrtMeanPriceX96, _interpolateIV(lastWrite));
            }

            // Populate `FeeGrowthGlobals`
            Volatility.FeeGrowthGlobals[FEE_GROWTH_ARRAY_LENGTH] storage arr = feeGrowthGlobals[pool];
            Volatility.FeeGrowthGlobals memory a = _getFeeGrowthGlobalsOld(arr, lastWrite.index);
            Volatility.FeeGrowthGlobals memory b = _getFeeGrowthGlobalsNow(pool);

            // Bring `lastWrite` forward so it's essentially "currentWrite"
            lastWrite.index = uint8((lastWrite.index + 1) % FEE_GROWTH_ARRAY_LENGTH);
            lastWrite.time = uint40(block.timestamp);
            lastWrite.oldIV = lastWrite.newIV;
            // lastWrite.newIV is updated below, iff feeGrowthGlobals samples are ≈`FEE_GROWTH_AVG_WINDOW` hours apart

            if (
                _isInInterval({
                    min: FEE_GROWTH_AVG_WINDOW - FEE_GROWTH_SAMPLE_PERIOD / 2,
                    x: b.timestamp - a.timestamp,
                    max: FEE_GROWTH_AVG_WINDOW + FEE_GROWTH_SAMPLE_PERIOD / 2
                })
            ) {
                // Update exponential moving average with a new IV estimate
                lastWrite.newIV = _ema(
                    int256(uint256(lastWrite.oldIV)),
                    int256(Volatility.estimate(cachedMetadata[pool], sqrtMeanPriceX96, a, b, IV_SCALE))
                );

                // Clamp `newIV` so it lies within [previous - maxChange, previous + maxChange]
                if (lastWrite.newIV > lastWrite.oldIV + IV_CHANGE_PER_UPDATE) {
                    lastWrite.newIV = lastWrite.oldIV + IV_CHANGE_PER_UPDATE;
                } else if (lastWrite.newIV + IV_CHANGE_PER_UPDATE < lastWrite.oldIV) {
                    lastWrite.newIV = lastWrite.oldIV - IV_CHANGE_PER_UPDATE;
                }
            }

            // Store the new feeGrowthGlobals sample and update `lastWrites`
            arr[lastWrite.index] = b;
            lastWrites[pool] = lastWrite;

            emit Update(pool, sqrtMeanPriceX96, lastWrite.newIV);
            return (metric, sqrtMeanPriceX96, lastWrite.oldIV); // `lastWrite.oldIV == _interpolateIV(lastWrite)` here
        }
    }

    function consult(IUniswapV3Pool pool, uint40 seed) external view returns (uint56, uint160, uint256) {
        (uint56 metric, uint160 sqrtMeanPriceX96) = Oracle.consult(pool, seed);
        return (metric, sqrtMeanPriceX96, _interpolateIV(lastWrites[pool]));
    }

    function _ema(int256 oldIV, int256 estimate) private pure returns (uint104) {
        unchecked {
            int256 gain = estimate > oldIV ? IV_EMA_GAIN_POS : IV_EMA_GAIN_NEG;
            return uint104(uint256(oldIV + (estimate - oldIV) / gain));
        }
    }

    function _interpolateIV(LastWrite memory lastWrite) private view returns (uint256) {
        unchecked {
            int256 deltaT = int256(block.timestamp - lastWrite.time);
            if (deltaT >= int256(FEE_GROWTH_SAMPLE_PERIOD)) return lastWrite.newIV;

            int256 oldIV = int256(uint256(lastWrite.oldIV));
            int256 newIV = int256(uint256(lastWrite.newIV));
            return uint256(oldIV + ((newIV - oldIV) * deltaT) / int256(FEE_GROWTH_SAMPLE_PERIOD));
        }
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
