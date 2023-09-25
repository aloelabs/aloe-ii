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

    function depositWithPermit(
        Lender lender,
        uint256 amount,
        uint256 allowance,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s,
        uint32 courierId,
        uint8 vL,
        bytes32 rL,
        bytes32 sL
    ) external returns (uint256 shares) {
        lender.permit(msg.sender, address(this), 1, deadline, vL, rL, sL);

        ERC20 asset = lender.asset();
        asset.permit(msg.sender, address(this), allowance, deadline, v, r, s);
        asset.safeTransferFrom(msg.sender, address(lender), amount);

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
