// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "forge-std/Test.sol";

import "src/Lender.sol";

import {deploySingleLender} from "./Utils.sol";

contract LenderTest is Test {
    ERC20 constant asset = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    Lender lender;

    bool shouldEnableBorrowAndRepay;

    // mock Factory
    function isBorrowerAllowed(Lender _lender, address _account) external returns (bool) {
        return shouldEnableBorrowAndRepay;
    }

    function setUp() public {
        lender = deploySingleLender(asset, address(this), new InterestModel());
    }

    function test_accrueInterest() public {
        lender.accrueInterest();
    }

    function test_deposit() public returns (address alice) {
        alice = makeAddr("alice");
        deal(address(asset), alice, 10000e6);

        hoax(alice, 1e18);
        asset.transfer(address(lender), 100e6);

        hoax(alice);
        uint256 shares = lender.deposit(100e6, alice);

        assertEq(shares, 100e6);
        assertEq(lender.totalSupply(), 100e6);
        assertEq(asset.balanceOf(alice), 9900e6);
    }

    function test_withdraw() public {
        address alice = test_deposit();

        hoax(alice);
        uint256 amount = lender.redeem(100e6, alice, address(0));

        assertEq(amount, 100e6);
        assertEq(lender.totalSupply(), 0);
        assertEq(asset.balanceOf(alice), 10000e6);
    }

    function testFail_borrow() public {
        deal(address(asset), address(lender), 10000e6);

        address bob = makeAddr("bob");
        hoax(bob, 1e18);
        lender.borrow(100e6, bob);
    }

    function testFail_repay() public {
        address cindy = makeAddr("cindy");
        deal(address(asset), cindy, 10000e6);

        hoax(cindy, 1e18);
        lender.repay(100e6, cindy);
    }

    function test_borrow() public {
        address alice = test_deposit();

        shouldEnableBorrowAndRepay = true;

        address jim = makeAddr("jim");
        hoax(jim, 1e18);
        lender.borrow(10e6, jim);

        assertEq(asset.balanceOf(jim), 10e6);
        assertEq(lender.balanceOf(jim), 0);
        assertEq(lender.borrowBalanceCurrent(jim), 10e6);

        skip(3600); // seconds

        console.log(FullMath.mulDiv(
            lender.balanceOf(alice),
            lender.lastBalance() + FullMath.mulDiv(lender.borrowBase(), lender.borrowIndex(), lender.BORROWS_SCALER()),
            lender.totalSupply()
        ));

        lender.accrueInterest();

        console.log(FullMath.mulDiv(
            lender.balanceOf(alice),
            lender.lastBalance() + FullMath.mulDiv(lender.borrowBase(), lender.borrowIndex(), lender.BORROWS_SCALER()),
            lender.totalSupply()
        ));


        assertEq(asset.balanceOf(jim), 10e6);
        assertEq(lender.borrowBalanceCurrent(jim), 10000022);

        assertEq(lender.balanceOfUnderlying(alice), 100000020);
    }
}
