// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

import {InvariantTest} from "forge-std/InvariantTest.sol";
import "forge-std/Test.sol";
import "forge-std/Vm.sol";

import {ClonesWithImmutableArgs} from "clones-with-immutable-args/ClonesWithImmutableArgs.sol";
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
        else return repay(amount, borrowers[i % borrowers.length]);
    }

    // TODO: repayMax
}

// NOTE: We assume that lender.RESERVE() does not have a courier
contract LenderInvariantsTest is Test, InvariantTest {
    ERC20 public asset;

    Lender public lender;

    LenderHarness public lenderHarness;

    struct ThingsThatShouldntChange {
        RateModel rateModel;
        uint8 reserveFactor;
        string name;
        string symbol;
        uint8 decimals;
        ERC20 asset;
        bytes32 domainSeparator;
    }

    struct ThingsThatShouldntShrink {
        uint256 lastAccrualTime;
        uint256 borrowIndex;
    }

    ThingsThatShouldntChange public thingsThatShouldntChange;

    ThingsThatShouldntShrink public thingsThatShouldntShrink;

    function setUp() public {
        {
            asset = new MockERC20("Token", "TKN", 18);
            address lenderImplementation = address(new Lender(address(2)));
            lender = Lender(ClonesWithImmutableArgs.clone(
                lenderImplementation,
                abi.encodePacked(address(asset))
            ));
            RateModel rateModel = new RateModel();
            lender.initialize(rateModel, 8);
            Router router = new Router();
            lenderHarness = new LenderHarness(lender, router);

            targetContract(address(lenderHarness));

            // forge can't simulate transactions from addresses with code, so we must exclude all contracts
            excludeSender(address(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D)); // vm
            excludeSender(address(0x4e59b44847b379578588920cA78FbF26c0B4956C)); // built-in create2 deployer
            excludeSender(address(this));
            excludeSender(address(asset));
            excludeSender(address(lenderImplementation));
            excludeSender(address(lender));
            excludeSender(address(rateModel));
            excludeSender(address(router));
            excludeSender(address(lenderHarness));
        }

        thingsThatShouldntChange = ThingsThatShouldntChange(
            lender.rateModel(),
            lender.reserveFactor(),
            lender.name(),
            lender.symbol(),
            lender.decimals(),
            lender.asset(),
            lender.DOMAIN_SEPARATOR()
        );

        thingsThatShouldntShrink = ThingsThatShouldntShrink(
            lender.lastAccrualTime(),
            lender.borrowIndex()
        );
    }

    function invariant_statsValuesMatchOtherGetters() public {
        (uint256 totalSupply, uint256 totalAssets, ) = lender.stats();
        // NOTE: `totalSupply` from `stats()` assumes interest accrual --> shares minted to reserves --> so it's
        // always >= the current value
        assertGe(totalSupply, lender.totalSupply());
        assertEq(totalAssets, lender.totalAssets());
    }

    function invariant_thingsThatShouldntChangeDontChange() public {
        ThingsThatShouldntChange memory update = ThingsThatShouldntChange(
            lender.rateModel(),
            lender.reserveFactor(),
            lender.name(),
            lender.symbol(),
            lender.decimals(),
            lender.asset(),
            lender.DOMAIN_SEPARATOR()
        );

        assertEq(uint160(address(update.rateModel)), uint160(address(thingsThatShouldntChange.rateModel)));
        assertEq(update.reserveFactor, thingsThatShouldntChange.reserveFactor);
        assertEq(bytes(update.name), bytes(thingsThatShouldntChange.name));
        assertEq(bytes(update.symbol), bytes(thingsThatShouldntChange.symbol));
        assertEq(update.decimals, thingsThatShouldntChange.decimals);
        assertEq(uint160(address(update.asset)), uint160(address(thingsThatShouldntChange.asset)));
        assertEq(update.domainSeparator, thingsThatShouldntChange.domainSeparator);
    }

    function invariant_thingsThatShouldntShrinkDontShrink() public {
        ThingsThatShouldntShrink memory update = ThingsThatShouldntShrink(
            lender.lastAccrualTime(),
            lender.borrowIndex()
        );

        assertGe(update.lastAccrualTime, thingsThatShouldntShrink.lastAccrualTime);
        assertGe(update.borrowIndex, thingsThatShouldntShrink.borrowIndex);

        thingsThatShouldntShrink = update;
    }

    function invariant_hasLastBalance() public {
        assertGe(asset.balanceOf(address(lender)), lender.lastBalance());
    }

    function invariant_lastBalanceLessThanTotalAssets() public {
        assertLe(lender.lastBalance(), lender.totalAssets());
    }

    function invariant_totalSupplyLessThanTotalAssets() public {
        (uint256 totalSupply, uint256 totalAssets, ) = lender.stats();
        assertLe(totalSupply, totalAssets);
    }

    function invariant_convertToXXXXXXIsAccurate() public {
        (uint256 totalSupply, uint256 totalAssets, ) = lender.stats();
        assertApproxEqAbs(lender.convertToAssets(totalSupply), totalAssets, 1);
        assertApproxEqAbs(lender.convertToShares(totalAssets), totalSupply, 1);
    }

    function invariant_totalSupplyEqualsSumOfBalances() public {
        uint256 totalSupply;
        uint256 count = lenderHarness.getHolderCount();
        for (uint256 i = 0; i < count; i++) {
            totalSupply += lender.balanceOf(lenderHarness.holders(i));
        }
        assertEq(totalSupply, lender.totalSupply());
    }

    function invariant_totalAssetsEqualsSumOfUnderlyingBalances() public {
        uint256 totalAssetsExcludingNewReserves;
        uint256 totalAssetsStored;
        uint256 count = lenderHarness.getHolderCount();
        for (uint256 i = 0; i < count; i++) {
            totalAssetsExcludingNewReserves += lender.underlyingBalance(lenderHarness.holders(i));
            totalAssetsStored += lender.underlyingBalanceStored(lenderHarness.holders(i));
        }

        (, uint256 totalAssetsIncludingNewReserves, ) = lender.stats();
        // NOTE: Σ(underlyingBalances) <= expected because `underlyingBalance` increases the denominator *as if*
        // shares have been minted to reserves, but doesn't actually increase reserves' balance.
        assertLe(totalAssetsExcludingNewReserves, totalAssetsIncludingNewReserves);

        uint256 totalBorrowsStored;
        unchecked {
            totalBorrowsStored = (uint256(lender.borrowBase()) * lender.borrowIndex()) / BORROWS_SCALER;
        }
        assertApproxEqAbs(
            totalAssetsStored,
            lender.lastBalance() + totalBorrowsStored,
            1 * count // max error of 1 per user
        );
    }

    function invariant_totalBorrowsEqualsSumOfBorrowBalances() public {
        uint256 totalBorrows;
        uint256 count = lenderHarness.getBorrowerCount();
        for (uint256 i = 0; i < count; i++) {
            totalBorrows += lender.borrowBalance(lenderHarness.borrowers(i));
        }

        (, , uint256 expected) = lender.stats();
        assertApproxEqAbs(
            totalBorrows,
            expected,
            1 * count // max error of 1 per user
        );
    }
}
