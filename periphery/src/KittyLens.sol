// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

import {ERC20} from "solmate/tokens/ERC20.sol";

import {FullMath} from "aloe-ii-core/libraries/FullMath.sol";

import {Kitty} from "aloe-ii-core/Kitty.sol";

contract KittyLens {
    function readBasics(Kitty kitty)
        external
        view
        returns (
            ERC20 asset,
            uint256 interestRate,
            uint256 utilization,
            uint256 inventory,
            uint256 totalBorrows
        )
    {
        asset = kitty.asset();
        totalBorrows = kitty.totalBorrows();
        inventory = asset.balanceOf(address(kitty)) + totalBorrows;
        utilization = FullMath.mulDiv(1e18, totalBorrows, inventory);
        interestRate = utilization > 0.5e18 ? 1.24e9 : 6.27e8;
    }
}
