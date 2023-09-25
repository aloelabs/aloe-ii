// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

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
            uint256 totalSupply,
            uint8 reserveFactor
        )
    {
        asset = lender.asset();
        (, inventory, totalBorrows, totalSupply) = lender.stats();

        if (inventory > 0) utilization = (1e18 * totalBorrows) / inventory;
        interestRate = lender.rateModel().getYieldPerSecond(utilization, address(lender));
        reserveFactor = lender.reserveFactor();
    }

    /**
     * @notice Indicates whether `lender.maxRedeem(owner)` is dynamic, i.e. whether it's changing over time or not
     * @dev In most cases, `lender.maxRedeem(owner)` returns a static number of shares, and a standard `lender.redeem`
     * call can successfully redeem everything. However, if the user has a courier or if utilization is too high, the
     * number of shares may change block by block. In that case, to redeem the maximum value, you can pass
     * `type(uint256).max` to `lender.redeem`.
     */
    function isMaxRedeemDynamic(Lender lender, address owner) external view returns (bool) {
        // NOTE: If the first statement is true, the second statement will also be true (unless this is the block in which
        // they deposited for the first time). We include the first statement only to reduce computation.
        return lender.courierOf(owner) > 0 || lender.balanceOf(owner) != lender.maxRedeem(owner);
    }
}
