// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import {DEFAULT_ANTE, DEFAULT_N_SIGMA} from "src/libraries/constants/Constants.sol";
import {zip} from "src/libraries/Positions.sol";

import "src/Borrower.sol";
import "src/Factory.sol";
import "src/Lender.sol";
import "src/RateModel.sol";

import {FatFactory, VolatilityOracleMock, getSeed} from "../Utils.sol";

contract LiquidatorGasTest is Test, IManager, ILiquidator {
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
        // deal to lender and deposit (so that there are assets to borrow)
        deal(address(asset0), address(lender0), 1800e18); // DAI
        deal(address(asset1), address(lender1), 100e18); // WETH
        lender0.deposit(1800e18, address(12345));
        lender1.deposit(100e18, address(12345));

        deal(address(account), DEFAULT_ANTE + 1);
    }

    function test_noCallbackOneAsset() public {
        vm.pauseGasMetering();

        // give the account 1 DAI
        deal(address(asset0), address(account), 1e18 + 2100);

        // borrow 200 DAI
        bytes memory data = abi.encode(Action.BORROW, 200e18, 0);
        account.modify(this, data, oracleSeed);

        assertEq(lender0.borrowBalance(address(account)), 200e18);

        vm.expectRevert(bytes("Aloe: healthy"));
        account.liquidate(this, bytes(""), 1, oracleSeed);

        setInterest(lender0, 10010);

        assertGt(lender0.borrowBalance(address(account)), 200e18);
        assertLt(lender0.borrowBalance(address(account)), 201e18);

        vm.resumeGasMetering();

        // MARK: actual command
        account.liquidate(this, bytes(""), 1, oracleSeed);

        vm.pauseGasMetering();
        assertEq(lender0.borrowBalance(address(account)), 0);
        vm.resumeGasMetering();
    }

    function test_noCallbackTwoAssets() public {
        vm.pauseGasMetering();

        // give the account 1 DAI and 0.1 WETH
        deal(address(asset0), address(account), 1e18);
        deal(address(asset1), address(account), 0.1e18 + 1);

        // borrow 200 DAI and 20 WETH
        bytes memory data = abi.encode(Action.BORROW, 200e18, 20e18);
        account.modify(this, data, oracleSeed);

        assertEq(lender0.borrowBalance(address(account)), 200e18);
        assertEq(lender1.borrowBalance(address(account)), 20e18);

        vm.expectRevert(bytes("Aloe: healthy"));
        account.liquidate(this, bytes(""), 1, oracleSeed);

        setInterest(lender0, 10010);
        setInterest(lender1, 10010);

        assertGt(lender0.borrowBalance(address(account)), 200e18);
        assertLt(lender0.borrowBalance(address(account)), 201e18);
        assertGt(lender1.borrowBalance(address(account)), 20e18);
        assertLt(lender1.borrowBalance(address(account)), 20.1e18);

        vm.resumeGasMetering();

        // MARK: actual command
        account.liquidate(this, bytes(""), 1, oracleSeed);

        vm.pauseGasMetering();
        assertEq(lender0.borrowBalance(address(account)), 0);
        assertEq(lender1.borrowBalance(address(account)), 0);
        vm.resumeGasMetering();
    }

    function test_noCallbackTwoAssetsAndUniswapPosition() public {
        vm.pauseGasMetering();

        // give the account 1 DAI and 0.1 WETH
        deal(address(asset0), address(account), 1e18);
        deal(address(asset1), address(account), 0.1e18);

        // borrow 200 DAI and 20 WETH
        bytes memory data = abi.encode(Action.BORROW, 199.5e18, 20e18);
        account.modify(this, data, oracleSeed);

        // create a small Uniswap position
        data = abi.encode(Action.UNI_DEPOSIT, 0, 0);
        account.modify(this, data, oracleSeed);

        assertEq(account.getUniswapPositions().length, 2);

        setInterest(lender0, 10010);
        setInterest(lender1, 10010);

        vm.resumeGasMetering();

        // MARK: actual command
        account.liquidate(this, bytes(""), 1, oracleSeed);

        vm.pauseGasMetering();
        assertEq(lender0.borrowBalance(address(account)), 0);
        assertEq(lender1.borrowBalance(address(account)), 0);
        vm.resumeGasMetering();
    }

    function test_withCallbackAndSwap() public {
        vm.pauseGasMetering();

        // give the account 1 WETH
        deal(address(asset1), address(account), 1e18);

        uint256 debt = 1595e18;
        // borrow `debt` DAI
        bytes memory data = abi.encode(Action.BORROW, debt, 0);
        account.modify(this, data, oracleSeed);

        // withdraw `debt` DAI
        data = abi.encode(Action.WITHDRAW, debt, 0);
        account.modify(this, data, oracleSeed);

        setInterest(lender0, 10100);
        setInterest(lender1, 10100);

        account.warn(oracleSeed);
        skip(LIQUIDATION_GRACE_PERIOD + 1 seconds);
        lender0.accrueInterest();
        lender1.accrueInterest();

        vm.resumeGasMetering();

        // MARK: actual command
        account.liquidate(this, bytes(""), 1, oracleSeed);

        vm.pauseGasMetering();
        assertEq(lender0.borrowBalance(address(account)), 0);
        assertEq(lender1.borrowBalance(address(account)), 0);
        vm.resumeGasMetering();
    }

    function test_warn() public {
        vm.pauseGasMetering();

        // give the account 1 WETH
        deal(address(asset1), address(account), 1e18);

        uint256 debt = 1595e18;
        // borrow `debt` DAI
        bytes memory data = abi.encode(Action.BORROW, debt, 0);
        account.modify(this, data, oracleSeed);

        // withdraw `debt` DAI
        data = abi.encode(Action.WITHDRAW, debt, 0);
        account.modify(this, data, oracleSeed);

        setInterest(lender0, 10100);
        setInterest(lender1, 10100);

        vm.resumeGasMetering();

        account.warn(oracleSeed);
    }

    enum Action {
        WITHDRAW,
        BORROW,
        UNI_DEPOSIT
    }

    // IManager
    function callback(bytes calldata data, address, uint208) external returns (uint208 positions) {
        require(msg.sender == address(account));

        (Action action, uint256 amount0, uint256 amount1) = abi.decode(data, (Action, uint256, uint256));

        if (action == Action.WITHDRAW) {
            account.transfer(amount0, amount1, address(this));
        } else if (action == Action.BORROW) {
            account.borrow(amount0, amount1, msg.sender);
        } else if (action == Action.UNI_DEPOSIT) {
            account.uniswapDeposit(-75600, -75540, 100000000000000000);
            positions = zip([-75600, -75540, 0, 0, 0, 0]);
        }
    }

    // ILiquidator
    receive() external payable {}

    function swap1For0(
        bytes calldata,
        uint256,
        uint256 expected0
    ) external {
        pool.swap(msg.sender, false, -int256(expected0), TickMath.MAX_SQRT_RATIO - 1, bytes(""));
    }

    function swap0For1(
        bytes calldata,
        uint256,
        uint256 expected1
    ) external {
        pool.swap(msg.sender, true, -int256(expected1), TickMath.MIN_SQRT_RATIO + 1, bytes(""));
    }

    // IUniswapV3SwapCallback
    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata
    ) external {
        if (amount0Delta > 0) asset0.transfer(msg.sender, uint256(amount0Delta));
        if (amount1Delta > 0) asset1.transfer(msg.sender, uint256(amount1Delta));
    }

    // Factory mock
    function getParameters(IUniswapV3Pool) external pure returns (uint248 ante, uint8 nSigma) {
        ante = DEFAULT_ANTE;
        nSigma = DEFAULT_N_SIGMA;
    }

    // (helpers)
    function setInterest(Lender lender, uint256 amount) private {
        bytes32 ID = bytes32(uint256(1));
        uint256 slot1 = uint256(vm.load(address(lender), ID));

        uint256 borrowBase = slot1 % (1 << 184);
        uint256 borrowIndex = slot1 >> 184;

        uint256 newSlot1 = borrowBase + ((borrowIndex * amount / 10_000) << 184);
        vm.store(address(lender), ID, bytes32(newSlot1));
    }
}
