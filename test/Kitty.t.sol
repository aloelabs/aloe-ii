// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

import "forge-std/Test.sol";

import {ERC20} from "@rari-capital/solmate/src/tokens/ERC20.sol";

import "src/InterestModel.sol";
import "src/Kitty.sol";

contract KittyTest is Test {
    ERC20 constant asset = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    Kitty kitty;

    bool shouldEnableBorrowAndRepay;

    // mock Factory
    function isMarginAccountAllowed(Kitty _kitty, address _account) external returns (bool) {
        return shouldEnableBorrowAndRepay;
    }

    function setUp() public {
        kitty = new Kitty(
            asset,
            new InterestModel(),
            address(this)
        );
    }

    function test_deposit() public returns (address alice) {
        alice = makeAddr("alice");
        deal(address(asset), alice, 10000e6);

        hoax(alice, 1e18);
        asset.approve(address(kitty), type(uint256).max);

        hoax(alice);
        uint256 shares = kitty.deposit(100e6);

        assertEq(shares, 100e6);
        assertEq(kitty.totalSupply(), 100e6);
        assertEq(asset.balanceOf(alice), 9900e6);
    }

    function test_withdraw() public {
        address alice = test_deposit();

        hoax(alice);
        uint256 amount = kitty.withdraw(100e6);

        assertEq(amount, 100e6);
        assertEq(kitty.totalSupply(), 0);
        assertEq(asset.balanceOf(alice), 10000e6);
    }

    function testFail_borrow() public {
        deal(address(asset), address(kitty), 10000e6);    

        address bob = makeAddr("bob");
        hoax(bob, 1e18);    
        kitty.borrow(100e6);
    }

    function testFail_repay() public {
        address cindy = makeAddr("cindy");
        deal(address(asset), cindy, 10000e6);    

        hoax(cindy, 1e18);    
        kitty.repay(100e6);
    }

    function test_borrow() public {
        address alice = test_deposit();

        shouldEnableBorrowAndRepay = true;

        address jim = makeAddr("jim");
        hoax(jim, 1e18);
        kitty.borrow(10e6);

        assertEq(asset.balanceOf(jim), 10e6);
        assertEq(kitty.balanceOf(jim), 0);
        assertEq(kitty.borrowBalanceCurrent(jim), 10e6);

        skip(3600); // seconds
        hoax(jim);
        kitty.accrueInterest();

        assertEq(asset.balanceOf(jim), 10e6);
        assertEq(kitty.borrowBalanceCurrent(jim), 10000022);

        assertEq(kitty.balanceOfUnderlying(alice), 100000020);
    }
}
