// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";

import {ClonesWithImmutableArgs} from "clones-with-immutable-args/ClonesWithImmutableArgs.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import "src/Lender.sol";
import "src/RateModel.sol";

import {FactoryForLenderTests} from "../Utils.sol";
import {LenderHarness, BORROWS_SCALER} from "./LenderHarness.sol";

contract LenderInvariantsTest is Test {
    ERC20 public asset;

    Lender public lender;

    LenderHarness public lenderHarness;

    struct ThingsThatShouldntChange {
        IRateModel rateModel;
        uint8 reserveFactor;
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
            RateModel rateModel = new RateModel();
            FactoryForLenderTests factory = new FactoryForLenderTests(rateModel, ERC20(address(0)));

            asset = new MockERC20("Token", "TKN", 18);
            lender = factory.deploySingleLender(asset);
            lenderHarness = new LenderHarness(lender);

            targetContract(address(lenderHarness));

            // forge can't simulate transactions from addresses with code, so we must exclude all contracts
            excludeSender(address(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D)); // vm
            excludeSender(address(0x4e59b44847b379578588920cA78FbF26c0B4956C)); // built-in create2 deployer
            excludeSender(address(this));
            excludeSender(address(rateModel));
            excludeSender(address(factory));
            excludeSender(address(factory.LENDER_IMPLEMENTATION()));
            excludeSender(address(asset));
            excludeSender(address(lender));
            excludeSender(address(lenderHarness));
        }

        thingsThatShouldntChange = ThingsThatShouldntChange(
            lender.rateModel(),
            lender.reserveFactor(),
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
        (, uint256 totalAssets, , uint256 totalSupply) = lender.stats();
        // NOTE: `totalSupply` from `stats()` assumes interest accrual --> shares minted to reserves --> so it's
        // always >= the current value
        assertGe(totalSupply, lender.totalSupply());
        assertEq(totalAssets, lender.totalAssets());
    }

    function invariant_thingsThatShouldntChangeDontChange() public {
        ThingsThatShouldntChange memory update = ThingsThatShouldntChange(
            lender.rateModel(),
            lender.reserveFactor(),
            lender.symbol(),
            lender.decimals(),
            lender.asset(),
            lender.DOMAIN_SEPARATOR()
        );

        assertEq(uint160(address(update.rateModel)), uint160(address(thingsThatShouldntChange.rateModel)));
        assertEq(update.reserveFactor, thingsThatShouldntChange.reserveFactor);
        assertEq(bytes(update.symbol), bytes(thingsThatShouldntChange.symbol));
        assertEq(update.decimals, thingsThatShouldntChange.decimals);
        assertEq(address(update.asset), address(thingsThatShouldntChange.asset));
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
        (, uint256 totalAssets, , uint256 totalSupply) = lender.stats();
        assertLe(totalSupply, totalAssets);
    }

    function invariant_convertToXXXXXXIsAccurate() public {
        (, uint256 totalAssets, , uint256 totalSupply) = lender.stats();
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
        // Σ(lender.underlyingBalance) = totalAssets - valueOfCourierFees - valueOfNewReserves
        uint256 sumUnderlyingBalances;
        // Σ(lender.underlyingBalanceStored) = totalAssets - valueOfCourierFees - newInterest
        uint256 sumUnderlyingBalancesStored;
        // Σ(lender.convertToAssets(lender.balanceOf) = totalAssets - valueOfNewReserves
        uint256 sumConvertedBalances;

        uint256 count = lenderHarness.getHolderCount();
        for (uint256 i = 0; i < count; i++) {
            address holder = lenderHarness.holders(i);

            sumUnderlyingBalances += lender.underlyingBalance(holder);
            sumUnderlyingBalancesStored += lender.underlyingBalanceStored(holder);
            sumConvertedBalances += lender.convertToAssets(lender.balanceOf(holder));
        }

        assertLe(sumUnderlyingBalancesStored, sumUnderlyingBalances);
        assertLe(sumUnderlyingBalances, sumConvertedBalances);

        (, , , uint256 newTotalSupply) = lender.stats();
        uint256 valueOfNewReserves = lender.convertToAssets(newTotalSupply - lender.totalSupply());
        assertApproxEqAbs(
            sumConvertedBalances + valueOfNewReserves,
            lender.totalAssets(),
            1 * count // max error of 1 per user
        );
    }

    function invariant_maxWithdrawLessThanUnderlyingBalance() public {
        uint256 count = lenderHarness.getHolderCount();
        for (uint256 i = 0; i < count; i++) {
            address user = lenderHarness.holders(i);

            assertLe(lender.maxWithdraw(user), lender.underlyingBalance(user));
        }
    }

    function invariant_maxRedeemLessThanBalance() public {
        uint256 count = lenderHarness.getHolderCount();
        for (uint256 i = 0; i < count; i++) {
            address user = lenderHarness.holders(i);

            assertLe(lender.maxRedeem(user), lender.balanceOf(user));
        }
    }

    function invariant_principleLessThanUnderlyingBalance() public {
        uint256 count = lenderHarness.getHolderCount();
        for (uint256 i = 0; i < count; i++) {
            address user = lenderHarness.holders(i);

            // NOTE: As price per share increases (i.e., each share converts to more and more underlying assets),
            // this assertion may become flakey due to rounding. Allowing for rounding error of 3 seems sufficient
            // in our testing. Just make sure the contract itself never assumes principle < underlyingBalance
            assertLe(lender.principleOf(user), lender.underlyingBalance(user) + 3);
        }
    }

    function invariant_underlyingBalanceLessThanConvertedShares() public {
        uint256 count = lenderHarness.getHolderCount();
        for (uint256 i = 0; i < count; i++) {
            address user = lenderHarness.holders(i);

            if (lender.courierOf(user) == 0) {
                assertEq(lender.underlyingBalance(user), lender.convertToAssets(lender.balanceOf(user)));
            } else {
                assertLe(lender.underlyingBalance(user), lender.convertToAssets(lender.balanceOf(user)));
            }
        }
    }

    function invariant_totalBorrowsEqualsSumOfBorrowBalances() public {
        uint256 totalBorrows;
        uint256 count = lenderHarness.getBorrowerCount();
        for (uint256 i = 0; i < count; i++) {
            totalBorrows += lender.borrowBalance(lenderHarness.borrowers(i));
        }

        (, , uint256 expected, ) = lender.stats();
        assertApproxEqAbs(
            totalBorrows,
            expected,
            1 * count // max error of 1 per user
        );
    }

    function invariant_borrowBalanceIsNonZeroIfUnitsExist() public {
        uint256 count = lenderHarness.getBorrowerCount();
        for (uint256 i = 0; i < count; i++) {
            address borrower = lenderHarness.borrowers(i);

            if (lender.borrows(borrower) > 1) assertGt(lender.borrowBalanceStored(borrower), 0);
            else assertEq(lender.borrowBalanceStored(borrower), 0);
        }
    }
}
