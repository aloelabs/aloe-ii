// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {IManager} from "aloe-ii-core/Borrower.sol";

contract SimpleManager is IManager {
    function callback(bytes calldata data, address, uint208) external override returns (uint208) {
        (bool success, ) = msg.sender.call(data); // solhint-disable-line avoid-low-level-calls
        require(success);
        return 0;
    }
}
