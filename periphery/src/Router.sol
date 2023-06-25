// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {ERC20, SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import {Lender} from "aloe-ii-core/Lender.sol";

contract Router {
    using SafeTransferLib for ERC20;

    IPermit2 public immutable PERMIT2;

    constructor(IPermit2 permit2) {
        PERMIT2 = permit2;
    }

    function depositWithApprove(Lender lender, uint256 amount) external returns (uint256 shares) {
        lender.asset().safeTransferFrom(msg.sender, address(lender), amount);
        shares = lender.deposit(amount, msg.sender);
    }

    function depositWithApprove(
        Lender lender,
        uint256 amount,
        uint32 courierId,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 shares) {
        lender.permit(msg.sender, address(this), 1, deadline, v, r, s);

        lender.asset().safeTransferFrom(msg.sender, address(lender), amount);
        shares = lender.deposit(amount, msg.sender, courierId);
    }

    function depositWithPermit(
        Lender lender,
        uint256 amount,
        uint256 allowance,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 shares) {
        if (allowance != 0) {
            lender.asset().permit(msg.sender, address(this), allowance, deadline, v, r, s);
        }

        lender.asset().safeTransferFrom(msg.sender, address(lender), amount);
        shares = lender.deposit(amount, msg.sender);
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
        if (allowance != 0) {
            lender.asset().permit(msg.sender, address(this), allowance, deadline, v, r, s);
        }

        lender.permit(msg.sender, address(this), 1, deadline, vL, rL, sL);

        lender.asset().safeTransferFrom(msg.sender, address(lender), amount);
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

    function repayWithApprove(Lender lender, uint256 amount, address beneficiary) external returns (uint256 units) {
        lender.asset().safeTransferFrom(msg.sender, address(lender), amount);
        units = lender.repay(amount, beneficiary);
    }

    function repayWithPermit(
        Lender lender,
        uint256 amount,
        address beneficiary,
        uint256 allowance,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 units) {
        ERC20 asset = lender.asset();

        if (allowance != 0) {
            asset.permit(msg.sender, address(this), allowance, deadline, v, r, s);
        }

        asset.safeTransferFrom(msg.sender, address(lender), amount);
        units = lender.repay(amount, beneficiary);
    }
}

// Minimal Permit2 interface, derived from
// https://github.com/Uniswap/permit2/blob/main/src/interfaces/ISignatureTransfer.sol
interface IPermit2 {
    // Token and amount in a permit message.
    struct TokenPermissions {
        // Token to transfer.
        ERC20 token;
        // Amount to transfer.
        uint256 amount;
    }

    // The permit2 message.
    struct PermitTransferFrom {
        // Permitted token and amount.
        TokenPermissions permitted;
        // Unique identifier for this permit.
        uint256 nonce;
        // Expiration for this permit.
        uint256 deadline;
    }

    // Transfer details for permitTransferFrom().
    struct SignatureTransferDetails {
        // Recipient of tokens.
        address to;
        // Amount to transfer.
        uint256 requestedAmount;
    }

    // Consume a permit2 message and transfer tokens.
    function permitTransferFrom(
        PermitTransferFrom calldata permit,
        SignatureTransferDetails calldata transferDetails,
        address owner,
        bytes calldata signature
    ) external;
}
