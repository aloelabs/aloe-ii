// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

import {Uniswap} from "aloe-ii-core/libraries/Uniswap.sol";

import {Borrower, IUniswapV3Pool} from "aloe-ii-core/Borrower.sol";

contract BorrowerLens {
    using Uniswap for Uniswap.Position;

    function getLiabilities(Borrower account) external view returns (uint256 amount0, uint256 amount1) {
        amount0 = account.LENDER0().borrowBalance(address(account));
        amount1 = account.LENDER1().borrowBalance(address(account));
    }

    function getAssets(
        Borrower account,
        bool includeUniswapFees
    ) external view returns (uint256, uint256, uint256, uint256) {
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

            int24[] memory positions = account.getUniswapPositions();
            uint256 count = positions.length;

            unchecked {
                for (uint256 i; i < count; i += 2) {
                    // Load lower and upper ticks from the `positions` array
                    int24 l = positions[i];
                    int24 u = positions[i + 1];

                    Uniswap.Position memory position = Uniswap.Position(l, u);
                    Uniswap.PositionInfo memory info = position.info(pool, address(account));

                    uint256 temp0;
                    uint256 temp1;

                    if (includeUniswapFees) {
                        (temp0, temp1) = position.fees(pool, info, c);
                        uni0 += temp0;
                        uni1 += temp1;
                    }

                    (temp0, temp1) = position.amountsForLiquidity(sqrtPriceX96, info.liquidity);
                    uni0 += temp0;
                    uni1 += temp1;
                }
            }
        }

        return (account.TOKEN0().balanceOf(address(account)), account.TOKEN1().balanceOf(address(account)), uni0, uni1);
    }

    function getUniswapPositions(
        Borrower account
    ) external view returns (bytes32[] memory keys, uint256[] memory fees) {
        IUniswapV3Pool pool = account.UNISWAP_POOL();
        Uniswap.FeeComputationCache memory c;
        {
            (, int24 tick, , , , , ) = pool.slot0();
            c = Uniswap.FeeComputationCache(tick, pool.feeGrowthGlobal0X128(), pool.feeGrowthGlobal1X128());
        }

        int24[] memory positions = account.getUniswapPositions();
        keys = new bytes32[](positions.length >> 1);
        fees = new uint256[](positions.length);

        unchecked {
            for (uint256 i = 0; i < positions.length; i += 2) {
                Uniswap.Position memory position = Uniswap.Position(positions[i], positions[i + 1]);
                Uniswap.PositionInfo memory info = position.info(pool, address(account));

                (uint256 temp0, uint256 temp1) = position.fees(pool, info, c);

                keys[i >> 1] = keccak256(abi.encodePacked(address(account), position.lower, position.upper));
                fees[i] = temp0;
                fees[i + 1] = temp1;
            }
        }
    }
}
