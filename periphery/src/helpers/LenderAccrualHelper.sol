// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {Lender} from "aloe-ii-core/Lender.sol";

contract LenderAccrualHelper {
    function accrueInterest(Lender[] calldata lenders) external {
        unchecked {
            uint256 count = lenders.length;
            for (uint256 i = 0; i < count; i++) {
                lenders[i].accrueInterest();
            }
        }
    }
}
