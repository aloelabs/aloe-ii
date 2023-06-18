// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import {DEFAULT_ANTE, DEFAULT_N_SIGMA} from "src/libraries/constants/Constants.sol";

import "src/Borrower.sol";
import "src/Factory.sol";
import "src/Lender.sol";

import {VolatilityOracleMock} from "./Utils.sol";

contract BorrowerTest is Test, IManager {
    IUniswapV3Pool constant pool = IUniswapV3Pool(0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640);
    ERC20 constant asset0 = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ERC20 constant asset1 = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    Lender lender0;
    Lender lender1;
    Borrower account;

    function callback(bytes calldata data, address)
        external
        returns (uint144)
    {
        Borrower _account = Borrower(msg.sender);

        (uint128 borrow0, uint128 borrow1, uint128 repay0, uint128 repay1, uint256 withdraw0, uint256 withdraw1) = abi
            .decode(data, (uint128, uint128, uint128, uint128, uint256, uint256));

        if (borrow0 != 0 || borrow1 != 0) {
            _account.borrow(borrow0, borrow1, msg.sender);
        }

        if (repay0 != 0 || repay1 != 0) {
            _account.repay(repay0, repay1);
        }

        if (withdraw0 != 0) asset0.transferFrom(msg.sender, address(this), withdraw0);
        if (withdraw1 != 0) asset1.transferFrom(msg.sender, address(this), withdraw1);

        return 0;
    }

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"));
        vm.rollFork(15_348_451);

        Factory factory = new Factory(
            VolatilityOracle(address(new VolatilityOracleMock())),
            new RateModel(),
            ERC20(address(0))
        );

        factory.createMarket(pool);
        (lender0, lender1, ) = factory.getMarket(pool);
        account = Borrower(factory.createBorrower(pool, address(this)));

        deal(address(account), DEFAULT_ANTE + 1);
    }

    // TODO: Test missing ante

    function test_liquidateLogicBothAreZero(uint184 liabilities0, uint184 liabilities1) public {
        unchecked {
            bool a = liabilities0 == 0 && liabilities1 == 0;
            bool b = uint256(liabilities0) + uint256(liabilities1) == 0;
            assertEq(a, b);
        }
    }

    function test_empty() public {
        bytes memory data = abi.encode(0, 0, 0, 0, 0, 0);
        bool[2] memory allowances;
        account.modify(this, data, allowances);
    }

    function test_addMargin() public {
        // give this contract some tokens
        deal(address(asset0), address(this), 10e6);
        deal(address(asset1), address(this), 1e17);

        // add margin
        asset0.transfer(address(account), 10e6);
        asset1.transfer(address(account), 1e17);

        bytes memory data = abi.encode(0, 0, 0, 0, 0, 0);
        bool[2] memory allowances;
        account.modify(this, data, allowances);
    }

    function test_borrow() public {
        _prepareKitties();

        // give this contract some tokens
        deal(address(asset0), address(this), 10e6);
        deal(address(asset1), address(this), 1e17);

        // add margin
        asset0.transfer(address(account), 10e6);
        asset1.transfer(address(account), 1e17);

        bytes memory data = abi.encode(100e6, 1e18, 0, 0, 0, 0);
        bool[2] memory allowances;
        account.modify(this, data, allowances);

        assertEq(lender0.borrowBalance(address(account)), 100e6);
        assertEq(lender1.borrowBalance(address(account)), 1e18);
        assertEq(asset0.balanceOf(address(account)), 10e6 + 100e6);
        assertEq(asset1.balanceOf(address(account)), 1e17 + 1e18);
    }

    function test_repay() public {
        test_borrow();

        bytes memory data = abi.encode(0, 0, 40e6, 0.4e18, 0, 0);
        bool[2] memory allowances;
        account.modify(this, data, allowances);

        assertEq(lender0.borrowBalance(address(account)), 60e6);
        assertEq(lender1.borrowBalance(address(account)), 0.6e18);
        assertEq(asset0.balanceOf(address(account)), 10e6 + 60e6);
        assertEq(asset1.balanceOf(address(account)), 1e17 + 0.6e18);
    }

    function testFail_completelyInsolvent() public {
        test_borrow();

        skip(86400); // seconds

        bytes memory data = abi.encode(0, 0, 0, 0, 10e6, 1e17);
        bool[2] memory allowances;
        allowances[0] = true;
        allowances[1] = true;
        account.modify(this, data, allowances);
    }

    function testFail_missingLiquidationIncentive() public {
        test_borrow();

        skip(86400); // seconds

        lender0.accrueInterest();
        lender1.accrueInterest();

        uint256 liabilities0 = lender0.borrowBalance(address(account));
        uint256 liabilities1 = lender1.borrowBalance(address(account));
        uint256 assets0 = asset0.balanceOf(address(account));
        uint256 assets1 = asset1.balanceOf(address(account));

        bytes memory data = abi.encode(0, 0, 0, 0, assets0 - liabilities0, assets1 - liabilities1);
        bool[2] memory allowances;
        allowances[0] = true;
        allowances[1] = true;
        account.modify(this, data, allowances);
    }

    function test_barelySolvent() public {
        test_borrow();

        skip(86400); // seconds

        lender0.accrueInterest();
        lender1.accrueInterest();

        uint256 liabilities0 = lender0.borrowBalance(address(account));
        uint256 liabilities1 = lender1.borrowBalance(address(account));
        uint256 assets0 = asset0.balanceOf(address(account));
        uint256 assets1 = asset1.balanceOf(address(account));

        bytes memory data = abi.encode(
            0,
            0,
            0,
            0,
            assets0 - ((liabilities0 * 1.005e8) / 1e8),
            assets1 - ((liabilities1 * 1.005e8) / 1e8)
        );
        bool[2] memory allowances;
        allowances[0] = true;
        allowances[1] = true;
        account.modify(this, data, allowances);
    }

    function _prepareKitties() private {
        address alice = makeAddr("alice");

        deal(address(asset0), address(lender0), 10000e6);
        lender0.deposit(10000e6, alice);

        deal(address(asset1), address(lender1), 3e18);
        lender1.deposit(3e18, alice);
    }

    function getParameters(IUniswapV3Pool) external pure returns (uint248 ante, uint8 nSigma) {
        ante = DEFAULT_ANTE;
        nSigma = DEFAULT_N_SIGMA;
    }
}
