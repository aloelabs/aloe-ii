// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {ERC20, SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import {Lender} from "aloe-ii-core/Lender.sol";

/// @dev Increases `Lender` ERC4626 compatibility. The following issues remain:
///      - ERC4626 events will be emitted by the `Lender`, not by this helper
///      - `withdraw` and `redeem` won't work unless the caller approves this helper to transfer
///        their vault tokens (shares), and for security reasons, `owner` cannot be set to anyone
///        other than the caller. You can avoid these issues by calling `redeem` on the `Lender`
///        directly.
///      - `mint` and `withdraw` consume more gas than `deposit` and `redeem`
///
///      We recommend using the `deposit` and `redeem` flow (as opposed to `mint`/`withdraw`),
///      because it's the most gas efficient and allows you to use the plain `Lender` for almost
///      everything. You'd only need to call this helper for `deposit`
contract ERC4626Helper {
    using SafeTransferLib for ERC20;

    Lender public immutable LENDER;

    ERC20 public immutable ASSET;

    constructor(Lender lender) {
        LENDER = lender;
        ASSET = lender.asset();
    }

    /// @dev Caller needs to have approved this contract to spend their assets
    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        ASSET.safeTransferFrom(msg.sender, address(LENDER), assets);
        shares = LENDER.deposit(assets, receiver);
    }

    /// @dev Caller needs to have approved this contract to spend their assets
    function mint(uint256 shares, address receiver) external returns (uint256 assets) {
        assets = LENDER.previewMint(shares);

        ASSET.safeTransferFrom(msg.sender, address(LENDER), assets);
        require(LENDER.deposit(assets, receiver) >= shares);
    }

    /// @dev Caller needs to have approved this contract to spend their shares
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares) {
        shares = LENDER.previewWithdraw(assets);

        require(owner == msg.sender);
        require(LENDER.redeem(shares, receiver, msg.sender) >= assets);
    }

    /// @dev Caller needs to have approved this contract to spend their shares
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets) {
        require(owner == msg.sender);
        assets = LENDER.redeem(shares, receiver, msg.sender);
    }

    /**
     * @dev Forwards the current call to `LENDER`.
     *
     * This function does not return to its internal call site, it will return directly to the external caller.
     */
    fallback() external {
        address implementation = address(LENDER);
        assembly {
            // Copy msg.data. We take full control of memory in this inline assembly
            // block because it will not return to Solidity code. We overwrite the
            // Solidity scratch pad at memory position 0.
            calldatacopy(0, 0, calldatasize())

            // Call the implementation.
            // out and outsize are 0 because we don't know the size yet.
            let result := call(gas(), implementation, 0, 0, calldatasize(), 0, 0)

            // Copy the returned data.
            returndatacopy(0, 0, returndatasize())

            switch result
            // delegatecall returns 0 on error.
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }
}
