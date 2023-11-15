// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {ERC20, SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import {Lender} from "aloe-ii-core/Lender.sol";

import {IPermit2} from "./interfaces/IPermit2.sol";

contract Router {
    using SafeTransferLib for ERC20;

    IPermit2 public immutable PERMIT2;

    constructor(IPermit2 permit2) {
        PERMIT2 = permit2;
    }

    /**
     * @notice Deposits `amount` of `lender.asset()` to `lender` using {`nonce`, `deadline`, `signature`} for Permit2,
     * and gives `courierId` a cut of future interest earned by `msg.sender`. `v`, `r`, and `s` are used with
     * `lender.permit` in order to (a) achieve 0 balance if necessary and (b) set the courier.
     * @dev This innoculates `Lender` against a potential courier frontrunning attack by redeeming all shares (if any
     * are present) before assigning the new `courierId`. `Lender` then clears the `permit`ed allowance in `deposit`,
     * meaning this contract is left with no special permissions.
     */
    function depositWithPermit2(
        Lender lender,
        uint256 amount,
        uint256 nonce,
        uint256 deadline,
        bytes calldata signature,
        uint32 courierId,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 shares) {
        lender.permit(msg.sender, address(this), type(uint256).max, deadline, v, r, s);

        if (lender.balanceOf(msg.sender) > 0) {
            lender.redeem(type(uint256).max, msg.sender, msg.sender);
        }

        // Transfer tokens from the caller to the lender.
        PERMIT2.permitTransferFrom(
            // The permit message.
            IPermit2.PermitTransferFrom({
                permitted: IPermit2.TokenPermissions({token: lender.asset(), amount: amount}),
                nonce: nonce,
                deadline: deadline
            }),
            // The transfer recipient and amount.
            IPermit2.SignatureTransferDetails({to: address(lender), requestedAmount: amount}),
            // The owner of the tokens, which must also be
            // the signer of the message, otherwise this call
            // will fail.
            msg.sender,
            // The packed signature that was the result of signing
            // the EIP712 hash of `permit`.
            signature
        );

        shares = lender.deposit(amount, msg.sender, courierId);
    }

    function depositWithPermit2(
        Lender lender,
        uint256 amount,
        uint256 nonce,
        uint256 deadline,
        bytes calldata signature
    ) external returns (uint256 shares) {
        // Transfer tokens from the caller to the lender.
        PERMIT2.permitTransferFrom(
            // The permit message.
            IPermit2.PermitTransferFrom({
                permitted: IPermit2.TokenPermissions({token: lender.asset(), amount: amount}),
                nonce: nonce,
                deadline: deadline
            }),
            // The transfer recipient and amount.
            IPermit2.SignatureTransferDetails({to: address(lender), requestedAmount: amount}),
            // The owner of the tokens, which must also be
            // the signer of the message, otherwise this call
            // will fail.
            msg.sender,
            // The packed signature that was the result of signing
            // the EIP712 hash of `permit`.
            signature
        );

        shares = lender.deposit(amount, msg.sender);
    }

    function repayWithPermit2(
        Lender lender,
        bool max,
        uint256 amount,
        address beneficiary,
        uint256 nonce,
        uint256 deadline,
        bytes calldata signature
    ) external returns (uint256 units) {
        IPermit2.PermitTransferFrom memory permitMsg = IPermit2.PermitTransferFrom({
            permitted: IPermit2.TokenPermissions({token: lender.asset(), amount: amount}),
            nonce: nonce,
            deadline: deadline
        });

        if (max) amount = lender.borrowBalance(beneficiary);

        // Transfer tokens from the caller to the lender.
        PERMIT2.permitTransferFrom(
            // The permit message.
            permitMsg,
            // The transfer recipient and amount.
            IPermit2.SignatureTransferDetails({to: address(lender), requestedAmount: amount}),
            // The owner of the tokens, which must also be
            // the signer of the message, otherwise this call
            // will fail.
            msg.sender,
            // The packed signature that was the result of signing
            // the EIP712 hash of `permit`.
            signature
        );

        units = lender.repay(amount, beneficiary);
    }
}
