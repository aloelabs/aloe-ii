// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

import {ERC20, SafeTransferLib} from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("Aloe Mock USDC", "USDC", 6) {}

    function request() external {
        _mint(msg.sender, 1000e6);
    }
}
