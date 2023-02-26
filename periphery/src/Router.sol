// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {ERC20, SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import {Lender} from "aloe-ii-core/Lender.sol";

contract Router {
    using SafeTransferLib for ERC20;

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
        lender.creditCourier(courierId, msg.sender);

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
        lender.creditCourier(courierId, msg.sender);

        lender.asset().safeTransferFrom(msg.sender, address(lender), amount);
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
