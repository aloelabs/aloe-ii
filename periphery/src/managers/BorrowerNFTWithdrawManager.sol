// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

import {Borrower, IManager} from "aloe-ii-core/Borrower.sol";

contract BorrowerNFTWithdrawManager is IManager {
    function callback(bytes calldata data, address, uint208) external override returns (uint208) {
        Borrower borrower = Borrower(payable(msg.sender));
        borrower.transfer(
            borrower.TOKEN0().balanceOf(msg.sender),
            borrower.TOKEN1().balanceOf(msg.sender),
            address(bytes20(data[:20]))
        );

        borrower.transferEth(msg.sender.balance, payable(address(bytes20(data[:20]))));

        return 0;
    }
}
