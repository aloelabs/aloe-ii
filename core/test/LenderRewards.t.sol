// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import "src/Lender.sol";
import "src/RateModel.sol";

import {FactoryForLenderTests} from "./Utils.sol";

contract LenderRewardsTest is Test {
    uint256 private constant REWARDS_RATE_MIN = uint256(1e19) / (365 days);
    uint256 private constant REWARDS_RATE_MAX = uint256(1e24) / (365 days);

    event RewardsRateSet(uint56 rate);

    event RewardsClaimed(address indexed user, uint112 amount);

    MockERC20 rewardsToken;

    MockERC20 asset;

    FactoryForLenderTests factory;

    Lender lender;

    function setUp() public {
        rewardsToken = new MockERC20("Rewards Token", "RWD", 18);
        asset = new MockERC20("Test Token", "TKN", 18);

        factory = new FactoryForLenderTests(new RateModel(), rewardsToken);
        lender = factory.deploySingleLender(asset);
    }

    function test_setRate(uint56 rate, address caller) public {
        vm.assume(caller != factory.GOVERNOR());

        // Starts at 0
        assertEq(lender.rewardsRate(), 0);

        // Only governance can change it
        vm.prank(caller);
        vm.expectRevert(bytes(""));
        factory.governRewardsRate(lender, rate);

        // Set it to `rate`
        vm.prank(factory.GOVERNOR());
        vm.expectEmit(true, false, false, false, address(lender));
        emit RewardsRateSet(rate);
        factory.governRewardsRate(lender, rate);
        assertEq(lender.rewardsRate(), rate);
    }

    function test_nothingToClaimAtFirst(address owner, address caller) public {
        vm.assume(caller != address(factory));

        assertEq(lender.rewardsOf(owner), 0);

        // Only factory can claim
        vm.prank(caller);
        vm.expectRevert(bytes(""));
        lender.claimRewards(owner);

        vm.prank(address(factory));
        vm.expectEmit(true, false, false, true, address(lender));
        emit RewardsClaimed(owner, 0);
        uint256 earned = lender.claimRewards(owner);
        assertEq(earned, 0);
    }

    function test_accounting1Holder(address holder, uint56 rate0, uint56 rate1) public {
        if (rate0 > 0) rate0 = uint56(bound(rate0, REWARDS_RATE_MIN, REWARDS_RATE_MAX));
        if (rate1 > 0) rate1 = uint56(bound(rate1, REWARDS_RATE_MIN, REWARDS_RATE_MAX));

        // Set `rate0`
        vm.prank(factory.GOVERNOR());
        factory.governRewardsRate(lender, rate0);

        // Rewards should begin accruing after deposit
        asset.mint(address(lender), 1e18);
        lender.deposit(1e18, holder);

        skip(1 days);
        assertApproxEqRel(lender.rewardsOf(holder), uint256(rate0) * (1 days), 0.001e18);

        // Set `rate1`
        vm.prank(factory.GOVERNOR());
        factory.governRewardsRate(lender, rate1);

        skip(1 days);
        assertApproxEqRel(lender.rewardsOf(holder), (uint256(rate0) + rate1) * (1 days), 0.001e18);

        // Rewards should stop accruing after redeem
        vm.prank(holder);
        lender.redeem(type(uint256).max, holder, holder);

        skip(1 days);
        assertApproxEqRel(lender.rewardsOf(holder), (uint256(rate0) + rate1) * (1 days), 0.001e18);

        // Check proper claim
        uint112 earned = lender.rewardsOf(holder);
        vm.prank(address(factory));
        vm.expectEmit(true, false, false, true, address(lender));
        emit RewardsClaimed(holder, earned);
        assertEq(lender.claimRewards(holder), earned);
        // Check no duplicate claim
        assertEq(lender.rewardsOf(holder), 0);
        vm.prank(address(factory));
        assertEq(lender.claimRewards(holder), 0);
    }

    function test_accounting2Holders(address holder0, address holder1, uint56 rate) public {
        vm.assume(holder0 != holder1);
        if (rate > 0) rate = uint56(bound(rate, REWARDS_RATE_MIN, REWARDS_RATE_MAX));

        // Set `rate`
        vm.prank(factory.GOVERNOR());
        factory.governRewardsRate(lender, rate);

        // Rewards should begin accruing to holder0 after deposit
        asset.mint(address(lender), 1e18);
        lender.deposit(1e18, holder0);

        skip(1 days);
        assertApproxEqRel(lender.rewardsOf(holder0), uint256(rate) * (1 days), 0.001e18);
        assertEq(lender.rewardsOf(holder1), 0);

        // Send half the tokens to holder1
        vm.prank(holder0);
        lender.transfer(holder1, 0.5e18);

        skip(1 days);
        assertApproxEqRel(lender.rewardsOf(holder0), (uint256(rate) + rate / 2) * (1 days), 0.001e18);
        assertApproxEqRel(lender.rewardsOf(holder1), uint256(rate / 2) * (1 days), 0.001e18);

        // Rewards should stop accruing to holder0 after redeem
        vm.prank(holder0);
        lender.redeem(type(uint256).max, holder0, holder0);

        skip(1 days);
        assertApproxEqRel(lender.rewardsOf(holder0), (uint256(rate) + rate / 2) * (1 days), 0.001e18);
        assertApproxEqRel(lender.rewardsOf(holder1), (uint256(rate) + rate / 2) * (1 days), 0.001e18);

        // Check proper claim for holder0
        uint112 earned = lender.rewardsOf(holder0);
        vm.prank(address(factory));
        vm.expectEmit(true, false, false, true, address(lender));
        emit RewardsClaimed(holder0, earned);
        assertEq(lender.claimRewards(holder0), earned);

        // Check proper claim for holder1
        earned = lender.rewardsOf(holder1);
        vm.prank(address(factory));
        vm.expectEmit(true, false, false, true, address(lender));
        emit RewardsClaimed(holder1, earned);
        assertEq(lender.claimRewards(holder1), earned);
    }

    function test_selfTransfer(address holder, uint56 rate) public {
        if (rate > 0) rate = uint56(bound(rate, REWARDS_RATE_MIN, REWARDS_RATE_MAX));

        // Set `rate`
        vm.prank(factory.GOVERNOR());
        factory.governRewardsRate(lender, rate);

        // Rewards should begin accruing to holder after deposit
        asset.mint(address(lender), 1e18);
        lender.deposit(1e18, holder);

        skip(1 days);
        assertApproxEqRel(lender.rewardsOf(holder), uint256(rate) * (1 days), 0.001e18);

        // Send half the tokens to holder
        vm.prank(holder);
        lender.transfer(holder, 0.5e18);

        skip(1 days);
        assertApproxEqRel(lender.rewardsOf(holder), uint256(rate) * (2 days), 0.001e18);

        // Rewards should stop accruing to holder after redeem
        vm.prank(holder);
        lender.redeem(type(uint256).max, holder, holder);

        skip(1 days);
        assertApproxEqRel(lender.rewardsOf(holder), uint256(rate) * (2 days), 0.001e18);

        // Check proper claim for holder
        uint112 earned = lender.rewardsOf(holder);
        vm.prank(address(factory));
        vm.expectEmit(true, false, false, true, address(lender));
        emit RewardsClaimed(holder, earned);
        assertEq(lender.claimRewards(holder), earned);
    }

    function test_accountingBehavesAtExtremes(address holder0, address holder1, uint56 rate) public {
        vm.assume(holder0 != holder1);

        // Set `rate`
        vm.prank(factory.GOVERNOR());
        factory.governRewardsRate(lender, rate);

        // Max absolute error is 2, so we do this for assertLe's to pass
        if (rate < type(uint56).max - 2) rate += 2;

        // Rewards should begin accruing to holder0 after deposit
        asset.mint(address(lender), 1000000e18);
        lender.deposit(1000000e18, holder0);

        console2.log(lender.balanceOf(holder0), lender.balanceOf(holder1), lender.totalSupply());

        skip(365 days);
        assertLe(lender.rewardsOf(holder0), uint256(rate) * (365 days), "excessive A0");
        assertEq(lender.rewardsOf(holder1), 0);

        // Send half the tokens to holder1
        vm.prank(holder0);
        lender.transfer(holder1, 500000e18);

        console2.log(lender.balanceOf(holder0), lender.balanceOf(holder1), lender.totalSupply());

        skip(365 days);
        assertLe(lender.rewardsOf(holder0), uint256(rate) * (547.5 days), "excessive B0");
        assertLe(lender.rewardsOf(holder1), uint256(rate) * (182.5 days), "excessive B1");

        // Rewards should stop accruing to holder0 after redeem
        vm.prank(holder0);
        lender.redeem(type(uint256).max, holder0, holder0);

        skip(365 days);
        assertLe(lender.rewardsOf(holder0), uint256(rate) * (547.5 days), "excessive C0");
        assertLe(lender.rewardsOf(holder1), uint256(rate) * (547.5 days), "excessive C1");

        // Check proper claim for holder0
        uint112 earned = lender.rewardsOf(holder0);
        vm.prank(address(factory));
        vm.expectEmit(true, false, false, true, address(lender));
        emit RewardsClaimed(holder0, earned);
        assertEq(lender.claimRewards(holder0), earned);

        // Check proper claim for holder1
        earned = lender.rewardsOf(holder1);
        vm.prank(address(factory));
        vm.expectEmit(true, false, false, true, address(lender));
        emit RewardsClaimed(holder1, earned);
        assertEq(lender.claimRewards(holder1), earned);
    }
}
