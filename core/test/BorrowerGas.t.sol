// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

import "forge-std/Test.sol";

import "src/Lender.sol";
import "src/Borrower.sol";

import {deploySingleLender} from "./Utils.sol";

contract BorrowerGasTest is Test, IManager {
    IUniswapV3Pool constant pool = IUniswapV3Pool(0xC2e9F25Be6257c210d7Adf0D4Cd6E3E881ba25f8);
    ERC20 constant asset0 = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    ERC20 constant asset1 = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    Lender immutable lender0;
    Lender immutable lender1;
    Borrower immutable account;

    constructor() {
        lender0 = deploySingleLender(asset0, address(this), new InterestModel());
        lender1 = deploySingleLender(asset1, address(this), new InterestModel());
        account = new Borrower(pool, lender0, lender1, address(this));
    }

    function setUp() public {
        lender0.whitelist(address(account));
        lender1.whitelist(address(account));

        // deal to this contract (so we're able to test add margin)
        deal(address(asset0), address(this), 99e18); // DAI
        deal(address(asset1), address(this), 0.8e18); // WETH

        // deal to lender and deposit (so we're able to test borrow)
        deal(address(asset0), address(lender0), 10000e18); // DAI
        deal(address(asset1), address(lender1), 10000e18); // WETH
        lender0.deposit(10000e18, address(12345));
        lender1.deposit(10000e18, address(12345));

        // deal to borrower and borrow (so we're able to test repay)
        deal(address(asset0), address(account), 333e18); // DAI
        deal(address(asset1), address(account), 2e18); // WETH
        test_borrow();
    }

    function test_modify() public {
        bytes memory data = abi.encode(Action.NONE, 0, 0);
        bool[4] memory allowances;
        account.modify(this, data, allowances);
    }

    function test_addMargin() public {
        asset1.transfer(address(account), 0.78e18);
    }

    function test_borrow() public {
        bytes memory data = abi.encode(Action.BORROW, 0, 20e18); // 0 DAI, 20 WETH
        bool[4] memory allowances;
        account.modify(this, data, allowances);
    }

    function test_repay() public {
        bytes memory data = abi.encode(Action.REPAY, 0, 20e18); // 0 DAI, 20 WETH
        bool[4] memory allowances;
        account.modify(this, data, allowances);
    }

    function test_withdraw() public {
        bytes memory data = abi.encode(Action.WITHDRAW, 0, 1e18); // 0 DAI, 1 WETH
        bool[4] memory allowances;
        allowances[0] = true;
        allowances[1] = true;
        account.modify(this, data, allowances);
    }

    enum Action {
        NONE,
        BORROW,
        REPAY,
        WITHDRAW
    }

    function callback(bytes calldata data) external returns (
        Uniswap.Position[] memory positions,
        bool includeLenderReceipts
    ) {
        require(msg.sender == address(account));

        (
            Action action,
            uint256 amount0,
            uint256 amount1
        ) = abi.decode(data, (Action, uint256, uint256));

        if (action == Action.NONE) {
        } else if (action == Action.BORROW) {
            account.borrow(amount0, amount1, msg.sender);
        } else if (action == Action.REPAY) {
            account.repay(amount0, amount1);
        } else if (action == Action.WITHDRAW) {
            if (amount0 != 0) asset0.transferFrom(msg.sender, address(this), amount0);
            if (amount0 != 0) asset1.transferFrom(msg.sender, address(this), amount0);
        }
    }
}
