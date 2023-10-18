// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {SSTORE2} from "solady/utils/SSTORE2.sol";

library SafeSSTORE2 {
    /// @custom:future-work The following could be replaced with a single line,
    ///   `pointer = (data.length == 0) ? address(0) : SSTORE2.write(data);`
    /// which is ~2% more gas efficient in most cases. However, when doing it that way, the `create` op occassionally
    /// throws errors when it shouldn't (in Foundry invariant tests, as of October 2023). In an abundance of caution,
    /// we've gone with the code below. It does have one positive side-effect:
    /// If a piece of data has already been written somewhere, that storage contract can be reused.
    function write(bytes memory data) internal returns (address pointer) {
        pointer = SSTORE2.predictDeterministicAddress(data, 0, address(this));
        if (pointer.code.length == 0) {
            SSTORE2.writeDeterministic(data, 0);
        }
    }

    function read(address pointer) internal view returns (bytes memory data) {
        data = (pointer == address(0)) ? bytes("") : SSTORE2.read(pointer);
    }
}
