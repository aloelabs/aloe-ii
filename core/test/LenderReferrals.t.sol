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
        lender = deploySingleLender(asset, address(2), new InterestModel());
    }

    function test_canEnrollCourier(uint32 id, address wallet, uint16 cut) public {
        (id, wallet, cut) = _enroll(id, wallet, cut);

        (address a, uint16 b) = lender.couriers(id);
        assertEq(a, wallet);
        assertEq(b, cut);
    }

    function test_cannotSetCutAbove10000(uint32 id, address wallet, uint16 cut) public {
        if (id == 0) id = 1;
        if (wallet == address(0)) wallet = address(1);
        if (cut < 10_000) cut += 10_000;

        vm.expectRevert(bytes(""));
        lender.enrollCourier(id, wallet, cut);
    }

    function test_cannotEnrollId0(address wallet, uint16 cut) public {
        if (wallet == address(0)) wallet = address(1);
        if (cut == 0) cut = 1;

        vm.expectRevert(bytes(""));
        lender.enrollCourier(0, wallet, cut);
    }

    function test_cannotEditCourierCut(uint32 id, address wallet, uint16 cutA, uint16 cutB) public {
        cutA = cutA % 10_000;
        cutB = cutB % 10_000;
        if (id == 0) id = 1;
        if (wallet == address(0)) wallet = address(1);
        if (cutA == 0) cutA = 1;
        if (cutB == 0) cutB = 1;

        lender.enrollCourier(id, wallet, cutA);

        vm.expectRevert(bytes(""));
        lender.enrollCourier(id, wallet, cutB);
    }

    function test_cannotEditCourierWallet(uint32 id, address walletA, address walletB, uint16 cut) public {
        cut = cut % 10_000;
        if (id == 0) id = 1;
        if (walletA == address(0)) walletA = address(1);
        if (walletB == address(0)) walletB = address(1);
        if (cut == 0) cut = 1;

        lender.enrollCourier(id, walletA, cut);

        vm.expectRevert(bytes(""));
        lender.enrollCourier(id, walletB, cut);
    }

    function test_canCreditCourier(uint32 id, address wallet, uint16 cut) public {
        (id, wallet, cut) = _enroll(id, wallet, cut);
        if (wallet == address(this)) return;

        lender.creditCourier(id, address(this));
        assertEq(lender.courierOf(address(this)), id);
    }

    function test_canCreditCourierWithPermission(uint32 id, address wallet, uint16 cut, address account) public {
        (id, wallet, cut) = _enroll(id, wallet, cut);
        if (wallet == account) return;

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

        if (account == address(this)) return;

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
        if (amount <= 1) return;
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
        assertEq(lender.balanceOfUnderlying(to), amount / 2);

        uint256 val = uint256(vm.load(address(lender), bytes32(uint256(1))));
        val += ((amount / 4) * uint256(type(uint72).max));
        val += (1e12) << 184;
        vm.store(address(lender), bytes32(uint256(1)), bytes32(val));

        assertEq(lender.courierOf(to), id);
        assertEq(lender.principleOf(to), amount / 2);
        assertEq(lender.balanceOf(to), amount / 2);
        assertLe(stdMath.delta(lender.balanceOfUnderlying(to), amount), 2);

        vm.prank(caller);
        lender.deposit(amount / 2, to);

        assertEq(lender.courierOf(to), id);
        assertEq(lender.principleOf(to), amount / 2 + amount / 2);
        assertLe(stdMath.delta(lender.balanceOf(to), amount / 2 + amount / 4), 1);
        assertLe(stdMath.delta(lender.balanceOfUnderlying(to), uint256(amount) + amount / 2), 2);
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

        if (amount <= 1) return;
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
        if (lender.balanceOfUnderlying(to) == 0) return;

        uint256 bal = lender.balanceOf(to);
        uint256 profit = lender.balanceOfUnderlying(to) - lender.principleOf(to);

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

        vm.prank(to);
        lender.redeem(bal, to, to);

        assertLe(stdMath.delta(lender.balanceOf(wallet), rewardShares), 1);

        assertLe(stdMath.delta(lender.balanceOfUnderlying(wallet), reward), 2);
    }

    function _enroll(uint32 id, address wallet, uint16 cut) private returns (uint32, address, uint16) {
        cut = cut % 10_000;

        if (id == 0) id = 1;
        if (wallet == address(0)) wallet = address(1);
        if (cut == 0) cut = 1;

        lender.enrollCourier(id, wallet, cut);

        return (id, wallet, cut);
    }
}
