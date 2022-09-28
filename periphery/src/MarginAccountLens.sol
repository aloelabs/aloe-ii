// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

import "aloe-ii-core/libraries/Uniswap.sol";

import "aloe-ii-core/MarginAccount.sol";

contract MarginAccountLens {
    using Uniswap for Uniswap.Position;

    function getLiabilities(MarginAccount account) external view returns (uint256 amount0, uint256 amount1) {
        amount0 = Kitty(account.KITTY0()).borrowBalanceCurrent(address(account));
        amount1 = Kitty(account.KITTY1()).borrowBalanceCurrent(address(account));
    }

    function getAssets(MarginAccount account)
        external
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        uint256 uni0;
        uint256 uni1;

        {
            IUniswapV3Pool pool = account.UNISWAP_POOL();
            (uint160 sqrtPriceX96, int24 tick, , , , , ) = pool.slot0();
            Uniswap.FeeComputationCache memory c = Uniswap.FeeComputationCache(
                tick,
                pool.feeGrowthGlobal0X128(),
                pool.feeGrowthGlobal1X128()
            );

            Uniswap.Position[] memory positions = account.getUniswapPositions();

            for (uint256 i = 0; i < positions.length; i++) {
                bytes32 key = keccak256(abi.encodePacked(address(account), positions[i].lower, positions[i].upper));
                Uniswap.PositionInfo memory info = _getInfo(pool, key);

                (uint256 temp0, uint256 temp1) = positions[i].fees(pool, info, c);
                uni0 += temp0;
                uni1 += temp1;

                (temp0, temp1) = positions[i].amountsForLiquidity(sqrtPriceX96, info.liquidity);
                uni0 += temp0;
                uni1 += temp1;
            }
        }

        return (
            account.TOKEN0().balanceOf(address(account)),
            account.TOKEN1().balanceOf(address(account)),
            Kitty(account.KITTY0()).balanceOfUnderlying(address(account)),
            Kitty(account.KITTY1()).balanceOfUnderlying(address(account)),
            uni0,
            uni1
        );
    }

    function _getInfo(IUniswapV3Pool pool, bytes32 key)
        private
        view
        returns (Uniswap.PositionInfo memory positionInfo)
    {
        (
            positionInfo.liquidity,
            positionInfo.feeGrowthInside0LastX128,
            positionInfo.feeGrowthInside1LastX128,
            positionInfo.tokensOwed0,
            positionInfo.tokensOwed1
        ) = pool.positions(key);
    }
}
