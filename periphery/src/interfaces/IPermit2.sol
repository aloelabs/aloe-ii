// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {ERC20} from "solmate/tokens/ERC20.sol";

/// @notice Minimal Permit2 interface, derived from
// https://github.com/Uniswap/permit2/blob/main/src/interfaces/ISignatureTransfer.sol
interface IPermit2 {
    // Token and amount in a permit message
    struct TokenPermissions {
        ERC20 token;
        uint256 amount;
    }

    // The permit2 message
    struct PermitTransferFrom {
        TokenPermissions permitted;
        uint256 nonce;
        uint256 deadline;
    }

    // Transfer details for permitTransferFrom()
    struct SignatureTransferDetails {
        address to;
        uint256 requestedAmount;
    }

    // Consume a permit2 message and transfer tokens
    function permitTransferFrom(
        PermitTransferFrom calldata permit,
        SignatureTransferDetails calldata transferDetails,
        address owner,
        bytes calldata signature
    ) external;
}
