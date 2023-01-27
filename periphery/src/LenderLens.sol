// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {Math} from "openzeppelin-contracts/utils/math/Math.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

import {Lender} from "aloe-ii-core/Lender.sol";

contract LenderLens {
    function readBasics(
        Lender lender
    )
        external
        view
        returns (
            ERC20 asset,
            uint256 interestRate,
            uint256 utilization,
            uint256 inventory,
            uint256 totalBorrows,
            uint256 totalSupply
        )
    {
        asset = lender.asset();
        (totalSupply, inventory, totalBorrows) = lender.stats();

        if (inventory != 0) {
            utilization = Math.mulDiv(1e18, totalBorrows, inventory);
            interestRate = lender.rateModel().computeYieldPerSecond(utilization);
        }
    }
}
