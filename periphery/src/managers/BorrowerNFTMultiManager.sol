// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

import {IManager} from "aloe-ii-core/Borrower.sol";

contract BorrowerNFTMultiManager is IManager {
    function callback(bytes calldata data, address, uint208) external override returns (uint208) {
        unchecked {
            bytes[] memory calls = abi.decode(data[20:], (bytes[]));

            uint256 count = calls.length;
            for (uint256 i; i < count; i++) {
                (bool success, ) = msg.sender.call(calls[i]); // solhint-disable-line avoid-low-level-calls
                require(success);
            }

            return 0;
        }
    }
}
