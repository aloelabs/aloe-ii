// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {ERC20, SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import {Borrower, IManager} from "aloe-ii-core/Borrower.sol";

contract WithdrawManager is IManager {
    using SafeTransferLib for ERC20;

    function callback(bytes calldata data, address) external override returns (uint144) {
        (uint256 amount0, uint256 amount1, address recipient) = abi.decode(data, (uint256, uint256, address));

        if (amount0 > 0) {
            Borrower(payable(msg.sender)).TOKEN0().safeTransferFrom(msg.sender, recipient, amount0);
        }

        if (amount1 > 0) {
            Borrower(payable(msg.sender)).TOKEN1().safeTransferFrom(msg.sender, recipient, amount1);
        }

        // Return 0 to indicate we don't want to change Uniswap positions
        return 0;
    }
}
