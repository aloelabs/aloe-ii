// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.15;

import {Math} from "openzeppelin-contracts/utils/math/Math.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {FixedPoint96} from "./FixedPoint96.sol";

struct Assets {
    uint256 fixed0;
    uint256 fixed1;
    uint256 fluid1A;
    uint256 fluid1B;
    uint256 fluid0C;
    uint256 fluid1C;
}

struct Prices {
    uint160 a;
    uint160 b;
    uint160 c;
}

library BalanceSheet {
    uint256 public constant MIN_SIGMA = 2e16;

    uint256 public constant MAX_SIGMA = 15e16;

    function isHealthy(
        uint256 liabilities0,
        uint256 liabilities1,
        Assets memory mem,
        Prices memory prices
    ) internal pure returns (bool) {
        // liquidation incentive. counted as liability because account will owe it to someone.
        // compensates liquidators for inventory risk.
        uint256 liquidationIncentive = _computeLiquidationIncentive(
            mem.fixed0 + mem.fluid0C,
            mem.fixed1 + mem.fluid1C,
            liabilities0,
            liabilities1,
            prices.c
        );

        unchecked {
            liabilities0 = (liabilities0 * 1.005e18) / 1e18;
            liabilities1 = (liabilities1 * 1.005e18) / 1e18 + liquidationIncentive;
        } // TODO is unchecked safe here?

        // combine
        uint224 priceX96;
        uint256 liabilities;
        uint256 assets;

        priceX96 = uint224(Math.mulDiv(prices.a, prices.a, FixedPoint96.Q96));
        liabilities = liabilities1 + Math.mulDiv(liabilities0, priceX96, FixedPoint96.Q96);
        assets = mem.fluid1A + mem.fixed1 + Math.mulDiv(mem.fixed0, priceX96, FixedPoint96.Q96);
        if (liabilities > assets) return false;

        priceX96 = uint224(Math.mulDiv(prices.b, prices.b, FixedPoint96.Q96));
        liabilities = liabilities1 + Math.mulDiv(liabilities0, priceX96, FixedPoint96.Q96);
        assets = mem.fluid1B + mem.fixed1 + Math.mulDiv(mem.fixed0, priceX96, FixedPoint96.Q96);
        if (liabilities > assets) return false;

        return true;
    }

    function computeProbePrices(
        uint160 sqrtMeanPriceX96,
        uint256 sigma,
        uint256 n
    ) internal pure returns (uint160 a, uint160 b) {
        unchecked {
            sigma *= n;

            if (sigma < MIN_SIGMA) sigma = MIN_SIGMA;
            else if (sigma > MAX_SIGMA) sigma = MAX_SIGMA;

            a = uint160((sqrtMeanPriceX96 * FixedPointMathLib.sqrt(1e18 - sigma)) / 1e9);
            b = uint160((sqrtMeanPriceX96 * FixedPointMathLib.sqrt(1e18 + sigma)) / 1e9);
        }
    }

    function _computeLiquidationIncentive(
        uint256 assets0,
        uint256 assets1,
        uint256 liabilities0,
        uint256 liabilities1,
        uint160 sqrtMeanPriceX96
    ) private pure returns (uint256 reward1) {
        unchecked {
            uint256 meanPriceX96 = Math.mulDiv(sqrtMeanPriceX96, sqrtMeanPriceX96, FixedPoint96.Q96);

            if (liabilities0 > assets0) {
                // shortfall is the amount that cannot be directly repaid using Borrower assets at this price
                uint256 shortfall = liabilities0 - assets0;
                // to cover it, a liquidator may have to use their own assets, taking on inventory risk.
                // to compensate them for this risk, they're allowed to seize some of the surplus asset.
                reward1 += Math.mulDiv(shortfall, 0.05e9 * meanPriceX96, 1e9 * FixedPoint96.Q96);
            }

            if (liabilities1 > assets1) {
                // shortfall is the amount that cannot be directly repaid using Borrower assets at this price
                uint256 shortfall = liabilities1 - assets1;
                // to cover it, a liquidator may have to use their own assets, taking on inventory risk.
                // to compensate them for this risk, they're allowed to seize some of the surplus asset.
                reward1 += Math.mulDiv(shortfall, 0.05e9, 1e9);
            }
        }
    }
}
