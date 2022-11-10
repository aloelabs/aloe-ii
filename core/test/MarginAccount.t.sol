// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

import "forge-std/Test.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";

import "src/InterestModel.sol";
import "src/Lender.sol";
import "src/MarginAccount.sol";

contract MarginAccountTest is Test, IManager {
    IUniswapV3Pool constant pool = IUniswapV3Pool(0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640);
    ERC20 constant asset0 = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ERC20 constant asset1 = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    Lender lender0;
    Lender lender1;
    MarginAccount account;

    // mock Factory
    function isMarginAccountAllowed(Lender _lender, address _account) external returns (bool) {
        return true;
    }

    function callback(bytes calldata data)
        external
        returns (Uniswap.Position[] memory positions, bool includeLenderReceipts)
    {
        MarginAccount _account = MarginAccount(msg.sender);

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
    }

    function setUp() public {
        lender0 = new Lender(asset0, new InterestModel(), address(this));
        lender1 = new Lender(asset1, new InterestModel(), address(this));
        account = new MarginAccount(pool, lender0, lender1, address(this));
    }

    function test_empty() public {
        bytes memory data = abi.encode(0, 0, 0, 0, 0, 0);
        bool[4] memory allowances;
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
        bool[4] memory allowances;
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
        bool[4] memory allowances;
        account.modify(this, data, allowances);

        assertEq(lender0.borrowBalanceCurrent(address(account)), 100e6);
        assertEq(lender1.borrowBalanceCurrent(address(account)), 1e18);
        assertEq(asset0.balanceOf(address(account)), 10e6 + 100e6);
        assertEq(asset1.balanceOf(address(account)), 1e17 + 1e18);
    }

    function test_repay() public {
        test_borrow();

        bytes memory data = abi.encode(0, 0, 50e6, 0.5e18, 0, 0);
        bool[4] memory allowances;
        allowances[0] = true;
        allowances[1] = true;
        account.modify(this, data, allowances);

        assertEq(lender0.borrowBalanceCurrent(address(account)), 50e6);
        assertEq(lender1.borrowBalanceCurrent(address(account)), 0.5e18);
        assertEq(asset0.balanceOf(address(account)), 10e6 + 50e6);
        assertEq(asset1.balanceOf(address(account)), 1e17 + 0.5e18);
    }

    function testFail_completelyInsolvent() public {
        test_borrow();

        skip(86400); // seconds

        bytes memory data = abi.encode(0, 0, 0, 0, 10e6, 1e17);
        bool[4] memory allowances;
        allowances[2] = true;
        allowances[3] = true;
        account.modify(this, data, allowances);
    }

    function testFail_missingLiquidationIncentive() public {
        test_borrow();

        skip(86400); // seconds

        lender0.accrueInterest();
        lender1.accrueInterest();

        uint256 liabilities0 = lender0.borrowBalanceCurrent(address(account));
        uint256 liabilities1 = lender1.borrowBalanceCurrent(address(account));
        uint256 assets0 = asset0.balanceOf(address(account));
        uint256 assets1 = asset1.balanceOf(address(account));

        bytes memory data = abi.encode(0, 0, 0, 0, assets0 - liabilities0, assets1 - liabilities1);
        bool[4] memory allowances;
        allowances[0] = true;
        allowances[1] = true;
        account.modify(this, data, allowances);
    }

    function test_barelySolvent() public {
        test_borrow();

        skip(86400); // seconds

        lender0.accrueInterest();
        lender1.accrueInterest();

        uint256 liabilities0 = lender0.borrowBalanceCurrent(address(account));
        uint256 liabilities1 = lender1.borrowBalanceCurrent(address(account));
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
        bool[4] memory allowances;
        allowances[0] = true;
        allowances[1] = true;
        account.modify(this, data, allowances);
    }

    function _prepareKitties() private {
        // give alice some tokens
        address alice = makeAddr("alice");
        deal(address(asset0), alice, 10000e6);
        deal(address(asset1), alice, 3e18);

        // have alice approve both kitties
        hoax(alice, 1e18);
        asset0.approve(address(lender0), type(uint256).max);
        hoax(alice);
        asset1.approve(address(lender1), type(uint256).max);

        // have alice deposit to both kitties
        hoax(alice);
        lender0.deposit(10000e6, alice);
        hoax(alice);
        lender1.deposit(3e18, alice);
    }
}
