// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import {DEFAULT_ANTE, DEFAULT_N_SIGMA} from "src/libraries/constants/Constants.sol";
import {zip} from "src/libraries/Positions.sol";

import "src/Factory.sol";
import "src/Borrower.sol";
import "src/Lender.sol";
import "src/RateModel.sol";

import {FatFactory, VolatilityOracleMock, getSeed} from "../Utils.sol";

contract BorrowerGasTest is Test, IManager {
    IUniswapV3Pool constant pool = IUniswapV3Pool(0xC2e9F25Be6257c210d7Adf0D4Cd6E3E881ba25f8);
    ERC20 constant asset0 = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    ERC20 constant asset1 = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    Lender immutable lender0;
    Lender immutable lender1;
    Borrower immutable account;
    uint32 immutable oracleSeed;

    constructor() {
        vm.createSelectFork(vm.rpcUrl("mainnet"));
        vm.rollFork(15_348_451);

        Factory factory = new FatFactory(
            address(0),
            address(0),
            VolatilityOracle(address(new VolatilityOracleMock())),
            new RateModel()
        );

        factory.createMarket(pool);
        (lender0, lender1, ) = factory.getMarket(pool);
        account = factory.createBorrower(pool, address(this), bytes12(0));
        oracleSeed = getSeed(pool);
    }

    function setUp() public {
        deal(address(account), DEFAULT_ANTE + 1);

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

        // Uniswap deposit (so we're able to test Uniswap withdrawal)
        pool.mint(address(account), 0, 60, 1000000, "");
    }

    function test_modify() public {
        bytes memory data = abi.encode(Action.NONE, 0, 0);
        account.modify(this, data, oracleSeed);
    }

    function test_modifyWithAnte() public {
        bytes memory data = abi.encode(Action.NONE, 0, 0);
        account.modify{value: DEFAULT_ANTE + 1 wei}(this, data, oracleSeed);
    }

    function test_addMargin() public {
        asset1.transfer(address(account), 0.78e18);
    }

    function test_borrow() public {
        bytes memory data = abi.encode(Action.BORROW, 0, 20e18); // 0 DAI, 20 WETH
        account.modify(this, data, oracleSeed);
    }

    function test_repay() public {
        bytes memory data = abi.encode(Action.REPAY, 0, 20e18); // 0 DAI, 20 WETH
        account.modify(this, data, oracleSeed);
    }

    function test_withdraw() public {
        bytes memory data = abi.encode(Action.WITHDRAW, 1e18, 1e18); // 1 DAI, 1 WETH
        account.modify(this, data, oracleSeed);
    }

    function test_uniswapDepositStandard() public {
        pool.mint(address(account), -75600, -75540, 10000000, "");
    }

    function test_uniswapDepositInBorrower() public {
        bytes memory data = abi.encode(Action.UNI_DEPOSIT, 0, 0);
        account.modify(this, data, oracleSeed);
    }

    function test_uniswapWithdraw() public {
        bytes memory data = abi.encode(Action.UNI_WITHDRAW, 0, 0);
        account.modify(this, data, oracleSeed);
    }

    function test_getUniswapPositions() public {
        vm.pauseGasMetering();
        test_uniswapDepositInBorrower();
        vm.resumeGasMetering();

        account.getUniswapPositions();
    }

    enum Action {
        NONE,
        BORROW,
        REPAY,
        WITHDRAW,
        UNI_DEPOSIT,
        UNI_WITHDRAW
    }

    function callback(bytes calldata data, address, uint208) external returns (uint208 positions) {
        require(msg.sender == address(account));

        (Action action, uint256 amount0, uint256 amount1) = abi.decode(data, (Action, uint256, uint256));

        if (action == Action.NONE) {} else if (action == Action.BORROW) {
            account.borrow(amount0, amount1, msg.sender);
        } else if (action == Action.REPAY) {
            account.repay(amount0, amount1);
        } else if (action == Action.WITHDRAW) {
            account.transfer(amount0, amount1, address(this));
        } else if (action == Action.UNI_DEPOSIT) {
            account.uniswapDeposit(-75600, -75540, 10000000000);
            positions = zip([-75600, -75540, 0, 0, 0, 0]);
        } else if (action == Action.UNI_WITHDRAW) {
            account.uniswapWithdraw(0, 60, 1000000, address(account));
        }
    }

    function uniswapV3MintCallback(uint256 _amount0, uint256 _amount1, bytes calldata) external {
        if (_amount0 != 0) asset0.transfer(msg.sender, _amount0);
        if (_amount1 != 0) asset1.transfer(msg.sender, _amount1);
    }

    function getParameters(IUniswapV3Pool) external pure returns (uint248 ante, uint8 nSigma) {
        ante = DEFAULT_ANTE;
        nSigma = DEFAULT_N_SIGMA;
    }
}
