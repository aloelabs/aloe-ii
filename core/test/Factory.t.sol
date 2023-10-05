// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {
    DEFAULT_ANTE,
    DEFAULT_N_SIGMA,
    DEFAULT_MANIPULATION_THRESHOLD_DIVISOR,
    DEFAULT_RESERVE_FACTOR,
    CONSTRAINT_N_SIGMA_MIN,
    CONSTRAINT_N_SIGMA_MAX,
    CONSTRAINT_MANIPULATION_THRESHOLD_DIVISOR_MIN,
    CONSTRAINT_MANIPULATION_THRESHOLD_DIVISOR_MAX,
    CONSTRAINT_RESERVE_FACTOR_MIN,
    CONSTRAINT_RESERVE_FACTOR_MAX,
    CONSTRAINT_ANTE_MAX,
    UNISWAP_AVG_WINDOW
} from "src/libraries/constants/Constants.sol";

import {Borrower} from "src/Borrower.sol";
import {Factory, IUniswapV3Pool, ERC20} from "src/Factory.sol";
import {Lender} from "src/Lender.sol";
import {RateModel} from "src/RateModel.sol";
import {VolatilityOracle} from "src/VolatilityOracle.sol";

import {FatFactory} from "./Utils.sol";

contract FactoryTest is Test {
    event CreateMarket(IUniswapV3Pool indexed pool, address lender0, address lender1);
    event CreateBorrower(IUniswapV3Pool indexed pool, address indexed owner, address account);
    event EnrollCourier(uint32 indexed id, address indexed wallet, uint16 cut);

    IUniswapV3Pool constant pool = IUniswapV3Pool(0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640);

    Factory factory;

    MockERC20 rewardsToken;
    
    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"), 15_348_451);

        factory = new FatFactory(address(12345), address(0), new VolatilityOracle(), new RateModel());
        rewardsToken = new MockERC20("Mock Token", "MOCK", 18);
    }

    function test_createMarket() external {
        vm.expectEmit(true, false, false, false, address(factory));
        emit CreateMarket(pool, address(0), address(0));
        factory.createMarket(pool);

        (Lender lender0, Lender lender1, ) = factory.getMarket(pool);
        assertEq(factory.peer(address(lender0)), address(lender1));
        assertEq(factory.peer(address(lender1)), address(lender0));
        assertEq(address(lender0.rateModel()), address(factory.DEFAULT_RATE_MODEL()));
        assertEq(address(lender1.rateModel()), address(factory.DEFAULT_RATE_MODEL()));
        assertEq(lender0.reserveFactor(), DEFAULT_RESERVE_FACTOR);
        assertEq(lender1.reserveFactor(), DEFAULT_RESERVE_FACTOR);

        vm.expectRevert(bytes(""));
        lender0.initialize();
        vm.expectRevert(bytes(""));
        lender1.initialize();

        // Can't recreate the same market
        vm.expectRevert();
        factory.createMarket(pool);
    }

    function test_createBorrower() external {
        factory.createMarket(pool);

        vm.expectEmit(true, true, false, false, address(factory));
        emit CreateBorrower(pool, address(6), address(0));
        Borrower borrower = factory.createBorrower(pool, address(6), bytes12(0));

        assertTrue(factory.isBorrower(address(borrower)));

        assertEq(borrower.owner(), address(6));

        (Lender lender0, Lender lender1, ) = factory.getMarket(pool);
        assertEq(lender0.borrows(address(borrower)), 1);
        assertEq(lender1.borrows(address(borrower)), 1);
    }

    function test_enrollCourier(uint32 id, uint16 cut) external {
        if (id == 0) {
            vm.expectRevert(bytes(""));
            factory.enrollCourier(id, cut);
            id = 1;
        }

        if (cut == 0 || cut >= 10_000) {
            vm.expectRevert(bytes(""));
            factory.enrollCourier(id, cut);
            cut = uint16(bound(cut, 1, 9999));
        }

        vm.expectEmit(true, true, false, true, address(factory));
        emit EnrollCourier(id, address(this), cut);
        factory.enrollCourier(id, cut);

        assertTrue(factory.isCourier(address(this)));
        (address courier, uint16 cutRec) = factory.couriers(id);
        assertEq(courier, address(this));
        assertEq(cutRec, cut);
    }

    function test_claimRewards() external {
        factory.createMarket(pool);
        (Lender lender0, Lender lender1, ) = factory.getMarket(pool);

        Lender[] memory lenders = new Lender[](2);
        lenders[0] = lender0;
        lenders[1] = lender1;

        // Couriers cannot claim rewards
        vm.prank(address(6789));
        factory.enrollCourier(1, 5000);
        vm.prank(address(6789));
        vm.expectRevert(bytes(""));
        factory.claimRewards(lenders, address(6789));

        // Set rewards token
        vm.prank(factory.GOVERNOR());
        factory.governRewardsToken(rewardsToken);

        // Expect factory to call Lenders in order to figure out rewards amount
        vm.mockCall(
            address(lender0),
            abi.encodeCall(Lender.claimRewards, (address(this))),
            abi.encode(uint256(3.1415e18))
        );
        vm.mockCall(
            address(lender1),
            abi.encodeCall(Lender.claimRewards, (address(this))),
            abi.encode(uint256(0.5e18))
        );

        // Can't pay out if factory doesn't have any tokens
        vm.expectRevert(bytes("TRANSFER_FAILED"));
        factory.claimRewards(lenders, address(this));

        // Happy path
        rewardsToken.mint(address(factory), 5e18);
        factory.claimRewards(lenders, address(this));
        assertEq(rewardsToken.balanceOf(address(this)), 3.6415e18);

        // Can't claim from non-Lenders
        lenders[1] = Lender(address(77777));
        vm.expectRevert();
        factory.claimRewards(lenders, address(this));
    }
}
