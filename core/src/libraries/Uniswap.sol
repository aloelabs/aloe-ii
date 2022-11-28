// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.15;

import {Math} from "openzeppelin-contracts/utils/math/Math.sol";
import "v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {FixedPoint128} from "./FixedPoint128.sol";
import {LiquidityAmounts} from "./LiquidityAmounts.sol";
import {TickMath} from "./TickMath.sol";

library Uniswap {
    struct Position {
        // the lower tick of a position
        int24 lower;
        // the upper tick of a position
        int24 upper;
    }

    struct PositionInfo {
        // the amount of liquidity in the position
        uint128 liquidity;
        // the fee growth of token0 inside the tick range as of the last mint/burn/poke
        uint256 feeGrowthInside0LastX128;
        // the fee growth of token1 inside the tick range as of the last mint/burn/poke
        uint256 feeGrowthInside1LastX128;
        // the computed amount of token0 owed to the position as of the last mint/burn/poke
        uint128 tokensOwed0;
        // the computed amount of token1 owed to the position as of the last mint/burn/poke
        uint128 tokensOwed1;
    }

    struct FeeComputationCache {
        int24 currentTick;
        uint256 feeGrowthGlobal0X128;
        uint256 feeGrowthGlobal1X128;
    }

    /// @dev Wrapper around `IUniswapV3Pool.positions()`.
    function info(
        Position memory position,
        IUniswapV3Pool pool
    ) internal view returns (PositionInfo memory positionInfo) {
        (
            positionInfo.liquidity,
            positionInfo.feeGrowthInside0LastX128,
            positionInfo.feeGrowthInside1LastX128,
            positionInfo.tokensOwed0,
            positionInfo.tokensOwed1
        ) = pool.positions(keccak256(abi.encodePacked(address(this), position.lower, position.upper)));
    }

    function fees(
        Position memory position,
        IUniswapV3Pool pool,
        PositionInfo memory positionInfo,
        FeeComputationCache memory c
    ) internal view returns (uint256 amount0, uint256 amount1) {
        (, , uint256 feeGrowthOutsideL0X128, uint256 feeGrowthOutsideL1X128, , , , ) = pool.ticks(position.lower);
        (, , uint256 feeGrowthOutsideU0X128, uint256 feeGrowthOutsideU1X128, , , , ) = pool.ticks(position.upper);

        uint256 feeGrowthInside0X128;
        uint256 feeGrowthInside1X128;
        unchecked {
            if (c.currentTick < position.lower) {
                feeGrowthInside0X128 = feeGrowthOutsideL0X128 - feeGrowthOutsideU0X128;
                feeGrowthInside1X128 = feeGrowthOutsideL1X128 - feeGrowthOutsideU1X128;
            } else if (c.currentTick < position.upper) {
                feeGrowthInside0X128 = c.feeGrowthGlobal0X128 - feeGrowthOutsideL0X128 - feeGrowthOutsideU0X128;
                feeGrowthInside1X128 = c.feeGrowthGlobal1X128 - feeGrowthOutsideL1X128 - feeGrowthOutsideU1X128;
            } else {
                feeGrowthInside0X128 = feeGrowthOutsideU0X128 - feeGrowthOutsideL0X128;
                feeGrowthInside1X128 = feeGrowthOutsideU1X128 - feeGrowthOutsideL1X128;
            }
        }

        return _fees(positionInfo, feeGrowthInside0X128, feeGrowthInside1X128);
    }

    // ⬆️⬆️⬆️⬆️ VIEW FUNCTIONS ⬆️⬆️⬆️⬆️  ------------------------------------------------------------------------------
    // ⬇️⬇️⬇️⬇️ PURE FUNCTIONS ⬇️⬇️⬇️⬇️  ------------------------------------------------------------------------------

    /// @dev Wrapper around `LiquidityAmounts.getLiquidityForAmount0()`.
    function liquidityForAmount0(Position memory position, uint256 amount0) internal pure returns (uint128) {
        return
            LiquidityAmounts.getLiquidityForAmount0(
                TickMath.getSqrtRatioAtTick(position.lower),
                TickMath.getSqrtRatioAtTick(position.upper),
                amount0
            );
    }

    /// @dev Wrapper around `LiquidityAmounts.getLiquidityForAmount1()`.
    function liquidityForAmount1(Position memory position, uint256 amount1) internal pure returns (uint128) {
        return
            LiquidityAmounts.getLiquidityForAmount1(
                TickMath.getSqrtRatioAtTick(position.lower),
                TickMath.getSqrtRatioAtTick(position.upper),
                amount1
            );
    }

    /// @dev Wrapper around `LiquidityAmounts.getLiquidityForAmounts()`.
    function liquidityForAmounts(
        Position memory position,
        uint160 sqrtPriceX96,
        uint256 amount0,
        uint256 amount1
    ) internal pure returns (uint128) {
        return
            LiquidityAmounts.getLiquidityForAmounts(
                sqrtPriceX96,
                TickMath.getSqrtRatioAtTick(position.lower),
                TickMath.getSqrtRatioAtTick(position.upper),
                amount0,
                amount1
            );
    }

    /// @dev Wrapper around `LiquidityAmounts.getAmountsForLiquidity()`.
    function amountsForLiquidity(
        Position memory position,
        uint160 sqrtPriceX96,
        uint128 liquidity
    ) internal pure returns (uint256, uint256) {
        return
            LiquidityAmounts.getAmountsForLiquidity(
                sqrtPriceX96,
                TickMath.getSqrtRatioAtTick(position.lower),
                TickMath.getSqrtRatioAtTick(position.upper),
                liquidity
            );
    }

    /// @dev Wrapper around `LiquidityAmounts.getValueOfLiquidity()`
    function valueOfLiquidity(
        Position memory position,
        uint160 sqrtPriceX96,
        uint128 liquidity
    ) internal pure returns (uint256) {
        (uint256 value0, uint256 value1) = LiquidityAmounts.getValueOfLiquidity(
            sqrtPriceX96,
            TickMath.getSqrtRatioAtTick(position.lower),
            TickMath.getSqrtRatioAtTick(position.upper),
            liquidity
        );
        unchecked {
            return value0 + value1;
        }
    }

    function _fees(
        PositionInfo memory positionInfo,
        uint256 feeGrowthInside0X128,
        uint256 feeGrowthInside1X128
    ) private pure returns (uint256 amount0, uint256 amount1) {
        unchecked {
            amount0 =
                positionInfo.tokensOwed0 +
                Math.mulDiv(
                    feeGrowthInside0X128 - positionInfo.feeGrowthInside0LastX128,
                    positionInfo.liquidity,
                    FixedPoint128.Q128
                );

            amount1 =
                positionInfo.tokensOwed1 +
                Math.mulDiv(
                    feeGrowthInside1X128 - positionInfo.feeGrowthInside1LastX128,
                    positionInfo.liquidity,
                    FixedPoint128.Q128
                );
        }
    }
}
