// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {IManager} from "aloe-ii-core/Borrower.sol";

contract MultiManager is IManager {
    function callback(bytes calldata data, address, uint144 positions) external override returns (uint144) {
        unchecked {
            bytes[] memory calls = abi.decode(data, (bytes[]));

            uint256 count = calls.length;
            for (uint256 i = 0; i < count; i++) {
                (bool success, ) = msg.sender.call(calls[i]); // solhint-disable-line avoid-low-level-calls
                require(success);
            }

            return positions;
        }
    }
}
