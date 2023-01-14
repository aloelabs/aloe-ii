// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.15;

import {Math} from "openzeppelin-contracts/utils/math/Math.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {MIN_SIGMA, MAX_SIGMA, MAX_LEVERAGE, LIQUIDATION_INCENTIVE} from "./constants/Constants.sol";
import {Q96} from "./constants/Q.sol";

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
    function isHealthy(
        uint256 liabilities0,
        uint256 liabilities1,
        Assets memory mem,
        Prices memory prices
    ) internal pure returns (bool) {
        // liquidation incentive. counted as liability because account will owe it to someone.
        // compensates liquidators for inventory risk.
        uint256 liquidationIncentive = computeLiquidationIncentive(
            mem.fixed0 + mem.fluid0C,
            mem.fixed1 + mem.fluid1C,
            liabilities0,
            liabilities1,
            prices.c
        );

        unchecked {
            liabilities0 += liabilities0 / MAX_LEVERAGE;
            liabilities1 += liabilities1 / MAX_LEVERAGE + liquidationIncentive;
        }

        // combine
        uint224 priceX96;
        uint256 liabilities;
        uint256 assets;

        priceX96 = uint224(Math.mulDiv(prices.a, prices.a, Q96));
        liabilities = liabilities1 + Math.mulDiv(liabilities0, priceX96, Q96);
        assets = mem.fluid1A + mem.fixed1 + Math.mulDiv(mem.fixed0, priceX96, Q96);
        if (liabilities > assets) return false;

        priceX96 = uint224(Math.mulDiv(prices.b, prices.b, Q96));
        liabilities = liabilities1 + Math.mulDiv(liabilities0, priceX96, Q96);
        assets = mem.fluid1B + mem.fixed1 + Math.mulDiv(mem.fixed0, priceX96, Q96);
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

    function computeLiquidationIncentive(
        uint256 assets0,
        uint256 assets1,
        uint256 liabilities0,
        uint256 liabilities1,
        uint160 sqrtMeanPriceX96
    ) internal pure returns (uint256 reward1) {
        unchecked {
            uint256 meanPriceX96 = Math.mulDiv(sqrtMeanPriceX96, sqrtMeanPriceX96, Q96);

            if (liabilities0 > assets0) {
                // shortfall is the amount that cannot be directly repaid using Borrower assets at this price
                uint256 shortfall = liabilities0 - assets0;
                // to cover it, a liquidator may have to use their own assets, taking on inventory risk.
                // to compensate them for this risk, they're allowed to seize some of the surplus asset.
                reward1 += Math.mulDiv(shortfall, meanPriceX96, Q96) / LIQUIDATION_INCENTIVE;
            }

            if (liabilities1 > assets1) {
                // shortfall is the amount that cannot be directly repaid using Borrower assets at this price
                uint256 shortfall = liabilities1 - assets1;
                // to cover it, a liquidator may have to use their own assets, taking on inventory risk.
                // to compensate them for this risk, they're allowed to seize some of the surplus asset.
                reward1 += shortfall / LIQUIDATION_INCENTIVE;
            }
        }
    }
}
