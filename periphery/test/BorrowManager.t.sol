// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

import "forge-std/Test.sol";

import "aloe-ii-core/Lender.sol";
import "aloe-ii-core/Borrower.sol";
import "aloe-ii-core/Factory.sol";
import "aloe-ii-core/InterestModel.sol";
import "src/BorrowManager.sol";

contract BorrowManagerTest is Test {
    IUniswapV3Pool constant pool = IUniswapV3Pool(0xC2e9F25Be6257c210d7Adf0D4Cd6E3E881ba25f8);
    ERC20 constant asset0 = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    ERC20 constant asset1 = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    address public immutable hayden;
    Borrower public borrower;
    BorrowManager public borrowManager;

    Factory public immutable factory;

    Lender public lender0;
    Lender public lender1;

    constructor() {
        hayden = makeAddr("hayden");
        factory = new Factory(new InterestModel());
    }

    function setUp() public {
        factory.createMarket(pool);
        borrowManager = new BorrowManager(factory);
        (lender0, lender1, ) = factory.getMarket(pool);
        borrower = Borrower(factory.createBorrower(pool, hayden));
    }

    function test_borrow_dai() public {
        _prepareKitties();

        // give this contract some tokens
        deal(address(asset0), address(borrower), 10e18);
        deal(address(asset1), address(borrower), 0);

        bool[4] memory allowances;
        bytes memory data = abi.encode(0, 5e18, 0);
        hoax(hayden);
        borrower.modify(borrowManager, data, allowances);

        assertEq(lender0.borrowBalance(address(borrower)), 5e18);
        assertEq(lender1.borrowBalance(address(borrower)), 0);
        assertEq(asset0.balanceOf(hayden), 5e18);
        assertEq(asset1.balanceOf(hayden), 0);
    }

    function test_borrow_weth() public {
        _prepareKitties();

        // give this contract some tokens
        deal(address(asset0), address(borrower), 10e18);
        deal(address(asset1), address(borrower), 0);

        bool[4] memory allowances;
        bytes memory data = abi.encode(0, 0, 1e15);
        hoax(hayden);
        borrower.modify(borrowManager, data, allowances);

        assertEq(lender0.borrowBalance(address(borrower)), 0);
        assertEq(lender1.borrowBalance(address(borrower)), 1e15);
        assertEq(asset0.balanceOf(hayden), 0);
        assertEq(asset1.balanceOf(hayden), 1e15);
    }

    function test_borrow_weth_fail_zero() public {
        _prepareKitties();

        // give this contract some tokens
        deal(address(asset0), address(borrower), 10e18);
        deal(address(asset1), address(borrower), 0);

        bool[4] memory allowances;
        bytes memory data = abi.encode(0, 10e20, 0);
        hoax(hayden);
        vm.expectRevert();
        borrower.modify(borrowManager, data, allowances);

        assertEq(lender0.borrowBalance(address(borrower)), 0);
        assertEq(lender1.borrowBalance(address(borrower)), 0);
        assertEq(asset0.balanceOf(hayden), 0);
        assertEq(asset1.balanceOf(hayden), 0);
    }

    function test_borrow_weth_fail_one() public {
        _prepareKitties();

        // give this contract some tokens
        deal(address(asset0), address(borrower), 10e18);
        deal(address(asset1), address(borrower), 0);

        bool[4] memory allowances;
        bytes memory data = abi.encode(0, 10e20, 0);
        hoax(hayden);
        vm.expectRevert();
        borrower.modify(borrowManager, data, allowances);

        assertEq(lender0.borrowBalance(address(borrower)), 0);
        assertEq(lender1.borrowBalance(address(borrower)), 0);
        assertEq(asset0.balanceOf(hayden), 0);
        assertEq(asset1.balanceOf(hayden), 0);
    }

    function _prepareKitties() private {
        address alice = makeAddr("alice");

        deal(address(asset0), address(lender0), 20e18);
        lender0.deposit(20e18, alice);

        deal(address(asset1), address(lender1), 3e18);
        lender1.deposit(3e18, alice);
    }
}
