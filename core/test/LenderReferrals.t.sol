// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

import "forge-std/Test.sol";

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import "src/Lender.sol";

import {deploySingleLender} from "./Utils.sol";

contract LenderReferralsTest is Test {
    using stdStorage for StdStorage;

    ERC20 asset;

    Lender lender;

    function setUp() public {
        asset = new MockERC20("Token", "TKN", 18);
        lender = deploySingleLender(asset, address(2), new RateModel());
    }

    function test_canEnrollCourier(uint32 id, address wallet, uint16 cut) public {
        (id, wallet, cut) = _enroll(id, wallet, cut);

        (address a, uint16 b) = lender.couriers(id);
        assertEq(a, wallet);
        assertEq(b, cut);
    }

    function test_cannotSetCutTo0(uint32 id, address wallet) public {
        vm.assume(id != 0);

        vm.expectRevert(bytes(""));
        lender.enrollCourier(id, wallet, 0);
    }

    function test_cannotSetCutAbove10000(uint32 id, address wallet, uint16 cut) public {
        vm.assume(id != 0);
        if (cut < 10_000) cut += 10_000;

        vm.expectRevert(bytes(""));
        lender.enrollCourier(id, wallet, cut);
    }

    function test_cannotEnrollId0(address wallet, uint16 cut) public {
        vm.assume(cut != 0);

        vm.expectRevert(bytes(""));
        lender.enrollCourier(0, wallet, cut);
    }

    function test_cannotEditCourierCut(uint32 id, address wallet, uint16 cutA, uint16 cutB) public {
        cutA = cutA % 10_000;
        cutB = cutB % 10_000;

        vm.assume(id != 0);
        vm.assume(cutA != 0);
        vm.assume(cutB != 0);

        lender.enrollCourier(id, wallet, cutA);

        vm.expectRevert(bytes(""));
        lender.enrollCourier(id, wallet, cutB);
    }

    function test_cannotEditCourierWallet(uint32 id, address walletA, address walletB, uint16 cut) public {
        cut = cut % 10_000;
        vm.assume(id != 0);
        vm.assume(cut != 0);

        lender.enrollCourier(id, walletA, cut);

        vm.expectRevert(bytes(""));
        lender.enrollCourier(id, walletB, cut);
    }

    function test_canCreditCourier(uint32 id, address wallet, uint16 cut) public {
        (id, wallet, cut) = _enroll(id, wallet, cut);
        vm.assume(wallet != address(this));

        lender.creditCourier(id, address(this));
        assertEq(lender.courierOf(address(this)), id);
    }

    function test_canCreditCourierWithPermission(uint32 id, address wallet, uint16 cut, address account) public {
        (id, wallet, cut) = _enroll(id, wallet, cut);
        vm.assume(wallet != account);

        vm.prank(account);
        lender.approve(address(this), 1);

        lender.creditCourier(id, account);
        assertEq(lender.courierOf(account), id);
    }

    function test_cannotCreditSelf(uint32 id, address wallet, uint16 cut) public {
        (id, wallet, cut) = _enroll(id, wallet, cut);

        vm.prank(wallet);
        vm.expectRevert(bytes(""));
        lender.creditCourier(id, wallet);
    }

    function test_cannotCreditCourierWithoutPermission(uint32 id, address wallet, uint16 cut, address account) public {
        (id, wallet, cut) = _enroll(id, wallet, cut);
        vm.assume(account != address(this));

        vm.expectRevert(bytes(""));
        lender.creditCourier(id, account);
    }

    function test_cannotCreditCourierBeforeEnrollment(uint32 id, address account) public {
        vm.prank(account);
        lender.approve(address(this), 1);

        vm.expectRevert(bytes(""));
        lender.creditCourier(id, account);
    }

    function test_cannotCreditCourierAfterAcquiringTokens(
        uint32 id,
        address wallet,
        uint16 cut,
        address account
    ) public {
        (id, wallet, cut) = _enroll(id, wallet, cut);

        vm.prank(account);
        lender.approve(address(this), 1);

        deal(address(lender), account, 1);

        vm.expectRevert(bytes(""));
        lender.creditCourier(id, account);
    }

    function test_depositDoesIncreasePrinciple(
        uint32 id,
        address wallet,
        uint16 cut,
        address caller,
        address to,
        uint112 amount
    ) public {
        vm.assume(amount > 1);
        (id, wallet, cut) = _enroll(id, wallet, cut);

        vm.prank(to);
        if (to == wallet) {
            vm.expectRevert(bytes(""));
            lender.creditCourier(id, to);
            return;
        }
        lender.creditCourier(id, to);

        deal(address(asset), address(lender), amount);
        vm.prank(caller);
        lender.deposit(amount / 2, to);

        assertEq(lender.courierOf(to), id);
        assertEq(lender.principleOf(to), amount / 2);
        assertEq(lender.balanceOf(to), amount / 2);
        assertEq(lender.underlyingBalance(to), amount / 2);

        uint256 val = uint256(vm.load(address(lender), bytes32(uint256(1))));
        val += ((amount / 4) * uint256(type(uint72).max));
        val += (1e12) << 184;
        vm.store(address(lender), bytes32(uint256(1)), bytes32(val));

        assertEq(lender.courierOf(to), id);
        assertEq(lender.principleOf(to), amount / 2);
        assertEq(lender.balanceOf(to), amount / 2);
        assertApproxEqAbs(
            lender.convertToAssets(lender.balanceOf(to)),
            amount,
            2
        );

        vm.prank(caller);
        lender.deposit(amount / 2, to);

        assertEq(lender.courierOf(to), id);
        assertEq(lender.principleOf(to), amount / 2 + amount / 2);
        assertApproxEqAbs(lender.balanceOf(to), amount / 2 + amount / 4, 1);
        assertApproxEqAbs(
            lender.convertToAssets(lender.balanceOf(to)),
            uint256(amount) + amount / 2,
            2
        );
    }

    function test_withdrawDoesPayout(
        uint32 id,
        address wallet,
        uint16 cut,
        address caller,
        address to,
        uint104 amount
    ) public {
        // MARK: Start by doing everything that `test_depositDoesIncreasePrinciple` does

        vm.assume(amount > 1);
        (id, wallet, cut) = _enroll(id, wallet, cut);
        if (to == wallet || to == address(lender)) return;

        vm.prank(to);
        if (to == wallet) {
            vm.expectRevert(bytes(""));
            lender.creditCourier(id, to);
            return;
        }
        lender.creditCourier(id, to);

        deal(address(asset), address(lender), amount);
        vm.prank(caller);
        lender.deposit(amount / 2, to);

        uint256 val = uint256(vm.load(address(lender), bytes32(uint256(1))));
        val += ((amount / 4) * uint256(type(uint72).max));
        val += uint256(1e12) << 184;
        vm.store(address(lender), bytes32(uint256(1)), bytes32(val));

        vm.prank(caller);
        lender.deposit(amount / 2, to);

        // MARK: Now do withdrawal stuff

        uint256 bal = lender.balanceOf(to);
        uint256 profit = lender.convertToAssets(bal) - lender.principleOf(to);

        // pretend that borrower pays off a big loan so that lender can make full payout
        deal(address(asset), address(lender), type(uint128).max);
        val = uint256(vm.load(address(lender), bytes32(uint256(1))));
        val -= ((amount / 4) * uint256(type(uint72).max));
        vm.store(address(lender), bytes32(uint256(1)), bytes32(val));
        val = uint256(vm.load(address(lender), bytes32(uint256(0))));
        val += uint256(amount / 2) << 112;
        vm.store(address(lender), bytes32(uint256(0)), bytes32(val));

        uint256 reward = (profit * uint256(cut)) / 10_000;
        uint256 rewardShares = lender.convertToShares(reward);

        uint256 maxRedeem = lender.maxRedeem(to);
        assertLe(maxRedeem, bal - rewardShares);
        if (bal - rewardShares >= 1) {
            assertGe(maxRedeem, bal - rewardShares - 1);
        }

        vm.prank(to);
        lender.redeem(maxRedeem, to, to);

        assertApproxEqAbs(lender.balanceOf(wallet), rewardShares, 1);
        assertApproxEqAbs(lender.underlyingBalance(wallet), reward, 1);
    }

    // TODO test chaining

    // TODO test withdrawing in 25% chunks

    // TODO test that nominalShares = balanceOf before any interest has accrued

    // TODO expect revert if shares > post-fee balance, even if shares < pre-fee balance

    function _enroll(uint32 id, address wallet, uint16 cut) private returns (uint32, address, uint16) {
        cut = cut % 10_000;

        vm.assume(id != 0);
        vm.assume(cut != 0);

        lender.enrollCourier(id, wallet, cut);

        return (id, wallet, cut);
    }
}
