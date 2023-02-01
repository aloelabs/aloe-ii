// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {MAX_LEVERAGE} from "aloe-ii-core/libraries/constants/Constants.sol";

import {Uniswap} from "./libraries/Uniswap.sol";

import "aloe-ii-core/Borrower.sol";

contract BorrowerLens {
    using Uniswap for Uniswap.Position;

    /// @dev Mirrors the logic in `BalanceSheet.isHealthy`, but returns numbers instead of a boolean
    function getHealth(
        Borrower account,
        bool previewInterest
    ) external view returns (uint256 healthA, uint256 healthB) {
        Prices memory prices = account.getPrices();
        Assets memory assets = _getAssets(account, account.getUniswapPositions(), prices);
        (uint256 liabilities0, uint256 liabilities1) = getLiabilities(account, previewInterest);

        // liquidation incentive. counted as liability because account will owe it to someone.
        // compensates liquidators for inventory risk.
        (uint256 incentive1, ) = BalanceSheet.computeLiquidationIncentive(
            assets.fixed0 + assets.fluid0C,
            assets.fixed1 + assets.fluid1C,
            liabilities0,
            liabilities1,
            prices.c
        );

        unchecked {
            liabilities0 += liabilities0 / MAX_LEVERAGE;
            liabilities1 += liabilities1 / MAX_LEVERAGE + incentive1;
        }

        // combine
        uint224 priceX96;
        uint256 liabilitiesSum;
        uint256 assetsSum;

        priceX96 = uint224(Math.mulDiv(prices.a, prices.a, Q96));
        liabilitiesSum = liabilities1 + Math.mulDiv(liabilities0, priceX96, Q96);
        assetsSum = assets.fluid1A + assets.fixed1 + Math.mulDiv(assets.fixed0, priceX96, Q96);
        healthA = liabilitiesSum > 0 ? (assetsSum * 1e18) / liabilitiesSum : 1000e18;

        priceX96 = uint224(Math.mulDiv(prices.b, prices.b, Q96));
        liabilitiesSum = liabilities1 + Math.mulDiv(liabilities0, priceX96, Q96);
        assetsSum = assets.fluid1B + assets.fixed1 + Math.mulDiv(assets.fixed0, priceX96, Q96);
        healthB = liabilitiesSum > 0 ? (assetsSum * 1e18) / liabilitiesSum : 1000e18;
    }

    function getAssets(Borrower account) external view returns (Assets memory) {
        return _getAssets(account, account.getUniswapPositions(), account.getPrices());
    }

    /* solhint-disable code-complexity */

    function _getAssets(
        Borrower account,
        int24[] memory positions_,
        Prices memory prices
    ) private view returns (Assets memory assets) {
        assets.fixed0 = account.TOKEN0().balanceOf(address(account));
        assets.fixed1 = account.TOKEN1().balanceOf(address(account));

        IUniswapV3Pool pool = account.UNISWAP_POOL();

        uint256 count = positions_.length;
        unchecked {
            for (uint256 i; i < count; i += 2) {
                // Load lower and upper ticks from the `positions_` array
                int24 l = positions_[i];
                int24 u = positions_[i + 1];
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

                // TODO: possibly need to skip fees check if `info.liquidity == 0`

                (uint256 temp0, uint256 temp1) = position.fees(pool, info, c);

                keys[i >> 1] = keccak256(abi.encodePacked(address(account), l, u));
                fees[i] = temp0;
                fees[i + 1] = temp1;
            }
        }
    }
}
