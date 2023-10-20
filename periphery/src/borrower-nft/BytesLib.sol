// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

// TODO: organize/order these functions better
library BytesLib {
    error RemovalFailed();

    error IndexOutOfBounds();

    function pack(uint256[] memory items, uint256 chunkSize) internal pure returns (bytes memory newList) {
        uint256 shift;
        unchecked {
            shift = 256 - (chunkSize << 3);
        }

        assembly ("memory-safe") {
            // Start `newList` at the free memory pointer
            newList := mload(0x40)

            let newPtr := add(newList, 32)
            let arrPtr := add(items, 32)
            let arrMemEnd := add(arrPtr, shl(5, mload(items)))

            // prettier-ignore
            for { } lt(arrPtr, arrMemEnd) { arrPtr := add(arrPtr, 32) } {
                // Load 32 byte chunk from `items`, left shifting by N bits so that items get packed together
                let x := shl(shift, mload(arrPtr))

                // Copy to `newList`
                mstore(newPtr, x)
                newPtr := add(newPtr, chunkSize)
            }

            // Set `newList` length
            mstore(newList, sub(sub(newPtr, newList), 32))
            // Update free memory pointer
            mstore(0x40, newPtr)
        }
    }

    /// @dev Appends `item` onto `oldList`, a packed array where each element spans `chunkSize` bytes
    function append(
        bytes memory oldList,
        uint256 item,
        uint256 chunkSize
    ) internal view returns (bytes memory newList) {
        unchecked {
            item <<= 256 - (chunkSize << 3);
        }

        assembly ("memory-safe") {
            // Start `newList` at the free memory pointer
            newList := mload(0x40)

            let newPtr := add(newList, 32)
            let length := mload(oldList)

            // Use identity precompile to copy `oldList` memory to `newList`
            if iszero(staticcall(gas(), 0x04, add(oldList, 32), length, newPtr, length)) {
                revert(0, 0)
            }

            // Write new `item` at the end
            newPtr := add(newPtr, length)
            mstore(newPtr, item)

            // Set `newList` length
            mstore(newList, add(length, chunkSize))
            // Update free memory pointer
            mstore(0x40, add(newPtr, chunkSize))
        }
    }

    /// @dev Appends all `items` onto `oldList`, a packed array where each element spans `chunkSize` bytes
    function append(
        bytes memory oldList,
        uint256[] memory items,
        uint256 chunkSize
    ) internal view returns (bytes memory newList) {
        uint256 shift;
        unchecked {
            shift = 256 - (chunkSize << 3);
        }

        assembly ("memory-safe") {
            // Start `newList` at the free memory pointer
            newList := mload(0x40)

            let newPtr := add(newList, 32)
            let length := mload(oldList)

            // Use identity precompile to copy `oldList` memory to `newList`
            if iszero(staticcall(gas(), 0x04, add(oldList, 32), length, newPtr, length)) {
                revert(0, 0)
            }

            // Write new `items` at the end
            newPtr := add(newPtr, length)
            let arrPtr := add(items, 32)
            let arrMemEnd := add(arrPtr, shl(5, mload(items)))

            // prettier-ignore
            for { } lt(arrPtr, arrMemEnd) { arrPtr := add(arrPtr, 32) } {
                // Load 32 byte chunk from `items`, left shifting by N bits so that items get packed together
                let x := shl(shift, mload(arrPtr))

                // Copy to `newList`
                mstore(newPtr, x)
                newPtr := add(newPtr, chunkSize)
            }

            // Set `newList` length
            mstore(newList, sub(sub(newPtr, newList), 32))
            // Update free memory pointer
            mstore(0x40, newPtr)
        }
    }

    /// @dev Removes all occurrences of `item` from `oldList`, a packed array where each element spans
    /// `chunkSize` bytes
    function filter(
        bytes memory oldList,
        uint256 item,
        uint256 chunkSize
    ) internal pure returns (bytes memory newList) {
        uint256 mask = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
        unchecked {
            uint256 shift = 256 - (chunkSize << 3);
            mask <<= shift;
            item <<= shift;
        }

        assembly ("memory-safe") {
            // Start `newList` at the free memory pointer
            newList := mload(0x40)

            let newPtr := add(newList, 32)
            let oldPtr := add(oldList, 32)
            let oldMemEnd := add(oldPtr, mload(oldList))

            // prettier-ignore
            for { } lt(oldPtr, oldMemEnd) { oldPtr := add(oldPtr, chunkSize) } {
                // Load 32 byte chunk from `oldList`, masking out the last N bits since items are packed together
                let x := and(mload(oldPtr), mask)
                // Skip it if it matches the `item` being deleted
                if eq(x, item) {
                    continue
                }

                // Copy to `newList`
                mstore(newPtr, x)
                newPtr := add(newPtr, chunkSize)
            }

            // Set `newList` length
            mstore(newList, sub(sub(newPtr, newList), 32))
            // Update free memory pointer
            mstore(0x40, newPtr)
        }
    }

    /// @dev Removes all occurrences of `item` from `oldList`, a packed array where each element spans
    /// `chunkSize` bytes. Reverts if nothing was removed.
    function remove(
        bytes memory oldList,
        uint256 item,
        uint256 chunkSize
    ) internal pure returns (bytes memory newList) {
        newList = filter(oldList, item, chunkSize);
        if (newList.length == oldList.length) revert RemovalFailed();
    }

    /// @dev Checks whether `item` is present in `list`, a packed array where each element spans `chunkSize` bytes
    function includes(bytes memory list, uint256 item, uint256 chunkSize) internal pure returns (bool result) {
        uint256 shift;
        unchecked {
            shift = 256 - (chunkSize << 3);
        }

        assembly ("memory-safe") {
            let ptr := add(list, 32)
            let memEnd := add(ptr, mload(list))

            // prettier-ignore
            for { } lt(ptr, memEnd) { ptr := add(ptr, chunkSize) } {
                // Load 32 bytes from `list`. Since chunks may overlap, `shr` to isolate the current one
                let x := shr(shift, mload(ptr))
                // If it matches `item`, return true
                if eq(x, item) {
                    result := 1
                    break
                }
            }
        }
    }

    // TODO: test this
    function find(
        bytes memory list,
        uint256 item,
        uint256 mask,
        uint256 chunkSize
    ) internal pure returns (uint256 result) {
        uint256 shift;
        unchecked {
            shift = 256 - (chunkSize << 3);
        }

        assembly ("memory-safe") {
            let ptr := add(list, 32)
            let memEnd := add(ptr, mload(list))

            // prettier-ignore
            for { } lt(ptr, memEnd) { ptr := add(ptr, chunkSize) } {
                // Load 32 bytes from `list`. Since chunks may overlap, `shr` to isolate the current one
                result := shr(shift, mload(ptr))
                // If masked `result` matches `item`, return it
                if eq(and(result, mask), item) {
                    break
                }
            }

            // TODO: probably error with `NotFound()` if it isn't found
        }
    }

    // TODO: test this
    function at(bytes memory list, uint256 index, uint256 chunkSize) internal pure returns (uint256 result) {
        uint256 shift;
        unchecked {
            shift = 256 - (chunkSize << 3);
        }

        assembly ("memory-safe") {
            let start := mul(index, chunkSize)

            {
                let length := mload(list)
                if or(mod(length, chunkSize), iszero(lt(start, length))) {
                    // Store the function selector of `IndexOutOfBounds()`.
                    mstore(0x00, 0x4e23d035)
                    // Revert with (offset, size).
                    revert(0x1c, 0x04)
                }
            }

            let ptr := add(add(list, 32), start)
            // Load 32 bytes from `list`. Since chunks may overlap, `shr` to isolate the desired one
            result := shr(shift, mload(ptr))
        }
    }
}
