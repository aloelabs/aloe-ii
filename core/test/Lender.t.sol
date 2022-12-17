// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

import "forge-std/Test.sol";

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import "src/Lender.sol";

import {deploySingleLender} from "./Utils.sol";

contract LenderTest is Test {
    using stdStorage for StdStorage;

    ERC20 asset;

    Lender lender;

    function setUp() public {
        asset = new MockERC20("Token", "TKN", 18);
        lender = deploySingleLender(asset, address(2), new InterestModel());
    }

    function test_whitelist(address attacker, address borrower, uint256 value) public {
        address factory = lender.FACTORY();

        if (attacker == factory) return;

        // Attacker cannot whitelist new borrowers
        vm.expectRevert(bytes(""));
        hoax(attacker);
        lender.whitelist(borrower);

        // Factory can whitelist new borrowers
        hoax(factory);
        lender.whitelist(borrower);
        assertEq(lender.borrows(borrower), 1);

        // Whitelisting does not increase debt
        assertEq(lender.borrowBalanceStored(borrower), 0);

        // Whitelisting cannot erase debt
        if (value == 0) value++;
        stdstore.target(address(lender)).sig("borrows(address)").with_key(borrower).depth(0).checked_write(value);
        vm.expectRevert(bytes(""));
        hoax(factory);
        lender.whitelist(borrower);
    }

    function test_accrueInterest(uint256 accrualFactor) public {
        // Give this test contract some shares
        deal(address(asset), address(lender), 2e18);
        lender.deposit(2e18, address(this));

        // Borrow some tokens (so that interest will actually accrue)
        hoax(lender.FACTORY());
        lender.whitelist(address(this));
        lender.borrow(1e18, address(this));

        // Mock interest model
        accrualFactor = accrualFactor % 0.1e12;
        vm.mockCall(
            address(lender.interestModel()),
            abi.encodeWithSelector(InterestModel.getAccrualFactor.selector, 13, 0.5e18),
            abi.encode(accrualFactor)
        );

        uint256 newInventory = 1e18 + FixedPointMathLib.mulDivDown(1e18, accrualFactor + 1e12, 1e12);
        uint256 interest = newInventory - 2e18;
        uint256 reserves = interest / lender.reserveFactor();

        uint256 epsilon = 2;

        // Initially, the `lender` holds 1e18 and has lent out 1e18
        assertEqDecimal(lender.totalAssets(), 2e18, 18);
        // Now skip forward in time, but don't modify `lender` state yet
        skip(13);
        // `totalAssets` uses view-only methods to compute interest, so it should have updated
        assertEqDecimal(lender.totalAssets(), newInventory, 18);
        // But `balanceOfUnderlyingStored` just reads from storage, so it should still have old value
        assertEqDecimal(lender.balanceOfUnderlyingStored(address(this)), 2e18, 18);
        // Now actually store interest updates
        lender.accrueInterest();
        // Both `totalAssets` and `balanceOfUnderlyingStored` should have updated now
        assertEqDecimal(lender.totalAssets(), newInventory, 18);
        assertLeDecimal(
            stdMath.delta(lender.balanceOfUnderlyingStored(address(this)), newInventory - reserves),
            epsilon,
            18
        );
        // Make sure `borrowIndex` is just as precise as `accrualFactor`
        if (accrualFactor > 0) assertGt(lender.borrowIndex(), 1e12);

        assertEq(lender.lastAccrualTime(), block.timestamp);
        assertLeDecimal(stdMath.delta(lender.balanceOfUnderlying(lender.RESERVE()), reserves), epsilon, 18);

        vm.clearMockedCalls();
    }

    function test_cannotInflateSharePrice(uint128 amount) public {
        deal(address(asset), address(lender), 1e18);
        lender.deposit(1e18, address(12345));

        uint256 balance = lender.balanceOfUnderlying(address(12345));
        deal(address(asset), address(lender), amount);

        assertEq(lender.balanceOfUnderlying(address(12345)), balance);
    }

    function test_cannotDepositWithoutERC20Transfer(uint112 amount, address to) public {
        if (amount == 0) amount++;

        deal(address(asset), address(lender), amount - 1);
        vm.expectRevert(bytes(""));
        lender.deposit(amount, to);
    }

    function test_previewAndDeposit(uint112 amount, address to) public {
        if (amount == 0) amount++;

        uint256 expectedShares = lender.previewDeposit(amount);
        uint256 totalSupply = lender.totalSupply();

        deal(address(asset), address(lender), amount);
        uint256 shares = lender.deposit(amount, to);

        // Check share correctness
        assertEq(shares, expectedShares);
        assertEq(lender.balanceOf(to), expectedShares);
        assertEq(lender.totalSupply(), totalSupply + shares);

        // Check underlying correctness
        assertEq(lender.balanceOfUnderlyingStored(to), amount);
        assertEq(lender.balanceOfUnderlying(to), amount);
    }

    function test_depositMultipleDestinations(uint112 amountA, uint112 amountB, address toA, address toB) public {
        if (uint256(amountA) + uint256(amountB) > type(uint112).max) {
            amountA = amountA / 2;
            amountB = amountB / 2;
        }

        deal(address(asset), address(lender), amountA + amountB);
        if (amountA == 0) {
            vm.expectRevert(bytes("Aloe: 0 shares"));
            lender.deposit(amountA, toA);
        } else lender.deposit(amountA, toA);
        if (amountB == 0) {
            vm.expectRevert(bytes("Aloe: 0 shares"));
            lender.deposit(amountB, toB);
        } else lender.deposit(amountB, toB);

        assertEq(lender.balanceOfUnderlying(toA), amountA);
        assertEq(lender.balanceOfUnderlying(toB), amountB);
    }

    function test_previewAndDepositWithInterest(uint16 time, uint112 amount, address to) public {
        skip(time);
        test_previewAndDeposit(amount, to);
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
        uint256 amount = lender.redeem(100e6, alice, alice);

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

        address jim = makeAddr("jim");
        lender.whitelist(jim);

        hoax(jim, 1e18);
        lender.borrow(10e6, jim);

        assertEq(asset.balanceOf(jim), 10e6);
        assertEq(lender.balanceOf(jim), 0);
        assertEq(lender.borrowBalance(jim), 10e6);

        skip(3600); // seconds
        lender.accrueInterest();

        assertEq(asset.balanceOf(jim), 10e6);
        assertEq(lender.borrowBalance(jim), 10000023);

        assertEq(lender.balanceOfUnderlying(alice), 100000020);
        assertEq(lender.balanceOfUnderlyingStored(alice), 100000020);
    }
}
