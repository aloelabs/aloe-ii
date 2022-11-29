// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

import "forge-std/Test.sol";

import "src/Lender.sol";

import {deploySingleLender} from "./Utils.sol";

contract LenderGasTest is Test {
    ERC20 constant asset = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    Lender immutable lender;

    address immutable bob;

    constructor() {
        lender = deploySingleLender(asset, address(this), new InterestModel());
        bob = makeAddr("bob");
    }

    function setUp() public {
        lender.whitelist(address(this));
        lender.whitelist(bob);

        // Give `bob` 1 WETH
        deal(address(asset), bob, 1e18);

        // `bob` deposits 0.5 WETH
        hoax(bob, 1e18);
        asset.transfer(address(lender), 0.50001e18);
        lender.deposit(0.5e18, bob);

        // `bob` allows this test contract to manage his WETH
        hoax(bob);
        asset.approve(address(this), type(uint256).max);

        // `bob` allows this test contract to manage his WETH+
        hoax(bob);
        lender.approve(address(this), type(uint256).max);

        // `bob` borrows 0.1 ETH
        hoax(bob);
        lender.borrow(0.1e18, bob);

        skip(3600); // seconds
        lender.accrueInterest();
    }

    function test_accrueInterest() public {
        skip(3600); // seconds
        lender.accrueInterest();
    }

    function test_deposit() public {
        asset.transferFrom(bob, address(lender), 0.1e18);
        lender.deposit(0.1e18, bob);
    }

    function test_redeem() public {
        lender.redeem(0.1e18, bob, bob);
    }

    function test_borrow() public {
        lender.borrow(0.2e18, bob);
    }

    function test_repay() public {
        asset.transferFrom(bob, address(lender), 0.1e18);
        lender.repay(0.1e18, bob);
    }
}
