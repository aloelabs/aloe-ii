// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.15;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import "./FixedPoint128.sol";
import "./LiquidityAmounts.sol";
import "./TickMath.sol";

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

    /// @dev Do zero-burns to poke the Uniswap pools so earned fees are updated
    function poke(IUniswapV3Pool pool, Position memory position) internal {
        if (position.lower == position.upper) return;
        (uint128 liquidity, , , , ) = info(pool, position);
        if (liquidity != 0) {
            pool.burn(position.lower, position.upper, 0);
        }
    }

    /**
     * @notice Amounts of TOKEN0 and TOKEN1 held in vault's position. Includes
     * owed fees, except those accrued since last poke.
     */
    function collectableAmountsAsOfLastPoke(
        IUniswapV3Pool pool,
        Position memory position,
        uint160 sqrtPriceX96
    )
        internal
        view
        returns (
            uint256,
            uint256,
            uint128
        )
    {
        if (position.lower == position.upper) return (0, 0, 0);

        (uint128 liquidity, , , uint128 earnable0, uint128 earnable1) = info(pool, position);
        (uint256 burnable0, uint256 burnable1) = amountsForLiquidity(position, sqrtPriceX96, liquidity);

        return (burnable0 + earnable0, burnable1 + earnable1, liquidity);
    }

    /// @dev Wrapper around `IUniswapV3Pool.positions()`.
    function info(IUniswapV3Pool pool, Position memory position)
        internal
        view
        returns (
            uint128, // liquidity
            uint256, // feeGrowthInside0LastX128
            uint256, // feeGrowthInside1LastX128
            uint128, // tokensOwed0
            uint128 // tokensOwed1
        )
    {
        return pool.positions(keccak256(abi.encodePacked(address(this), position.lower, position.upper)));
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

    struct FeeParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        uint256 positionFeeGrowthInside0LastX128;
        uint256 positionFeeGrowthInside1LastX128;
        uint256 tokensOwed0;
        uint256 tokensOwed1;
    }

    /// @notice Calculates the total fees owed to the token owner
    /// @return amount0 The amount of fees owed in token0
    /// @return amount1 The amount of fees owed in token1
    function fees(
        IUniswapV3Pool pool,
        Position memory position,
        int24 currentTick,
        uint256 feeGrowthGlobal0X128,
        uint256 feeGrowthGlobal1X128
    ) internal view returns (uint256 amount0, uint256 amount1) {
        PositionInfo memory positionInfo;
        (
            positionInfo.liquidity,
            positionInfo.feeGrowthInside0LastX128,
            positionInfo.feeGrowthInside1LastX128,
            positionInfo.tokensOwed0,
            positionInfo.tokensOwed1
        ) = info(pool, position);

        return
            _fees(
                pool,
                position,
                positionInfo,
                currentTick,
                feeGrowthGlobal0X128,
                feeGrowthGlobal1X128
            );
    }

    function _fees(
        IUniswapV3Pool pool,
        Position memory position,
        PositionInfo memory positionInfo,
        int24 currentTick,
        uint256 feeGrowthGlobal0X128,
        uint256 feeGrowthGlobal1X128
    ) private view returns (uint256 amount0, uint256 amount1) {
        (uint256 poolFeeGrowthInside0LastX128, uint256 poolFeeGrowthInside1LastX128) = _getFeeGrowthInside(
            pool,
            position,
            currentTick,
            feeGrowthGlobal0X128,
            feeGrowthGlobal1X128
        );

        unchecked {
            amount0 =
                FullMath.mulDiv(
                    poolFeeGrowthInside0LastX128 - positionInfo.feeGrowthInside0LastX128,
                    positionInfo.liquidity,
                    FixedPoint128.Q128
                ) +
                positionInfo.tokensOwed0;

            amount1 =
                FullMath.mulDiv(
                    poolFeeGrowthInside1LastX128 - positionInfo.feeGrowthInside1LastX128,
                    positionInfo.liquidity,
                    FixedPoint128.Q128
                ) +
                positionInfo.tokensOwed1;
        }
    }

    function _getFeeGrowthInside(
        IUniswapV3Pool pool,
        Position memory position,
        int24 currentTick,
        uint256 feeGrowthGlobal0X128,
        uint256 feeGrowthGlobal1X128
    ) private view returns (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) {
        (, , uint256 feeGrowthOutsideL0X128, uint256 feeGrowthOutsideL1X128, , , , ) = pool.ticks(position.lower);
        (, , uint256 feeGrowthOutsideU0X128, uint256 feeGrowthOutsideU1X128, , , , ) = pool.ticks(position.upper);

        unchecked {
            if (currentTick < position.lower) {
                feeGrowthInside0X128 = feeGrowthOutsideL0X128 - feeGrowthOutsideU0X128;
                feeGrowthInside1X128 = feeGrowthOutsideL1X128 - feeGrowthOutsideU1X128;
            } else if (currentTick < position.upper) {
                feeGrowthInside0X128 = feeGrowthGlobal0X128 - feeGrowthOutsideL0X128 - feeGrowthOutsideU0X128;
                feeGrowthInside1X128 = feeGrowthGlobal1X128 - feeGrowthOutsideL1X128 - feeGrowthOutsideU1X128;
            } else {
                feeGrowthInside0X128 = feeGrowthOutsideU0X128 - feeGrowthOutsideL0X128;
                feeGrowthInside1X128 = feeGrowthOutsideU1X128 - feeGrowthOutsideL1X128;
            }
        }
    }
}
