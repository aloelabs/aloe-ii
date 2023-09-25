// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {FixedPointMathLib as SoladyMath} from "solady/utils/FixedPointMathLib.sol";
import {IUniswapV3Pool} from "v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {MAX_LEVERAGE, LIQUIDATION_INCENTIVE} from "aloe-ii-core/libraries/constants/Constants.sol";
import {Assets, Prices} from "aloe-ii-core/libraries/BalanceSheet.sol";
import {LiquidityAmounts} from "aloe-ii-core/libraries/LiquidityAmounts.sol";
import {square, mulDiv128, mulDiv128Up} from "aloe-ii-core/libraries/MulDiv.sol";
import {TickMath} from "aloe-ii-core/libraries/TickMath.sol";
import {Borrower} from "aloe-ii-core/Borrower.sol";

import {Uniswap} from "./libraries/Uniswap.sol";

contract BorrowerLens {
    using SoladyMath for uint256;
    using Uniswap for Uniswap.Position;

    /// @dev Mirrors the logic in `BalanceSheet.isHealthy`, but returns numbers instead of a boolean
    function getHealth(
        Borrower account,
        bool previewInterest
    ) external view returns (uint256 healthA, uint256 healthB) {
        (Prices memory prices, ) = account.getPrices(1 << 32);
        Assets memory mem = _getAssets(account, account.getUniswapPositions(), prices);
        (uint256 liabilities0, uint256 liabilities1) = getLiabilities(account, previewInterest);

        unchecked {
            // The optimizer eliminates the conditional in `divUp`; don't worry about gas golfing that
            liabilities0 +=
                liabilities0.divUp(MAX_LEVERAGE) +
                liabilities0.zeroFloorSub(mem.fixed0 + mem.fluid0C).divUp(LIQUIDATION_INCENTIVE);
            liabilities1 +=
                liabilities1.divUp(MAX_LEVERAGE) +
                liabilities1.zeroFloorSub(mem.fixed1 + mem.fluid1C).divUp(LIQUIDATION_INCENTIVE);
        }

        // combine
        uint256 priceX128;
        uint256 liabilities;
        uint256 assets;

        priceX128 = square(prices.a);
        liabilities = liabilities1 + mulDiv128Up(liabilities0, priceX128);
        assets = mem.fluid1A + mem.fixed1 + mulDiv128(mem.fixed0, priceX128);
        healthA = liabilities > 0 ? (assets * 1e18) / liabilities : 1000e18;

        priceX128 = square(prices.b);
        liabilities = liabilities1 + mulDiv128Up(liabilities0, priceX128);
        assets = mem.fluid1B + mem.fixed1 + mulDiv128(mem.fixed0, priceX128);
        healthB = liabilities > 0 ? (assets * 1e18) / liabilities : 1000e18;
    }

    function getUniswapFees(Borrower account) external view returns (bytes32[] memory keys, uint256[] memory fees) {
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
                // Load lower and upper ticks from the `positions` array
                int24 l = positions[i];
                int24 u = positions[i + 1];

                Uniswap.Position memory position = Uniswap.Position(l, u);
                Uniswap.PositionInfo memory info = position.info(pool, address(account));

                (uint256 temp0, uint256 temp1) = position.fees(pool, info, c);

                keys[i >> 1] = keccak256(abi.encodePacked(address(account), l, u));
                fees[i] = temp0;
                fees[i + 1] = temp1;
            }
        }
    }

    function getAssets(Borrower account) external view returns (Assets memory) {
        (Prices memory prices, ) = account.getPrices(1 << 32);
        return _getAssets(account, account.getUniswapPositions(), prices);
    }

    function getLiabilities(
        Borrower account,
        bool previewInterest
    ) public view returns (uint256 amount0, uint256 amount1) {
        if (previewInterest) {
            amount0 = account.LENDER0().borrowBalance(address(account));
            amount1 = account.LENDER1().borrowBalance(address(account));
        } else {
            amount0 = account.LENDER0().borrowBalanceStored(address(account));
            amount1 = account.LENDER1().borrowBalanceStored(address(account));
        }
    }

    /* solhint-disable code-complexity */

    /// @dev Mirrors the logic in `Borrower._getAssets`
    function _getAssets(
        Borrower account,
        int24[] memory positions,
        Prices memory prices
    ) private view returns (Assets memory assets) {
        assets.fixed0 = account.TOKEN0().balanceOf(address(account));
        assets.fixed1 = account.TOKEN1().balanceOf(address(account));

        IUniswapV3Pool pool = account.UNISWAP_POOL();

        uint256 count = positions.length;
        unchecked {
            for (uint256 i; i < count; i += 2) {
                // Load lower and upper ticks from the `positions` array
                int24 l = positions[i];
                int24 u = positions[i + 1];
                // Fetch amount of `liquidity` in the position
                (uint128 liquidity, , , , ) = pool.positions(keccak256(abi.encodePacked(address(account), l, u)));

                if (liquidity == 0) continue;

                // Compute lower and upper sqrt ratios
                uint160 L = TickMath.getSqrtRatioAtTick(l);
                uint160 U = TickMath.getSqrtRatioAtTick(u);

                // Compute the value of `liquidity` (in terms of token1) at both probe prices
                assets.fluid1A += LiquidityAmounts.getValueOfLiquidity(prices.a, L, U, liquidity);
                assets.fluid1B += LiquidityAmounts.getValueOfLiquidity(prices.b, L, U, liquidity);

                // Compute what amounts underlie `liquidity` at the current TWAP
                (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(prices.c, L, U, liquidity);
                assets.fluid0C += amount0;
                assets.fluid1C += amount1;
            }
        }
    }

    /* solhint-enable code-complexity */
}
