// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import "src/Factory.sol";
import "src/Lender.sol";
import "src/RateModel.sol";

import {FactoryForLenderTests} from "../Utils.sol";

contract LenderGasTest is Test {
    ERC20 constant asset = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    Lender immutable lender;

    address immutable bob;

    address immutable alice;

    constructor() {
        vm.createSelectFork(vm.rpcUrl("mainnet"));
        vm.rollFork(15_348_451);

        FactoryForLenderTests factory = new FactoryForLenderTests(new RateModel(), ERC20(address(0)));
        lender = factory.deploySingleLender(asset);
        bob = makeAddr("bob");
        alice = makeAddr("alice");
    }

    function setUp() public {
        vm.startPrank(address(lender.FACTORY()));
        lender.whitelist(address(this));
        lender.whitelist(bob);
        vm.stopPrank();

        // Give `bob` and `alice` 1 WETH each
        deal(address(asset), bob, 1e18);
        deal(address(asset), alice, 1e18);

        // `bob` deposits 0.5 WETH
        hoax(bob, 1e18);
        asset.transfer(address(lender), 0.50001e18);
        lender.deposit(0.5e18, bob);

        // `bob` allows this test contract to manage his WETH
        vm.prank(bob);
        asset.approve(address(this), type(uint256).max);

        // `bob` allows this test contract to manage his WETH+
        vm.prank(bob);
        lender.approve(address(this), type(uint256).max);

        // `bob` borrows 0.1 ETH
        vm.prank(bob);
        lender.borrow(0.1e18, bob);

        // `alice` allows this test contract to manage her WETH;
        vm.prank(alice);
        asset.approve(address(this), type(uint256).max);

        // `alice` allows this test contract to manage her WETH+
        vm.prank(alice);
        lender.approve(address(this), type(uint256).max);

        // Setup courier#1
        Factory factory = lender.FACTORY();
        vm.prank(address(12345));
        factory.enrollCourier(1, 1000);

        // `alice` deposits 0.5 WETH, crediting courier#1
        asset.transferFrom(alice, address(lender), 0.5e18);
        lender.deposit(0.5e18, alice, 1);

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

    function test_depositWithCourier() public {
        asset.transferFrom(alice, address(lender), 0.1e18);
        lender.deposit(0.1e18, alice);
    }

    function test_redeem() public {
        lender.redeem(0.1e18, bob, bob);
    }

    function test_redeemWithCourier() public {
        lender.redeem(0.1e18, alice, alice);
    }

    function test_borrow() public {
        lender.borrow(0.2e18, bob);
    }

    function test_repay() public {
        asset.transferFrom(bob, address(lender), 0.1e18);
        lender.repay(0.1e18, bob);
    }
}
