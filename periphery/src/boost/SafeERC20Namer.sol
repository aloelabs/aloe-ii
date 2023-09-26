// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IERC20Metadata {
    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function decimals() external view returns (uint8);
}

/// @notice Produces token descriptors from inconsistent or absent ERC20 symbol implementations that can
/// return string or bytes32 this library will always produce a string symbol to represent the token
/// @author [Yield Protocol](https://github.com/yieldprotocol/yield-utils-v2/blob/main/src/token/SafeERC20Namer.sol)
library SafeERC20Namer {
    // attempts to extract the token symbol. if it does not implement symbol, returns a symbol derived from the address
    function tokenSymbol(address token) internal view returns (string memory) {
        string memory symbol = _callAndParseStringReturn(token, IERC20Metadata.symbol.selector);
        if (bytes(symbol).length == 0) {
            // fallback to 6 uppercase hex of address
            return "---";
        }
        return symbol;
    }

    // attempts to extract the token name. if it does not implement name, returns a name derived from the address
    function tokenName(address token) internal view returns (string memory) {
        string memory name = _callAndParseStringReturn(token, IERC20Metadata.name.selector);
        if (bytes(name).length == 0) {
            // fallback to full hex of address
            return "Unknown";
        }
        return name;
    }

    /// @notice Provides a safe ERC20.decimals version which returns '0' as fallback value.
    /// @param token The address of the ERC-20 token contract.
    /// @return (uint8) Token decimals.
    function tokenDecimals(address token) internal view returns (uint8) {
        (bool success, bytes memory data) = token.staticcall(abi.encodeWithSelector(IERC20Metadata.decimals.selector));
        return success && data.length == 32 ? abi.decode(data, (uint8)) : 0;
    }

    // calls an external view token contract method that returns a symbol or name, and parses the output into a string
    function _callAndParseStringReturn(address token, bytes4 selector) private view returns (string memory) {
        (bool success, bytes memory data) = token.staticcall(abi.encodeWithSelector(selector));
        // if not implemented, or returns empty data, return empty string
        if (!success || data.length == 0) {
            return "";
        }
        // bytes32 data always has length 32
        if (data.length == 32) {
            bytes32 decoded = abi.decode(data, (bytes32));
            return _bytes32ToString(decoded);
        } else if (data.length > 64) {
            return abi.decode(data, (string));
        }
        return "";
    }

    function _bytes32ToString(bytes32 x) private pure returns (string memory) {
        bytes memory bytesString = new bytes(32);
        uint256 charCount = 0;
        for (uint256 j = 0; j < 32; j++) {
            bytes1 char = x[j];
            if (char != 0) {
                bytesString[charCount] = char;
                charCount++;
            }
        }
        bytes memory bytesStringTrimmed = new bytes(charCount);
        for (uint256 j = 0; j < charCount; j++) {
            bytesStringTrimmed[j] = bytesString[j];
        }
        return string(bytesStringTrimmed);
    }

    // assumes the data is in position 2
    function _parseStringData(bytes memory b) private pure returns (string memory) {
        uint256 charCount = 0;
        // first parse the charCount out of the data
        for (uint256 i = 32; i < 64; i++) {
            charCount <<= 8;
            charCount += uint8(b[i]);
        }

        bytes memory bytesStringTrimmed = new bytes(charCount);
        for (uint256 i = 0; i < charCount; i++) {
            bytesStringTrimmed[i] = b[i + 64];
        }

        return string(bytesStringTrimmed);
    }
}
