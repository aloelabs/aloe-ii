// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.17;

import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";
import {SafeCastLib} from "solmate/utils/SafeCastLib.sol";

import {Q96} from "./constants/Q.sol";

/// @title LiquidityAmounts
/// @notice Provides functions for computing liquidity amounts from token amounts and prices
/// @author Aloe Labs, Inc.
/// @author Modified from Uniswap (https://github.com/Uniswap/v3-periphery/blob/main/contracts/libraries/LiquidityAmounts.sol)
library LiquidityAmounts {
    /// @notice Computes the amount of token0 for a given amount of liquidity and a price range
    /// @param sqrtRatioAX96 A sqrt price representing the first tick boundary
    /// @param sqrtRatioBX96 A sqrt price representing the second tick boundary
    /// @param liquidity The liquidity being valued
    /// @return amount0 The amount of token0. Will fit in a uint224 if you need it to
    function getAmount0ForLiquidity(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint128 liquidity
    ) internal pure returns (uint256 amount0) {
        assert(sqrtRatioAX96 <= sqrtRatioBX96);

        amount0 = Math.mulDiv(uint256(liquidity) << 96, sqrtRatioBX96 - sqrtRatioAX96, sqrtRatioBX96) / sqrtRatioAX96;
    }

    /// @notice Computes the amount of token1 for a given amount of liquidity and a price range
    /// @param sqrtRatioAX96 A sqrt price representing the first tick boundary
    /// @param sqrtRatioBX96 A sqrt price representing the second tick boundary
    /// @param liquidity The liquidity being valued
    /// @return amount1 The amount of token1. Will fit in a uint192 if you need it to
    function getAmount1ForLiquidity(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint128 liquidity
    ) internal pure returns (uint256 amount1) {
        assert(sqrtRatioAX96 <= sqrtRatioBX96);

        amount1 = Math.mulDiv(liquidity, sqrtRatioBX96 - sqrtRatioAX96, Q96);
    }

    /// @notice Computes the token0 and token1 value for a given amount of liquidity, the current
    /// pool prices and the prices at the tick boundaries
    /// @param sqrtRatioX96 A sqrt price representing the current pool prices
    /// @param sqrtRatioAX96 A sqrt price representing the first tick boundary
    /// @param sqrtRatioBX96 A sqrt price representing the second tick boundary
    /// @param liquidity The liquidity being valued
    /// @return amount0 The amount of token0
    /// @return amount1 The amount of token1
    function getAmountsForLiquidity(
        uint160 sqrtRatioX96,
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint128 liquidity
    ) internal pure returns (uint256 amount0, uint256 amount1) {
        assert(sqrtRatioAX96 <= sqrtRatioBX96);

        if (sqrtRatioX96 <= sqrtRatioAX96) {
            amount0 = getAmount0ForLiquidity(sqrtRatioAX96, sqrtRatioBX96, liquidity);
        } else if (sqrtRatioX96 < sqrtRatioBX96) {
            amount0 = getAmount0ForLiquidity(sqrtRatioX96, sqrtRatioBX96, liquidity);
            amount1 = getAmount1ForLiquidity(sqrtRatioAX96, sqrtRatioX96, liquidity);
        } else {
            amount1 = getAmount1ForLiquidity(sqrtRatioAX96, sqrtRatioBX96, liquidity);
        }
    }

    /// @notice Computes the value of each portion of the liquidity in terms of token1
    /// @dev Each return value can fit in a uint192 if necessary
    /// @param sqrtRatioX96 A sqrt price representing the current pool prices
    /// @param sqrtRatioAX96 A sqrt price representing the lower tick boundary
    /// @param sqrtRatioBX96 A sqrt price representing the upper tick boundary
    /// @param liquidity The liquidity being valued
    /// @return value0 The value of amount0 underlying `liquidity`, in terms of token1
    /// @return value1 The amount of token1
    function getValuesOfLiquidity(
        uint160 sqrtRatioX96,
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint128 liquidity
    ) internal pure returns (uint256 value0, uint256 value1) {
        assert(sqrtRatioAX96 <= sqrtRatioBX96);

        unchecked {
            if (sqrtRatioX96 <= sqrtRatioAX96) {
                uint256 priceX96 = Math.mulDiv(sqrtRatioX96, sqrtRatioX96, Q96);

                value0 = Math.mulDiv(
                    priceX96,
                    Math.mulDiv(uint256(liquidity) << 96, sqrtRatioBX96 - sqrtRatioAX96, sqrtRatioBX96),
                    uint256(sqrtRatioAX96) << 96
                );
            } else if (sqrtRatioX96 < sqrtRatioBX96) {
                uint256 numerator = Math.mulDiv(sqrtRatioX96, sqrtRatioBX96 - sqrtRatioX96, Q96);

                value0 = Math.mulDiv(liquidity, numerator, sqrtRatioBX96);
                value1 = Math.mulDiv(liquidity, sqrtRatioX96 - sqrtRatioAX96, Q96);
            } else {
                value1 = Math.mulDiv(liquidity, sqrtRatioBX96 - sqrtRatioAX96, Q96);
            }
        }
    }

    /// @notice Computes the value of the liquidity in terms of token1
    /// @dev The return value can fit in a uint192 if necessary
    /// @param sqrtRatioX96 A sqrt price representing the current pool prices
    /// @param sqrtRatioAX96 A sqrt price representing the lower tick boundary
    /// @param sqrtRatioBX96 A sqrt price representing the upper tick boundary
    /// @param liquidity The liquidity being valued
    /// @return The value of the underlying `liquidity`, in terms of token1
    function getValueOfLiquidity(
        uint160 sqrtRatioX96,
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint128 liquidity
    ) internal pure returns (uint256) {
        (uint256 value0, uint256 value1) = getValuesOfLiquidity(sqrtRatioX96, sqrtRatioAX96, sqrtRatioBX96, liquidity);
        unchecked {
            return value0 + value1;
        }
    }
}
