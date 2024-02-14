// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

import {ClonesWithImmutableArgs} from "clones-with-immutable-args/ClonesWithImmutableArgs.sol";
import {FixedPointMathLib as SoladyMath} from "solady/utils/FixedPointMathLib.sol";
import {IUniswapV3Pool} from "v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {MAX_LEVERAGE, LIQUIDATION_INCENTIVE} from "aloe-ii-core/libraries/constants/Constants.sol";
import {Assets, Prices} from "aloe-ii-core/libraries/BalanceSheet.sol";
import {square, mulDiv128, mulDiv128Up} from "aloe-ii-core/libraries/MulDiv.sol";
import {Borrower} from "aloe-ii-core/Borrower.sol";
import {Factory} from "aloe-ii-core/Factory.sol";

import {Uniswap} from "./libraries/Uniswap.sol";

contract BorrowerLens {
    using SoladyMath for uint256;
    using Uniswap for Uniswap.Position;

    function predictBorrowerAddress(
        IUniswapV3Pool pool,
        address owner,
        bytes12 salt,
        address caller,
        Factory factory
    ) external view returns (address borrower) {
        (, , Borrower implementation) = factory.getMarket(pool);

        borrower = ClonesWithImmutableArgs.predictDeterministicAddress(
            address(implementation),
            bytes32(bytes.concat(bytes20(caller), salt)),
            address(factory),
            abi.encodePacked(owner)
        );
    }

    /// @dev Mirrors the logic in `BalanceSheet.isHealthy`, but returns numbers instead of a boolean
    function getHealth(Borrower account) external view returns (uint256 healthA, uint256 healthB) {
        (Prices memory prices, , , ) = account.getPrices(1 << 32);
        Assets memory assets = account.getAssets();
        (uint256 liabilities0, uint256 liabilities1) = account.getLiabilities();

        unchecked {
            uint256 augmented0;
            uint256 augmented1;

            // The optimizer eliminates the conditional in `divUp`; don't worry about gas golfing that
            augmented0 =
                liabilities0 +
                liabilities0.divUp(MAX_LEVERAGE) +
                liabilities0.zeroFloorSub(assets.amount0AtA).divUp(LIQUIDATION_INCENTIVE);
            augmented1 =
                liabilities1 +
                liabilities1.divUp(MAX_LEVERAGE) +
                liabilities1.zeroFloorSub(assets.amount1AtA).divUp(LIQUIDATION_INCENTIVE);

            healthA = _health(prices.a, assets.amount0AtA, assets.amount1AtA, augmented0, augmented1);

            augmented0 =
                liabilities0 +
                liabilities0.divUp(MAX_LEVERAGE) +
                liabilities0.zeroFloorSub(assets.amount0AtB).divUp(LIQUIDATION_INCENTIVE);
            augmented1 =
                liabilities1 +
                liabilities1.divUp(MAX_LEVERAGE) +
                liabilities1.zeroFloorSub(assets.amount1AtB).divUp(LIQUIDATION_INCENTIVE);

            healthB = _health(prices.b, assets.amount0AtB, assets.amount1AtB, augmented0, augmented1);
        }
    }

    function isInUse(Borrower borrower) external view returns (bool, IUniswapV3Pool) {
        IUniswapV3Pool pool = borrower.UNISWAP_POOL();

        if (borrower.getUniswapPositions().length > 0) return (true, pool);
        if (borrower.TOKEN0().balanceOf(address(borrower)) > 0) return (true, pool);
        if (borrower.TOKEN1().balanceOf(address(borrower)) > 0) return (true, pool);
        if (borrower.LENDER0().borrowBalanceStored(address(borrower)) > 0) return (true, pool);
        if (borrower.LENDER1().borrowBalanceStored(address(borrower)) > 0) return (true, pool);

        return (false, pool);
    }

    function getUniswapPositions(
        Borrower account
    ) external view returns (int24[] memory positions, uint128[] memory liquidity, uint256[] memory fees) {
        IUniswapV3Pool pool = account.UNISWAP_POOL();
        Uniswap.FeeComputationCache memory c;
        {
            (, int24 tick, , , , , ) = pool.slot0();
            c = Uniswap.FeeComputationCache(tick, pool.feeGrowthGlobal0X128(), pool.feeGrowthGlobal1X128());
        }

        positions = account.getUniswapPositions();
        liquidity = new uint128[](positions.length >> 1);
        fees = new uint256[](positions.length);

        unchecked {
            for (uint256 i = 0; i < positions.length; i += 2) {
                // Load lower and upper ticks from the `positions` array
                int24 l = positions[i];
                int24 u = positions[i + 1];

                Uniswap.Position memory position = Uniswap.Position(l, u);
                Uniswap.PositionInfo memory info = position.info(pool, address(account));

                (uint256 temp0, uint256 temp1) = position.fees(pool, info, c);

                liquidity[i >> 1] = info.liquidity;
                fees[i] = temp0;
                fees[i + 1] = temp1;
            }
        }
    }

    function _health(
        uint160 sqrtPriceX96,
        uint256 assets0,
        uint256 assets1,
        uint256 liabilities0,
        uint256 liabilities1
    ) private pure returns (uint256 health) {
        uint256 priceX128 = square(sqrtPriceX96);
        uint256 liabilities = liabilities1 + mulDiv128Up(liabilities0, priceX128);
        uint256 assets = assets1 + mulDiv128(assets0, priceX128);

        health = liabilities > 0 ? (assets * 1e18) / liabilities : 1000e18;
    }
}
