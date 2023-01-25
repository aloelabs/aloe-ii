// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

import "forge-std/Vm.sol";

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import "src/Lender.sol";

import {Router} from "../Utils.sol";

uint256 constant BORROWS_SCALER = uint256(type(uint72).max) * 1e12;

contract LenderHarness {
    Vm constant vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    Lender immutable LENDER;

    Router immutable ROUTER;

    address[] public holders;

    mapping(address => bool) alreadyHolder;

    address[] public borrowers;

    uint32[] public courierIds;

    mapping(uint32 => bool) alreadyEnrolledCourier;

    constructor(Lender lender, Router router) {
        LENDER = lender;
        ROUTER = router;

        holders.push(lender.RESERVE());
        alreadyHolder[lender.RESERVE()] = true;
    }

    function getHolderCount() external view returns (uint256) {
        return holders.length;
    }

    function getBorrowerCount() external view returns (uint256) {
        return borrowers.length;
    }

    function enrollCourier(uint32 id, address wallet, uint16 cut) external {
        if (id == 0 || cut == 0 || cut >= 10_000) {
            vm.prank(msg.sender);
            vm.expectRevert();
            LENDER.enrollCourier(id, wallet, cut);
        }
        if (id == 0) id = 1;
        cut = (cut % 9_999) + 1;

        (, uint16 currentCut) = LENDER.couriers(id);
        if (currentCut != 0) {
            vm.prank(msg.sender);
            vm.expectRevert();
            LENDER.enrollCourier(id, wallet, cut);

            assert(alreadyEnrolledCourier[id]);
            return;
        }

        vm.prank(msg.sender);
        LENDER.enrollCourier(id, wallet, cut);

        assert(!alreadyEnrolledCourier[id]);
        courierIds.push(id);
        alreadyEnrolledCourier[id] = true;

        if (!alreadyHolder[wallet]) {
            holders.push(wallet);
            alreadyHolder[wallet] = true;
        }
    }

    function creditCourier(uint32 id, address account) public {
        if (msg.sender != account) {
            vm.prank(msg.sender);
            vm.expectRevert();
            LENDER.creditCourier(id, account);

            vm.prank(account);
            LENDER.approve(msg.sender, 1);
        }

        (address wallet, ) = LENDER.couriers(id);
        if (wallet == account || !alreadyEnrolledCourier[id] || LENDER.balanceOf(account) > 0) {
            vm.prank(msg.sender);
            vm.expectRevert();
            LENDER.creditCourier(id, account);
            return;
        }

        vm.prank(msg.sender);
        LENDER.creditCourier(id, account);

        assert(LENDER.courierOf(account) == id);
        assert(LENDER.principleOf(account) == 0);
    }

    function creditCourier(uint16 i, address account) external {
        uint256 count = courierIds.length;
        if (count == 0) return;
        else creditCourier(courierIds[i % count], account);
    }

    function accrueInterest(uint16 elapsedTime) external {
        if (elapsedTime > 0) {
            vm.warp(block.timestamp + elapsedTime);
        }
        vm.prank(msg.sender);
        LENDER.accrueInterest();
    }

    function deposit(uint112 amount, address to) public returns (uint256 shares) {
        if (!alreadyHolder[to]) {
            holders.push(to);
            alreadyHolder[to] = true;
        }

        amount = uint112(amount % LENDER.maxDeposit(msg.sender));

        // make sure `msg.sender` has enough assets to make the deposit
        MockERC20 asset = MockERC20(address(LENDER.asset()));
        asset.mint(msg.sender, amount);

        // approve `ROUTER` to transfer `from`'s assets
        vm.prank(msg.sender);
        asset.approve(address(ROUTER), amount);

        // collect data before deposit
        uint256 lastBalance = LENDER.lastBalance();
        uint256 totalSupply = LENDER.totalSupply();
        uint256 balanceOfTo = LENDER.balanceOf(to);

        shares = LENDER.previewDeposit(amount);
        if (shares == 0 || lastBalance + amount > type(uint112).max) {
            vm.prank(msg.sender);
            vm.expectRevert(bytes("Aloe: zero impact"));
            ROUTER.deposit(LENDER, amount, to);
            amount = 0;
        } else {
            vm.prank(msg.sender);
            assert(ROUTER.deposit(LENDER, amount, to) == shares);
        }

        assert(LENDER.lastBalance() == lastBalance + amount);
        assert(LENDER.totalSupply() >= totalSupply + shares); // >= (not ==) due to reserves accrual
        if (to != LENDER.RESERVE()) {
            assert(LENDER.balanceOf(to) == balanceOfTo + shares);
        } else {
            uint256 newReservesShares = LENDER.totalSupply() - (totalSupply + shares);
            assert(LENDER.balanceOf(to) == balanceOfTo + shares + newReservesShares);
        }
    }

    function deposit(uint112 amount) external returns (uint256 shares) {
        shares = deposit(amount, msg.sender);
    }

    function depositReserve(uint112 amount) external returns (uint256 shares) {
        shares = deposit(amount, LENDER.RESERVE());
    }

    function redeem(uint112 shares, address recipient, address owner) public returns (uint256 amount) {
        uint256 maxRedeem = LENDER.maxRedeem(owner);
        shares = uint112(shares % (maxRedeem + 1));

        ERC20 asset = LENDER.asset();

        if (owner != msg.sender) {
            vm.prank(owner);
            LENDER.approve(msg.sender, shares);
        }

        // collect data before redeem
        uint256 lastBalance = LENDER.lastBalance();
        uint256 balanceOfOwner = LENDER.balanceOf(owner);
        uint256 assetBalanceOfRecipient = asset.balanceOf(recipient);

        amount = LENDER.previewRedeem(shares);
        if (amount == 0) {
            vm.prank(msg.sender);
            vm.expectRevert(bytes("Aloe: zero impact"));
            LENDER.redeem(shares, recipient, owner);
        } else {
            vm.prank(msg.sender);
            assert(LENDER.redeem(shares, recipient, owner) == amount);
        }

        assert(LENDER.lastBalance() == lastBalance - amount);
        assert(asset.balanceOf(recipient) == assetBalanceOfRecipient + amount);
        if (owner != LENDER.RESERVE()) {
            assert(LENDER.balanceOf(owner) == balanceOfOwner - shares);
        } else {
            assert(LENDER.balanceOf(owner) >= balanceOfOwner - shares);
        }
    }

    function redeem(uint112 shares, address recipient) external returns (uint256 amount) {
        amount = redeem(shares, recipient, msg.sender);
    }

    function redeemReserve(uint112 shares, address recipient) external returns (uint256 amount) {
        amount = redeem(shares, recipient, LENDER.RESERVE());
    }

    // TODO: redeemMax

    function borrow(uint112 amount, address recipient) external returns (uint256 units) {
        // allow `msg.sender` to borrow stuff
        if (LENDER.borrows(msg.sender) == 0) {
            vm.expectRevert("Aloe: not a borrower");
            LENDER.borrow(amount, recipient);

            vm.prank(LENDER.FACTORY());
            LENDER.whitelist(msg.sender);

            // `msg.sender` is now a borrower
            borrowers.push(msg.sender);
        }

        ERC20 asset = LENDER.asset();
        uint256 borrowBase = LENDER.borrowBase();
        uint256 borrowBalance = LENDER.borrowBalance(msg.sender);
        uint256 lastBalance = LENDER.lastBalance();
        uint256 assetBalanceOfRecipient = asset.balanceOf(recipient);

        if (amount > lastBalance) {
            vm.prank(msg.sender);
            vm.expectRevert();
            LENDER.borrow(amount, recipient);

            amount = uint112(amount % (lastBalance + 1));
        }

        vm.prank(msg.sender);
        units = LENDER.borrow(amount, recipient);

        // assert(units > 0); TODO: currently we're not checking this. at least check in borrow, maybe in repay too
        assert(LENDER.borrowBase() == borrowBase + units);
        assert(LENDER.lastBalance() == lastBalance - amount);
        assert(asset.balanceOf(recipient) == assetBalanceOfRecipient + amount);
        borrowBalance += amount;
        uint256 borrowBalanceNew = LENDER.borrowBalance(msg.sender);
        assert(borrowBalance <= borrowBalanceNew && borrowBalanceNew <= borrowBalance + 1);

        // ensure we didn't wipe out the whitelist flag
        assert(LENDER.borrows(msg.sender) > 0);
    }

    function repay(uint112 amount, address beneficiary) public returns (uint256) {
        uint256 b = LENDER.borrows(beneficiary);
        if (b == 0) {
            vm.prank(msg.sender);
            vm.expectRevert(bytes("Aloe: not a borrower"));
            LENDER.repay(amount, beneficiary);
            return 0;
        }

        // TODO: borrowBalance should work here (or at the very lest borrowBalanceStored; but they don't)
        uint256 maxRepay = (b - 1) * LENDER.borrowIndex() / BORROWS_SCALER;
        if (amount > maxRepay) {
            vm.prank(msg.sender);
            vm.expectRevert(bytes("Aloe: repay too much"));
            LENDER.repay(amount, beneficiary);

            amount = uint112(amount % (maxRepay + 1));
        }

        // Give `msg.sender` requisite assets
        MockERC20 asset = MockERC20(address(LENDER.asset()));
        asset.mint(msg.sender, amount);

        // Expect failure because `msg.sender` hasn't yet send funds to `LENDER`
        if (amount > 0) {
            vm.prank(msg.sender);
            vm.expectRevert(bytes("Aloe: insufficient pre-pay"));
            LENDER.repay(amount, beneficiary);
        }

        // Send repayment to `LENDER`
        vm.prank(msg.sender);
        asset.transfer(address(LENDER), amount);

        // Collect data before repay
        uint256 lastBalance = LENDER.lastBalance();
        uint256 borrowBase = LENDER.borrowBase();

        vm.prank(msg.sender);
        uint256 units = LENDER.repay(amount, beneficiary);

        assert(LENDER.lastBalance() == lastBalance + amount);
        assert(LENDER.borrowBase() == borrowBase - units);
        assert(LENDER.borrows(beneficiary) > 0);
        assert(LENDER.borrows(beneficiary) == b - units);

        return units;
    }

    function repay(uint112 amount, uint16 i) external returns (uint256) {
        uint256 count = borrowers.length;
        if (count == 0) return 0;
        else return repay(amount, borrowers[i % count]);
    }

    // TODO: repayMax

    function transfer(address to, uint112 shares) external returns (bool) {
        if (LENDER.courierOf(msg.sender) != 0 || LENDER.courierOf(to) != 0) {
            vm.prank(msg.sender);
            vm.expectRevert();
            LENDER.transfer(to, shares);
            return false;
        }

        uint256 balance = LENDER.balanceOf(msg.sender);
        if (balance < shares) {
            vm.prank(msg.sender);
            vm.expectRevert();
            LENDER.transfer(to, shares);

            shares = balance > 0 ? uint112(shares % (balance + 1)) : 0;
        }

        if (!alreadyHolder[to]) {
            holders.push(to);
            alreadyHolder[to] = true;
        }

        vm.prank(msg.sender);
        return LENDER.transfer(to, shares);
    }
}
