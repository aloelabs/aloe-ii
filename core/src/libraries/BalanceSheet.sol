// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {Math} from "openzeppelin-contracts/utils/math/Math.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {MIN_SIGMA, MAX_SIGMA, MAX_LEVERAGE, LIQUIDATION_INCENTIVE} from "./constants/Constants.sol";
import {Q96} from "./constants/Q.sol";
import {SafeCastLib} from "./SafeCastLib.sol";

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

/// @title BalanceSheet
/// @notice Provides functions for computing a `Borrower`'s health
/// @author Aloe Labs, Inc.
library BalanceSheet {
    function isHealthy(
        Prices memory prices,
        Assets memory mem,
        uint256 liabilities0,
        uint256 liabilities1
    ) internal pure returns (bool) {
        (uint256 incentive1, ) = computeLiquidationIncentive(
            mem.fixed0 + mem.fluid0C, // total assets0 at `prices.c` (the TWAP)
            mem.fixed1 + mem.fluid1C, // total assets1 at `prices.c` (the TWAP)
            liabilities0,
            liabilities1,
            prices.c
        );
        return isHealthy(prices, mem, liabilities0, liabilities1, incentive1);
    }

    function isHealthy(
        Prices memory prices,
        Assets memory mem,
        uint256 liabilities0,
        uint256 liabilities1,
        uint256 incentive1
    ) internal pure returns (bool) {
        // The liquidation incentive is added to `liabilities1` because it's a potential liability, and we
        // don't want to re-evaluate it at the probe prices (as would happen if we added it to `liabilities0`).
        unchecked {
            liabilities0 += liabilities0 / MAX_LEVERAGE;
            liabilities1 += liabilities1 / MAX_LEVERAGE + incentive1;
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
            if (sigma < MIN_SIGMA) sigma = MIN_SIGMA;
            else if (sigma > MAX_SIGMA) sigma = MAX_SIGMA;

            sigma *= n;

            a = uint160((sqrtMeanPriceX96 * FixedPointMathLib.sqrt(1e18 - sigma)) / 1e9);
            b = SafeCastLib.safeCastTo160((sqrtMeanPriceX96 * FixedPointMathLib.sqrt(1e18 + sigma)) / 1e9);
        }
    }

    function computeLiquidationIncentive(
        uint256 assets0,
        uint256 assets1,
        uint256 liabilities0,
        uint256 liabilities1,
        uint160 sqrtMeanPriceX96
    ) internal pure returns (uint256 incentive1, uint224 meanPriceX96) {
        unchecked {
            meanPriceX96 = uint224(Math.mulDiv(sqrtMeanPriceX96, sqrtMeanPriceX96, Q96));

            if (liabilities0 > assets0) {
                // shortfall is the amount that cannot be directly repaid using Borrower assets at this price
                uint256 shortfall = liabilities0 - assets0;
                // to cover it, a liquidator may have to use their own assets, taking on inventory risk.
                // to compensate them for this risk, they're allowed to seize some of the surplus asset.
                incentive1 += Math.mulDiv(shortfall / LIQUIDATION_INCENTIVE, meanPriceX96, Q96);
            }

            if (liabilities1 > assets1) {
                // shortfall is the amount that cannot be directly repaid using Borrower assets at this price
                uint256 shortfall = liabilities1 - assets1;
                // to cover it, a liquidator may have to use their own assets, taking on inventory risk.
                // to compensate them for this risk, they're allowed to seize some of the surplus asset.
                incentive1 += shortfall / LIQUIDATION_INCENTIVE;
            }
        }
    }
}
