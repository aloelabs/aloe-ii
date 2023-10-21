// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {SSTORE2} from "solady/utils/SSTORE2.sol";

library SafeSSTORE2 {
    function write(bytes memory data) internal returns (address pointer) {
        pointer = (data.length == 0) ? address(0) : SSTORE2.write(data);
    }

    function read(address pointer) internal view returns (bytes memory data) {
        data = (pointer == address(0)) ? bytes("") : SSTORE2.read(pointer);
    }
}
