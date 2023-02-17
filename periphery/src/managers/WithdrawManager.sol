// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {ERC20, SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import {Borrower, IManager} from "aloe-ii-core/Borrower.sol";

contract WithdrawManager is IManager {
    using SafeTransferLib for ERC20;

    function callback(bytes calldata raw) external override returns (uint144) {
        (uint256 amount0, uint256 amount1, address recipient, bytes memory data) = abi.decode(
            raw,
            (uint256, uint256, address, bytes)
        );

        if (data.length > 0) {
            (bool success, ) = msg.sender.call(data);
            require(success);
        }

        if (amount0 > 0) {
            Borrower(msg.sender).TOKEN0().safeTransferFrom(msg.sender, recipient, amount0);
        }

        if (amount1 > 0) {
            Borrower(msg.sender).TOKEN1().safeTransferFrom(msg.sender, recipient, amount1);
        }

        return 0;
    }
}
