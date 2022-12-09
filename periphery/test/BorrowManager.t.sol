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

        uint8 action = 0;
        uint8[] memory actions = new uint8[](1);
        actions[0] = action;
        bytes memory arg = abi.encode([5e18, 0]);
        bytes[] memory args = new bytes[](1);
        args[0] = arg;
        bytes memory data = abi.encode(actions, args);
        bool[4] memory allowances;

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

        uint8 action = 0;
        uint8[] memory actions = new uint8[](1);
        actions[0] = action;
        bytes memory arg = abi.encode([0, 1e15]);
        bytes[] memory args = new bytes[](1);
        args[0] = arg;
        bytes memory data = abi.encode(actions, args);
        bool[4] memory allowances;

        hoax(hayden);
        borrower.modify(borrowManager, data, allowances);

        assertEq(lender0.borrowBalance(address(borrower)), 0);
        assertEq(lender1.borrowBalance(address(borrower)), 1e15);
        assertEq(asset0.balanceOf(hayden), 0);
        assertEq(asset1.balanceOf(hayden), 1e15);
    }

    function test_borrow_dai_and_weth_combined() public {
        _prepareKitties();

        // give this contract some tokens
        deal(address(asset0), address(borrower), 20e18);
        deal(address(asset1), address(borrower), 0);

        uint8 action0 = 0;
        uint8[] memory actions = new uint8[](1);
        actions[0] = action0;
        bytes memory arg0 = abi.encode([5e18, 1e15]);
        bytes[] memory args = new bytes[](1);
        args[0] = arg0;
        bytes memory data = abi.encode(actions, args);
        bool[4] memory allowances;

        hoax(hayden);
        borrower.modify(borrowManager, data, allowances);

        assertEq(lender0.borrowBalance(address(borrower)), 5e18);
        assertEq(lender1.borrowBalance(address(borrower)), 1e15);
        assertEq(asset0.balanceOf(hayden), 5e18);
        assertEq(asset1.balanceOf(hayden), 1e15);
    }

    function test_borrow_dai_and_weth_separate() public {
        _prepareKitties();

        // give this contract some tokens
        deal(address(asset0), address(borrower), 20e18);
        deal(address(asset1), address(borrower), 0);

        uint8 action0 = 0;
        uint8 action1 = 0;
        uint8[] memory actions = new uint8[](2);
        actions[0] = action0;
        actions[1] = action1;
        bytes memory arg0 = abi.encode([5e18, 0]);
        bytes memory arg1 = abi.encode([0, 1e15]);
        bytes[] memory args = new bytes[](2);
        args[0] = arg0;
        args[1] = arg1;
        bytes memory data = abi.encode(actions, args);
        bool[4] memory allowances;

        hoax(hayden);
        borrower.modify(borrowManager, data, allowances);

        assertEq(lender0.borrowBalance(address(borrower)), 5e18);
        assertEq(lender1.borrowBalance(address(borrower)), 1e15);
        assertEq(asset0.balanceOf(hayden), 5e18);
        assertEq(asset1.balanceOf(hayden), 1e15);
    }

    function test_borrow_dai_fail() public {
        _prepareKitties();

        // give this contract some tokens
        deal(address(asset0), address(borrower), 10e18);
        deal(address(asset1), address(borrower), 0);

        uint8 action = 0;
        uint8[] memory actions = new uint8[](1);
        actions[0] = action;
        bytes memory arg = abi.encode([10e19, 0]);
        bytes[] memory args = new bytes[](1);
        args[0] = arg;
        bytes memory data = abi.encode(actions, args);
        bool[4] memory allowances;

        hoax(hayden);
        vm.expectRevert();
        borrower.modify(borrowManager, data, allowances);

        assertEq(lender0.borrowBalance(address(borrower)), 0);
        assertEq(lender1.borrowBalance(address(borrower)), 0);
        assertEq(asset0.balanceOf(hayden), 0);
        assertEq(asset1.balanceOf(hayden), 0);
    }

    function test_borrow_weth_fail() public {
        _prepareKitties();

        // give this contract some tokens
        deal(address(asset0), address(borrower), 10e18);
        deal(address(asset1), address(borrower), 0);

        uint8 action = 0;
        uint8[] memory actions = new uint8[](1);
        actions[0] = action;
        bytes memory arg = abi.encode([0, 10e18]);
        bytes[] memory args = new bytes[](1);
        args[0] = arg;
        bytes memory data = abi.encode(actions, args);
        bool[4] memory allowances;

        hoax(hayden);
        vm.expectRevert();
        borrower.modify(borrowManager, data, allowances);

        assertEq(lender0.borrowBalance(address(borrower)), 0);
        assertEq(lender1.borrowBalance(address(borrower)), 0);
        assertEq(asset0.balanceOf(hayden), 0);
        assertEq(asset1.balanceOf(hayden), 0);
    }

    function test_repay_dai() public {
        test_borrow_dai();

        deal(address(asset0), hayden, 5e18);
        deal(address(asset1), hayden, 0);

        uint8 action = 1;
        uint8[] memory actions = new uint8[](1);
        actions[0] = action;
        bytes memory arg = abi.encode([5e18, 0]);
        bytes[] memory args = new bytes[](1);
        args[0] = arg;
        bytes memory data = abi.encode(actions, args);
        bool[4] memory allowances;

        hoax(hayden);
        asset0.approve(address(borrowManager), 5e18);
        hoax(hayden);
        borrower.modify(borrowManager, data, allowances);

        assertEq(lender0.borrowBalance(address(borrower)), 0);
        assertEq(lender1.borrowBalance(address(borrower)), 0);
        assertEq(asset0.balanceOf(hayden), 0);
        assertEq(asset1.balanceOf(hayden), 0);
    }

    function test_repay_weth() public {
        test_borrow_weth();

        deal(address(asset0), hayden, 0);
        deal(address(asset1), hayden, 1e18);

        uint8 action = 1;
        uint8[] memory actions = new uint8[](1);
        actions[0] = action;
        bytes memory arg = abi.encode([0, 1e18]);
        bytes[] memory args = new bytes[](1);
        args[0] = arg;
        bytes memory data = abi.encode(actions, args);
        bool[4] memory allowances;

        hoax(hayden);
        asset1.approve(address(borrowManager), 1e18);
        hoax(hayden);
        borrower.modify(borrowManager, data, allowances);

        assertEq(lender0.borrowBalance(address(borrower)), 0);
        assertEq(lender1.borrowBalance(address(borrower)), 0);
        assertEq(asset0.balanceOf(hayden), 0);
        assertEq(asset1.balanceOf(hayden), 0);
    }

    // // TODO: Test repay both
    // // TODO: Test repay partial
    // // TODO: Test repay partial fail
    // // TODO: Test repay fail

    function test_withdraw_dai() public {
        // give this contract some tokens
        deal(address(asset0), address(borrower), 10e18);
        deal(address(asset1), address(borrower), 0);

        uint8 action = 2;
        uint8[] memory actions = new uint8[](1);
        actions[0] = action;
        bytes memory arg = abi.encode([10e18, 0]);
        bytes[] memory args = new bytes[](1);
        args[0] = arg;
        bytes memory data = abi.encode(actions, args);
        bool[4] memory allowances = [true, false, false, false];

        hoax(hayden);
        borrower.modify(borrowManager, data, allowances);

        assertEq(lender0.borrowBalance(address(borrower)), 0);
        assertEq(lender1.borrowBalance(address(borrower)), 0);
        assertEq(asset0.balanceOf(hayden), 10e18);
        assertEq(asset1.balanceOf(hayden), 0);
    }

    function test_withdraw_weth() public {
        // give this contract some tokens
        deal(address(asset0), address(borrower), 0);
        deal(address(asset1), address(borrower), 1e18);

        uint8 action = 2;
        uint8[] memory actions = new uint8[](1);
        actions[0] = action;
        bytes memory arg = abi.encode([0, 1e18]);
        bytes[] memory args = new bytes[](1);
        args[0] = arg;
        bytes memory data = abi.encode(actions, args);
        bool[4] memory allowances = [false, true, false, false];

        hoax(hayden);
        borrower.modify(borrowManager, data, allowances);

        assertEq(lender0.borrowBalance(address(borrower)), 0);
        assertEq(lender1.borrowBalance(address(borrower)), 0);
        assertEq(asset0.balanceOf(hayden), 0);
        assertEq(asset1.balanceOf(hayden), 1e18);
    }

    function test_withdraw_partial_dai() public {
        // give this contract some tokens
        deal(address(asset0), address(borrower), 10e18);
        deal(address(asset1), address(borrower), 0);

        uint8 action = 2;
        uint8[] memory actions = new uint8[](1);
        actions[0] = action;
        bytes memory arg = abi.encode([5e18, 0]);
        bytes[] memory args = new bytes[](1);
        args[0] = arg;
        bytes memory data = abi.encode(actions, args);
        bool[4] memory allowances = [true, false, false, false];

        hoax(hayden);
        borrower.modify(borrowManager, data, allowances);

        assertEq(asset0.balanceOf(address(borrower)), 5e18);
        assertEq(asset1.balanceOf(address(borrower)), 0);
        assertEq(asset0.balanceOf(hayden), 5e18);
        assertEq(asset1.balanceOf(hayden), 0);
    }

    function test_withdraw_partial_weth() public {
        // give this contract some tokens
        deal(address(asset0), address(borrower), 0);
        deal(address(asset1), address(borrower), 2e18);

        uint8 action = 2;
        uint8[] memory actions = new uint8[](1);
        actions[0] = action;
        bytes memory arg = abi.encode([0, 1e18]);
        bytes[] memory args = new bytes[](1);
        args[0] = arg;
        bytes memory data = abi.encode(actions, args);
        bool[4] memory allowances = [false, true, false, false];

        hoax(hayden);
        borrower.modify(borrowManager, data, allowances);

        assertEq(asset0.balanceOf(address(borrower)), 0);
        assertEq(asset1.balanceOf(address(borrower)), 1e18);
        assertEq(asset0.balanceOf(hayden), 0);
        assertEq(asset1.balanceOf(hayden), 1e18);
    }

    function test_withdraw_dai_and_weth() public {
        // give this contract some tokens
        deal(address(asset0), address(borrower), 10e18);
        deal(address(asset1), address(borrower), 1e18);

        uint8 action = 2;
        uint8[] memory actions = new uint8[](1);
        actions[0] = action;
        bytes memory arg = abi.encode([10e18, 1e18]);
        bytes[] memory args = new bytes[](1);
        args[0] = arg;
        bytes memory data = abi.encode(actions, args);
        bool[4] memory allowances = [true, true, false, false];

        hoax(hayden);
        borrower.modify(borrowManager, data, allowances);

        assertEq(asset0.balanceOf(address(borrower)), 0);
        assertEq(asset1.balanceOf(address(borrower)), 0);
        assertEq(asset0.balanceOf(hayden), 10e18);
        assertEq(asset1.balanceOf(hayden), 1e18);
    }

    function test_withdraw_dai_and_weth_partial() public {
        // give this contract some tokens
        deal(address(asset0), address(borrower), 10e18);
        deal(address(asset1), address(borrower), 2e18);

        uint8 action = 2;
        uint8[] memory actions = new uint8[](1);
        actions[0] = action;
        bytes memory arg = abi.encode([5e18, 1e18]);
        bytes[] memory args = new bytes[](1);
        args[0] = arg;
        bytes memory data = abi.encode(actions, args);
        bool[4] memory allowances = [true, true, false, false];

        hoax(hayden);
        borrower.modify(borrowManager, data, allowances);

        assertEq(asset0.balanceOf(address(borrower)), 5e18);
        assertEq(asset1.balanceOf(address(borrower)), 1e18);
        assertEq(asset0.balanceOf(hayden), 5e18);
        assertEq(asset1.balanceOf(hayden), 1e18);
    }

    function test_withdraw_dai_fail() public {
        // give this contract some tokens
        deal(address(asset0), address(borrower), 10e18);
        deal(address(asset1), address(borrower), 0);

        uint8 action = 2;
        uint8[] memory actions = new uint8[](1);
        actions[0] = action;
        bytes memory arg = abi.encode([11e18, 0]);
        bytes[] memory args = new bytes[](1);
        args[0] = arg;
        bytes memory data = abi.encode(actions, args);
        bool[4] memory allowances = [true, false, false, false];

        hoax(hayden);
        vm.expectRevert(abi.encodePacked("TRANSFER_FROM_FAILED"));
        borrower.modify(borrowManager, data, allowances);

        assertEq(asset0.balanceOf(address(borrower)), 10e18);
        assertEq(asset1.balanceOf(address(borrower)), 0);
        assertEq(asset0.balanceOf(hayden), 0);
        assertEq(asset1.balanceOf(hayden), 0);
    }

    function test_withdraw_weth_fail() public {
        // give this contract some tokens
        deal(address(asset0), address(borrower), 0);
        deal(address(asset1), address(borrower), 1e18);

        uint8 action = 2;
        uint8[] memory actions = new uint8[](1);
        actions[0] = action;
        bytes memory arg = abi.encode([0, 2e18]);
        bytes[] memory args = new bytes[](1);
        args[0] = arg;
        bytes memory data = abi.encode(actions, args);
        bool[4] memory allowances = [false, true, false, false];

        hoax(hayden);
        vm.expectRevert(abi.encodePacked("TRANSFER_FROM_FAILED"));
        borrower.modify(borrowManager, data, allowances);

        assertEq(asset0.balanceOf(address(borrower)), 0);
        assertEq(asset1.balanceOf(address(borrower)), 1e18);
        assertEq(asset0.balanceOf(hayden), 0);
        assertEq(asset1.balanceOf(hayden), 0);
    }

    function test_withdraw_dai_and_weth_one_fail() public {
        // give this contract some tokens
        deal(address(asset0), address(borrower), 10e18);
        deal(address(asset1), address(borrower), 1e18);

        uint8 action = 2;
        uint8[] memory actions = new uint8[](1);
        actions[0] = action;
        bytes memory arg = abi.encode([10e18, 2e18]);
        bytes[] memory args = new bytes[](1);
        args[0] = arg;
        bytes memory data = abi.encode(actions, args);
        bool[4] memory allowances = [true, true, false, false];

        hoax(hayden);
        vm.expectRevert(abi.encodePacked("TRANSFER_FROM_FAILED"));
        borrower.modify(borrowManager, data, allowances);

        assertEq(asset0.balanceOf(address(borrower)), 10e18);
        assertEq(asset1.balanceOf(address(borrower)), 1e18);
        assertEq(asset0.balanceOf(hayden), 0);
        assertEq(asset1.balanceOf(hayden), 0);
    }

    function test_withdraw_dai_and_weth_other_fail() public {
        // give this contract some tokens
        deal(address(asset0), address(borrower), 10e18);
        deal(address(asset1), address(borrower), 1e18);

        uint8 action = 2;
        uint8[] memory actions = new uint8[](1);
        actions[0] = action;
        bytes memory arg = abi.encode([20e18, 1e18]);
        bytes[] memory args = new bytes[](1);
        args[0] = arg;
        bytes memory data = abi.encode(actions, args);
        bool[4] memory allowances = [true, true, false, false];

        hoax(hayden);
        vm.expectRevert(abi.encodePacked("TRANSFER_FROM_FAILED"));
        borrower.modify(borrowManager, data, allowances);

        assertEq(asset0.balanceOf(address(borrower)), 10e18);
        assertEq(asset1.balanceOf(address(borrower)), 1e18);
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
