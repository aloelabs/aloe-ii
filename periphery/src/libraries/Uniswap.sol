// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";
import {SafeCastLib} from "solmate/utils/SafeCastLib.sol";
import {IUniswapV3Pool} from "v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {Q96} from "aloe-ii-core/libraries/constants/Q.sol";
import {LiquidityAmounts} from "aloe-ii-core/libraries/LiquidityAmounts.sol";
import {mulDiv96, mulDiv128} from "aloe-ii-core/libraries/MulDiv.sol";
import {TickMath} from "aloe-ii-core/libraries/TickMath.sol";

library Uniswap {
    using SafeCastLib for uint256;

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

    bytes32 private constant _INIT_CODE_HASH = 0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54;

    /// @dev Wrapper around `IUniswapV3Pool.positions()` that assumes `positions` is owned by `this`
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

    /// @dev Wrapper around `IUniswapV3Pool.positions()`.
    function info(
        Position memory position,
        IUniswapV3Pool pool,
        address owner
    ) internal view returns (PositionInfo memory positionInfo) {
        (
            positionInfo.liquidity,
            positionInfo.feeGrowthInside0LastX128,
            positionInfo.feeGrowthInside1LastX128,
            positionInfo.tokensOwed0,
            positionInfo.tokensOwed1
        ) = pool.positions(keccak256(abi.encodePacked(owner, position.lower, position.upper)));
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

    function liquidityForAmount0(Position memory position, uint256 amount0) internal pure returns (uint128) {
        return
            liquidityForAmount0(
                TickMath.getSqrtRatioAtTick(position.lower),
                TickMath.getSqrtRatioAtTick(position.upper),
                amount0
            );
    }

    /// @notice Computes the amount of liquidity received for a given amount of token0 and price range
    /// @dev Calculates amount0 * (sqrt(upper) * sqrt(lower)) / (sqrt(upper) - sqrt(lower))
    /// @param sqrtRatioAX96 A sqrt price representing the first tick boundary
    /// @param sqrtRatioBX96 A sqrt price representing the second tick boundary
    /// @param amount0 The amount0 being sent in
    /// @return liquidity The amount of returned liquidity
    function liquidityForAmount0(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint256 amount0
    ) internal pure returns (uint128 liquidity) {
        assert(sqrtRatioAX96 < sqrtRatioBX96);
        uint256 intermediate = mulDiv96(sqrtRatioAX96, sqrtRatioBX96);
        liquidity = Math.mulDiv(amount0, intermediate, sqrtRatioBX96 - sqrtRatioAX96).safeCastTo128();
    }

    function liquidityForAmount1(Position memory position, uint256 amount1) internal pure returns (uint128) {
        return
            liquidityForAmount1(
                TickMath.getSqrtRatioAtTick(position.lower),
                TickMath.getSqrtRatioAtTick(position.upper),
                amount1
            );
    }

    /// @notice Computes the amount of liquidity received for a given amount of token1 and price range
    /// @dev Calculates amount1 / (sqrt(upper) - sqrt(lower)).
    /// @param sqrtRatioAX96 A sqrt price representing the first tick boundary
    /// @param sqrtRatioBX96 A sqrt price representing the second tick boundary
    /// @param amount1 The amount1 being sent in
    /// @return liquidity The amount of returned liquidity
    function liquidityForAmount1(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint256 amount1
    ) internal pure returns (uint128 liquidity) {
        assert(sqrtRatioAX96 < sqrtRatioBX96);
        liquidity = Math.mulDiv(amount1, Q96, sqrtRatioBX96 - sqrtRatioAX96).safeCastTo128();
    }

    function liquidityForAmounts(
        Position memory position,
        uint160 sqrtPriceX96,
        uint256 amount0,
        uint256 amount1
    ) internal pure returns (uint128) {
        return
            liquidityForAmounts(
                sqrtPriceX96,
                TickMath.getSqrtRatioAtTick(position.lower),
                TickMath.getSqrtRatioAtTick(position.upper),
                amount0,
                amount1
            );
    }

    /// @notice Computes the maximum amount of liquidity received for a given amount of token0, token1, the current
    /// pool prices and the prices at the tick boundaries
    /// @param sqrtRatioX96 A sqrt price representing the current pool prices
    /// @param sqrtRatioAX96 A sqrt price representing the first tick boundary
    /// @param sqrtRatioBX96 A sqrt price representing the second tick boundary
    /// @param amount0 The amount of token0 being sent in
    /// @param amount1 The amount of token1 being sent in
    /// @return liquidity The maximum amount of liquidity received
    function liquidityForAmounts(
        uint160 sqrtRatioX96,
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint256 amount0,
        uint256 amount1
    ) internal pure returns (uint128 liquidity) {
        assert(sqrtRatioAX96 < sqrtRatioBX96);

        if (sqrtRatioX96 <= sqrtRatioAX96) {
            liquidity = liquidityForAmount0(sqrtRatioAX96, sqrtRatioBX96, amount0);
        } else if (sqrtRatioX96 < sqrtRatioBX96) {
            uint128 liquidity0 = liquidityForAmount0(sqrtRatioX96, sqrtRatioBX96, amount0);
            uint128 liquidity1 = liquidityForAmount1(sqrtRatioAX96, sqrtRatioX96, amount1);

            liquidity = liquidity0 < liquidity1 ? liquidity0 : liquidity1;
        } else {
            liquidity = liquidityForAmount1(sqrtRatioAX96, sqrtRatioBX96, amount1);
        }
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
        return
            LiquidityAmounts.getValueOfLiquidity(
                sqrtPriceX96,
                TickMath.getSqrtRatioAtTick(position.lower),
                TickMath.getSqrtRatioAtTick(position.upper),
                liquidity
            );
    }

    function computePoolAddress(
        address factory,
        address token0,
        address token1,
        uint24 fee
    ) internal pure returns (IUniswapV3Pool pool) {
        assert(token0 < token1);
        pool = IUniswapV3Pool(
            address(
                uint160(
                    uint256(
                        keccak256(
                            abi.encodePacked(
                                hex"ff",
                                factory,
                                keccak256(abi.encode(token0, token1, fee)),
                                _INIT_CODE_HASH
                            )
                        )
                    )
                )
            )
        );
    }

    function _fees(
        PositionInfo memory positionInfo,
        uint256 feeGrowthInside0X128,
        uint256 feeGrowthInside1X128
    ) private pure returns (uint256 amount0, uint256 amount1) {
        unchecked {
            amount0 =
                positionInfo.tokensOwed0 +
                mulDiv128(feeGrowthInside0X128 - positionInfo.feeGrowthInside0LastX128, positionInfo.liquidity);

            amount1 =
                positionInfo.tokensOwed1 +
                mulDiv128(feeGrowthInside1X128 - positionInfo.feeGrowthInside1LastX128, positionInfo.liquidity);
        }
    }
}
