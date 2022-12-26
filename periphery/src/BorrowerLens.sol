// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

import "aloe-ii-core/libraries/Uniswap.sol";

import "aloe-ii-core/Borrower.sol";

contract BorrowerLens {
    using Uniswap for Uniswap.Position;

    function getLiabilities(Borrower account) external view returns (uint256 amount0, uint256 amount1) {
        amount0 = Lender(account.LENDER0()).borrowBalance(address(account));
        amount1 = Lender(account.LENDER1()).borrowBalance(address(account));
    }

    function getAssets(Borrower account) external view returns (uint256, uint256, uint256, uint256, uint256, uint256) {
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
            Lender(account.LENDER0()).underlyingBalance(address(account)),
            Lender(account.LENDER1()).underlyingBalance(address(account)),
            uni0,
            uni1
        );
    }

    function getUniswapPositions(
        Borrower account
    ) external view returns (bytes32[] memory keys, uint256[] memory fees) {
        IUniswapV3Pool pool = account.UNISWAP_POOL();
        (, int24 tick, , , , , ) = pool.slot0();
        Uniswap.FeeComputationCache memory c = Uniswap.FeeComputationCache(
            tick,
            pool.feeGrowthGlobal0X128(),
            pool.feeGrowthGlobal1X128()
        );

        Uniswap.Position[] memory positions = account.getUniswapPositions();
        keys = new bytes32[](positions.length);
        fees = new uint256[](positions.length * 2);

        for (uint256 i = 0; i < positions.length; i++) {
            bytes32 key = keccak256(abi.encodePacked(address(account), positions[i].lower, positions[i].upper));
            Uniswap.PositionInfo memory info = _getInfo(pool, key);

            (uint256 temp0, uint256 temp1) = positions[i].fees(pool, info, c);

            keys[i] = key;
            fees[i] = temp0;
            fees[i + 1] = temp1;
        }
    }

    function _getInfo(
        IUniswapV3Pool pool,
        bytes32 key
    ) private view returns (Uniswap.PositionInfo memory positionInfo) {
        (
            positionInfo.liquidity,
            positionInfo.feeGrowthInside0LastX128,
            positionInfo.feeGrowthInside1LastX128,
            positionInfo.tokensOwed0,
            positionInfo.tokensOwed1
        ) = pool.positions(key);
    }
}
