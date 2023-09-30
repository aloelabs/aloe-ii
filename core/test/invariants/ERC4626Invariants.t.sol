// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";

import {ClonesWithImmutableArgs} from "clones-with-immutable-args/ClonesWithImmutableArgs.sol";
import {ERC4626, ERC20} from "solmate/mixins/ERC4626.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import "src/Lender.sol";
import "src/RateModel.sol";

import {ERC4626Harness} from "./ERC4626Harness.sol";

contract ERC4626InvariantsTest is Test {
    ERC20 public asset;

    ERC4626 public vault;

    ERC4626Harness public vaultHarness;

    struct ThingsThatShouldntChange {
        string symbol;
        uint8 decimals;
        ERC20 asset;
        bytes32 domainSeparator;
    }

    ThingsThatShouldntChange public thingsThatShouldntChange;

    function setUp() public {
        {
            asset = new MockERC20("Token", "TKN", 18); // TODO: replace 18 with an env var
            address lenderImplementation = address(new Lender(address(2)));
            Lender lender = Lender(ClonesWithImmutableArgs.clone(
                lenderImplementation,
                abi.encodePacked(address(asset))
            ));
            RateModel rateModel = new RateModel();
            lender.initialize();
            lender.setRateModelAndReserveFactor(rateModel, 8); // TODO: replace 8 with an env var

            vault = ERC4626(address(lender));
            vaultHarness = new ERC4626Harness(lender);

            targetContract(address(vaultHarness));

            // forge can't simulate transactions from addresses with code, so we must exclude all contracts
            excludeSender(address(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D)); // vm
            excludeSender(address(0x4e59b44847b379578588920cA78FbF26c0B4956C)); // built-in create2 deployer
            excludeSender(address(this));
            excludeSender(address(asset));
            excludeSender(address(lenderImplementation));
            excludeSender(address(rateModel));
            excludeSender(address(vault));
            excludeSender(address(vaultHarness));
        }

        thingsThatShouldntChange = ThingsThatShouldntChange(
            vault.symbol(),
            vault.decimals(),
            vault.asset(),
            vault.DOMAIN_SEPARATOR()
        );
    }

    function invariant_thingsThatShouldntChangeDontChange() public {
        ThingsThatShouldntChange memory update = ThingsThatShouldntChange(
            vault.symbol(),
            vault.decimals(),
            vault.asset(),
            vault.DOMAIN_SEPARATOR()
        );

        assertEq(bytes(update.symbol), bytes(thingsThatShouldntChange.symbol));
        assertEq(update.decimals, thingsThatShouldntChange.decimals);
        assertEq(address(update.asset), address(thingsThatShouldntChange.asset));
        assertEq(update.domainSeparator, thingsThatShouldntChange.domainSeparator);
    }

    function invariant_conversionsAreInverses() public {
        // Choice of `x` is random/convenient
        uint256 x = vault.totalSupply();

        // This would need to be true for all `x` in order to fully prove they're inverses
        assertEq(vault.convertToAssets(vault.convertToShares(x)), x);
        assertEq(vault.convertToShares(vault.convertToAssets(x)), x);
    }

    function invariant_totalSupplyEqualsSumOfBalances() public {
        uint256 totalSupply;
        uint256 count = vaultHarness.getHolderCount();
        for (uint256 i = 0; i < count; i++) {
            totalSupply += vault.balanceOf(vaultHarness.holders(i));
        }
        assertEq(totalSupply, vault.totalSupply());
    }

    function invariant_maxRedeemLessThanBalance() public {
        uint256 count = vaultHarness.getHolderCount();
        for (uint256 i = 0; i < count; i++) {
            address user = vaultHarness.holders(i);

            assertLe(vault.maxRedeem(user), vault.balanceOf(user));
        }
    }
}
