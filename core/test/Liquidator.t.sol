// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import {B, LIQUIDATION_INCENTIVE} from "src/libraries/constants/Constants.sol";
import {zip} from "src/libraries/Positions.sol";

import "src/Borrower.sol";
import "src/Lender.sol";

import {deploySingleBorrower, deploySingleLender} from "./Utils.sol";

contract LiquidatorTest is Test, IManager, ILiquidator {
    IUniswapV3Pool constant pool = IUniswapV3Pool(0xC2e9F25Be6257c210d7Adf0D4Cd6E3E881ba25f8);
    ERC20 constant asset0 = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    ERC20 constant asset1 = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    Lender immutable lender0;
    Lender immutable lender1;
    Borrower immutable account;

    constructor() {
        vm.createSelectFork(vm.rpcUrl("mainnet"));
        vm.rollFork(15_348_451);

        lender0 = deploySingleLender(asset0, address(this), new RateModel());
        lender1 = deploySingleLender(asset1, address(this), new RateModel());
        account = deploySingleBorrower(pool, lender0, lender1);
        account.initialize(address(this), B);

        lender0.whitelist(address(account));
        lender1.whitelist(address(account));
    }

    function setUp() public {
        // deal to lender and deposit (so that there are assets to borrow)
        deal(address(asset0), address(lender0), 10000e18); // DAI
        deal(address(asset1), address(lender1), 10000e18); // WETH
        lender0.deposit(10000e18, address(12345));
        lender1.deposit(10000e18, address(12345));

        deal(address(account), account.ANTE() + 1);
    }

    function test_warn(uint8 seed0, uint8 seed1) public {
        uint256 margin0 = 1e18 * (seed0 % 8 + 1); // TODO: Fuzz testing RPC concerns
        uint256 margin1 = 0.1e18 * (seed1 % 8 + 1);
        uint256 borrows0 = margin0 * 200;
        uint256 borrows1 = margin1 * 200;

        deal(address(asset0), address(account), margin0);
        deal(address(asset1), address(account), margin1);

        bytes memory data = abi.encode(Action.BORROW, borrows0, borrows1);
        bool[2] memory allowances;
        account.modify(this, data, allowances);

        assertEq(lender0.borrowBalance(address(account)), borrows0);
        assertEq(lender1.borrowBalance(address(account)), borrows1);
        assertEq(asset0.balanceOf(address(account)), borrows0 + margin0);
        assertEq(asset1.balanceOf(address(account)), borrows1 + margin1);

        vm.expectRevert(bytes("Aloe: healthy"));
        account.warn();

        vm.expectRevert(bytes("Aloe: healthy"));
        account.liquidate(this, bytes(""), 1);

        setInterest(lender0, 10010);
        setInterest(lender1, 10010);
        assertEq(lender0.borrowBalance(address(account)), borrows0 * 10010 / 10000);
        assertEq(lender1.borrowBalance(address(account)), borrows1 * 10010 / 10000);

        account.warn();

        (, , uint80 unleashLiquidationTime, ) = account.slot0();
        assertEq(unleashLiquidationTime, block.timestamp + LIQUIDATION_GRACE_PERIOD);

        vm.expectRevert(bytes(""));
        account.warn();

        // MARK: actual command
        account.liquidate(this, bytes(""), 1);

        assertEq(lender0.borrowBalance(address(account)), 0);
        assertEq(lender1.borrowBalance(address(account)), 0);
        assertEq(asset0.balanceOf(address(account)), borrows0 + margin0 - borrows0 * 10010 / 10000);
        assertEq(asset1.balanceOf(address(account)), borrows1 + margin1 - borrows1 * 10010 / 10000);
    }

    function test_spec_repayDAI() public {
        uint256 strain = 1;
        // give the account 1 DAI
        deal(address(asset0), address(account), 1e18);

        // borrow 200 DAI
        bytes memory data = abi.encode(Action.BORROW, 200e18, 0);
        bool[2] memory allowances;
        account.modify(this, data, allowances);

        assertEq(lender0.borrowBalance(address(account)), 200e18);
        assertEq(asset0.balanceOf(address(account)), 201e18);

        vm.expectRevert(bytes("Aloe: healthy"));
        account.liquidate(this, bytes(""), strain);

        setInterest(lender0, 10010);
        assertEq(lender0.borrowBalance(address(account)), 200.2e18);

        vm.expectRevert();
        account.liquidate(this, bytes(""), 0);

        // MARK: actual command
        account.liquidate(this, bytes(""), strain);

        assertEq(lender0.borrowBalance(address(account)), 0);
        assertEq(asset0.balanceOf(address(account)), 0.8e18);
    }

    function test_spec_repayETH() public {
        uint256 strain = 1;
        // give the account 0.1 ETH
        deal(address(asset1), address(account), 0.1e18);

        // borrow 20 ETH
        bytes memory data = abi.encode(Action.BORROW, 0, 20e18);
        bool[2] memory allowances;
        account.modify(this, data, allowances);

        assertEq(lender1.borrowBalance(address(account)), 20e18);
        assertEq(asset1.balanceOf(address(account)), 20.1e18);

        vm.expectRevert(bytes("Aloe: healthy"));
        account.liquidate(this, bytes(""), strain);

        setInterest(lender1, 10010);
        assertEq(lender1.borrowBalance(address(account)), 20.02e18);

        vm.expectRevert();
        account.liquidate(this, bytes(""), 0);

        // MARK: actual command
        account.liquidate(this, bytes(""), strain);

        assertEq(lender1.borrowBalance(address(account)), 0);
        assertEq(asset1.balanceOf(address(account)), 0.08e18);
    }

    function test_spec_repayDAIAndETH() public {
        uint256 strain = 1;
        // give the account 1 DAI and 0.1 ETH
        deal(address(asset0), address(account), 1e18);
        deal(address(asset1), address(account), 0.1e18);

        // borrow 200 DAI and 20 ETH
        bytes memory data = abi.encode(Action.BORROW, 200e18, 20e18);
        bool[2] memory allowances;
        account.modify(this, data, allowances);

        assertEq(lender0.borrowBalance(address(account)), 200e18);
        assertEq(lender1.borrowBalance(address(account)), 20e18);
        assertEq(asset0.balanceOf(address(account)), 201e18);
        assertEq(asset1.balanceOf(address(account)), 20.1e18);

        vm.expectRevert(bytes("Aloe: healthy"));
        account.liquidate(this, bytes(""), strain);

        setInterest(lender0, 10010);
        setInterest(lender1, 10010);
        assertEq(lender0.borrowBalance(address(account)), 200.2e18);
        assertEq(lender1.borrowBalance(address(account)), 20.02e18);

        vm.expectRevert();
        account.liquidate(this, bytes(""), 0);

        // MARK: actual command
        account.liquidate(this, bytes(""), strain);

        assertEq(lender0.borrowBalance(address(account)), 0);
        assertEq(lender1.borrowBalance(address(account)), 0);
        assertEq(asset0.balanceOf(address(account)), 0.8e18);
        assertEq(asset1.balanceOf(address(account)), 0.08e18);
    }

    function test_spec_repayDAIAndETHWithUniswapPosition() public {
        uint256 strain = 1;
        // give the account 1 DAI and 0.1 ETH
        deal(address(asset0), address(account), 1.1e18);
        deal(address(asset1), address(account), 0.1e18);

        // borrow 200 DAI and 20 ETH
        bytes memory data = abi.encode(Action.BORROW, 200e18, 20e18);
        bool[2] memory allowances;
        account.modify(this, data, allowances);

        // create a small Uniswap position
        data = abi.encode(Action.UNI_DEPOSIT, 0, 0);
        account.modify(this, data, allowances);

        assertEq(lender0.borrowBalance(address(account)), 200e18);
        assertEq(lender1.borrowBalance(address(account)), 20e18);

        vm.expectRevert(bytes("Aloe: healthy"));
        account.liquidate(this, bytes(""), strain);

        setInterest(lender0, 10010);
        setInterest(lender1, 10010);
        assertEq(lender0.borrowBalance(address(account)), 200.2e18);
        assertEq(lender1.borrowBalance(address(account)), 20.02e18);

        vm.expectRevert();
        account.liquidate(this, bytes(""), 0);

        // MARK: actual command
        account.liquidate(this, bytes(""), strain);

        assertEq(lender0.borrowBalance(address(account)), 0);
        assertEq(lender1.borrowBalance(address(account)), 0);
        assertEq(asset0.balanceOf(address(account)), 899999999999999999);
        assertEq(asset1.balanceOf(address(account)), 79999999999999999);

        (uint128 liquidity, , , , ) = pool.positions(keccak256(abi.encodePacked(address(account), int24(-75600), int24(-75540))));
        assertEq(liquidity, 0);
    }

    function test_spec_interestTriggerRepayDAIUsingSwap(uint8 strain) public {
        strain = (strain % 8) + 1;

        // give the account 1 WETH
        deal(address(asset1), address(account), 1e18);

        uint256 debt = 1617e18;

        // borrow `debt` DAI
        bytes memory data = abi.encode(Action.BORROW, debt, 0);
        bool[2] memory allowances;
        account.modify(this, data, allowances);

        assertEq(lender0.borrowBalance(address(account)), debt);
        assertEq(asset0.balanceOf(address(account)), debt);
        assertEq(asset1.balanceOf(address(account)), 1e18);

        // withdraw `debt` DAI
        data = abi.encode(Action.WITHDRAW, debt, 0);
        allowances[0] = true;
        account.modify(this, data, allowances);

        assertEq(asset0.balanceOf(address(account)), 0);

        vm.expectRevert(bytes("Aloe: healthy"));
        account.liquidate(this, bytes(""), 1);

        setInterest(lender0, 10010);
        debt = debt * 10010 / 10000;
        assertEq(lender0.borrowBalance(address(account)), debt);

        // Disable warn() requirement by setting unleashLiquidationTime=1
        vm.store(address(account), bytes32(uint256(0)), bytes32(uint256(
            uint160(address(this)) + (1 << 160)
        )));

        vm.expectRevert();
        account.liquidate(this, bytes(""), 0);

        Prices memory prices = account.getPrices(B);
        uint256 price = Math.mulDiv(prices.c, prices.c, Q96);
        uint256 incentive1 = Math.mulDiv(debt / LIQUIDATION_INCENTIVE, price, Q96);
        uint256 assets1 = Math.mulDiv(debt / strain, price, Q96) + incentive1 / strain;

        // MARK: actual command
        data = abi.encode(assets1);
        account.liquidate(this, data, strain);

        assertEq(lender0.borrowBalance(address(account)), debt - debt / strain);
        assertGt(asset1.balanceOf(address(this)), 0);
    }

    function test_spec_cannotReenterLiquidate(uint8 strain) public {
        strain = (strain % 8) + 1;

        // give the account 1 WETH
        deal(address(asset1), address(account), 1e18);

        uint256 debt = 1617e18;

        // borrow `debt` DAI
        bytes memory data = abi.encode(Action.BORROW, debt, 0);
        bool[2] memory allowances;
        account.modify(this, data, allowances);

        // withdraw `debt` DAI
        data = abi.encode(Action.WITHDRAW, debt, 0);
        allowances[0] = true;
        account.modify(this, data, allowances);

        setInterest(lender0, 10010);
        debt = debt * 10010 / 10000;

        // Disable warn() requirement by setting unleashLiquidationTime=1
        vm.store(address(account), bytes32(uint256(0)), bytes32(uint256(
            uint160(address(this)) + (1 << 160)
        )));

        Prices memory prices = account.getPrices(B);
        uint256 price = Math.mulDiv(prices.c, prices.c, Q96);
        uint256 incentive1 = Math.mulDiv(debt / LIQUIDATION_INCENTIVE, price, Q96);
        uint256 assets1 = Math.mulDiv(debt / strain, price, Q96) + incentive1 / strain;

        vm.expectRevert();
        data = abi.encode(type(uint256).max); // Special value that we're using to tell our test callback to try to re-enter
        account.liquidate(this, data, strain);

        // MARK: actual command
        data = abi.encode(assets1, false);
        account.liquidate(this, data, strain);
    }

    function test_spec_interestTriggerRepayETHUsingSwap(uint8 scale, uint8 strain) public {
        // These tests are forked, so we don't want to spam the RPC with too many fuzzing values
        strain = (strain % 8) + 1;

        Prices memory prices = account.getPrices(B);
        uint256 borrow1 = 1e18 * ((scale % 4) + 1); // Same concern here
        {
            uint256 effectiveLiabilities1 = borrow1 + borrow1 / 200 + borrow1 / 20;
            uint256 margin0 = Math.mulDiv(effectiveLiabilities1, Q96, Math.mulDiv(prices.a, prices.a, Q96));
            // give the account its margin
            deal(address(asset0), address(account), margin0 + 1);
        }

        // borrow ETH
        bytes memory data = abi.encode(Action.BORROW, 0, borrow1);
        bool[2] memory allowances;
        account.modify(this, data, allowances);

        assertEq(lender1.borrowBalance(address(account)), borrow1);
        assertEq(asset1.balanceOf(address(account)), borrow1);

        // withdraw ETH
        data = abi.encode(Action.WITHDRAW, 0, borrow1);
        allowances[1] = true;
        account.modify(this, data, allowances);

        assertEq(asset1.balanceOf(address(account)), 0);

        vm.expectRevert(bytes("Aloe: healthy"));
        account.liquidate(this, bytes(""), 1);

        setInterest(lender1, 10010);
        borrow1 = borrow1 * 10010 / 10000;
        assertEq(lender1.borrowBalance(address(account)), borrow1);

        // Disable warn() requirement by setting unleashLiquidationTime=1
        vm.store(address(account), bytes32(uint256(0)), bytes32(uint256(
            uint160(address(this)) + (1 << 160)
        )));

        vm.expectRevert();
        account.liquidate(this, bytes(""), 0);

        uint256 price = Math.mulDiv(prices.c, prices.c, Q96);
        uint256 incentive1 = borrow1 / LIQUIDATION_INCENTIVE;
        uint256 assets0 = Math.mulDiv(borrow1 / strain + incentive1 / strain, Q96, price);

        // MARK: actual command
        data = abi.encode(assets0);
        account.liquidate(this, data, strain);

        assertApproxEqAbs(lender1.borrowBalance(address(account)), borrow1 - borrow1 / strain, 1);
        assertGt(asset0.balanceOf(address(this)), 0);
    }

    function test_spec_priceTriggerRepayDAIUsingSwap() public {
        uint256 strain = 1;

        Prices memory prices = account.getPrices(B);
        uint256 borrow0 = 1000e18;
        {
            uint256 effectiveLiabilities0 = borrow0 + borrow0 / 200;
            uint256 margin1 = Math.mulDiv(effectiveLiabilities0, Math.mulDiv(prices.b, prices.b, Q96), Q96);
            margin1 += Math.mulDiv(borrow0, Math.mulDiv(prices.c, prices.c, Q96), Q96) / 20;
            // give the account its margin
            deal(address(asset1), address(account), margin1 + 1);
        }

        // borrow DAI
        bytes memory data = abi.encode(Action.BORROW, borrow0, 0);
        bool[2] memory allowances;
        account.modify(this, data, allowances);

        assertEq(lender0.borrowBalance(address(account)), borrow0);
        assertEq(asset0.balanceOf(address(account)), borrow0);

        // withdraw DAI
        data = abi.encode(Action.WITHDRAW, borrow0, 0);
        allowances[0] = true;
        account.modify(this, data, allowances);

        assertEq(asset0.balanceOf(address(account)), 0);

        vm.expectRevert(bytes("Aloe: healthy"));
        account.liquidate(this, bytes(""), 1);

        // increase price of DAI by 1 tick
        {
            uint32[] memory t = new uint32[](2);
            t[0] = 1200;
            t[1] = 0;
            (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s) = pool.observe(t);
            int24 newTick = TickMath.getTickAtSqrtRatio(prices.c) + 1;
            tickCumulatives[0] = 0;
            tickCumulatives[1] = int56(newTick) * 1200;
            vm.mockCall(
                address(pool),
                abi.encodeWithSelector(pool.observe.selector),
                abi.encode(tickCumulatives, secondsPerLiquidityCumulativeX128s)
            );
        }

        // Disable warn() requirement by setting unleashLiquidationTime=1
        vm.store(address(account), bytes32(uint256(0)), bytes32(uint256(
            uint160(address(this)) + (1 << 160)
        )));

        prices = account.getPrices(B);

        uint256 price = Math.mulDiv(prices.c, prices.c, Q96);
        uint256 assets1 = Math.mulDiv(borrow0 / strain, price, Q96);
        assets1 += assets1 / LIQUIDATION_INCENTIVE;

        // MARK: actual command
        data = abi.encode(assets1);
        account.liquidate(this, data, strain);

        assertEq(lender0.borrowBalance(address(account)), borrow0 - borrow0 / strain);
        assertGt(asset1.balanceOf(address(this)), 0);
    }

    function test_warnDoesProtect() public {
        uint256 strain = 1;

        Prices memory prices = account.getPrices(B);
        uint256 borrow0 = 1000e18;
        {
            uint256 effectiveLiabilities0 = borrow0 + borrow0 / 200;
            uint256 margin1 = Math.mulDiv(effectiveLiabilities0, Math.mulDiv(prices.b, prices.b, Q96), Q96);
            margin1 += Math.mulDiv(borrow0, Math.mulDiv(prices.c, prices.c, Q96), Q96) / 20;
            // give the account its margin
            deal(address(asset1), address(account), margin1 + 1);
        }

        // borrow DAI
        bytes memory data = abi.encode(Action.BORROW, borrow0, 0);
        bool[2] memory allowances;
        account.modify(this, data, allowances);

        // withdraw DAI
        data = abi.encode(Action.WITHDRAW, borrow0, 0);
        allowances[0] = true;
        account.modify(this, data, allowances);

        vm.expectRevert(bytes("Aloe: healthy"));
        account.liquidate(this, bytes(""), 1);

        // increase price of DAI by 1 tick
        {
            uint32[] memory t = new uint32[](2);
            t[0] = 1200;
            t[1] = 0;
            (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s) = pool.observe(t);
            int24 newTick = TickMath.getTickAtSqrtRatio(prices.c) + 1;
            tickCumulatives[0] = 0;
            tickCumulatives[1] = int56(newTick) * 1200;
            vm.mockCall(
                address(pool),
                abi.encodeWithSelector(pool.observe.selector),
                abi.encode(tickCumulatives, secondsPerLiquidityCumulativeX128s)
            );
        }

        vm.expectRevert(bytes("Aloe: grace"));
        account.liquidate(this, bytes(""), 1);

        account.warn();

        vm.expectRevert(bytes("Aloe: grace"));
        account.liquidate(this, bytes(""), 1);

        skip(LIQUIDATION_GRACE_PERIOD);

        vm.expectRevert(bytes("Aloe: grace"));
        account.liquidate(this, bytes(""), 1);

        skip(1);

        prices = account.getPrices(B);

        uint256 price = Math.mulDiv(prices.c, prices.c, Q96);
        uint256 assets1 = Math.mulDiv(borrow0 / strain, price, Q96);
        assets1 += assets1 / LIQUIDATION_INCENTIVE;

        // MARK: actual command
        data = abi.encode(assets1);
        account.liquidate(this, data, strain);

        (, , uint80 unleashLiquidationTime, ) = account.slot0();
        assertEq(unleashLiquidationTime, 0);
    }

    enum Action {
        WITHDRAW,
        BORROW,
        UNI_DEPOSIT
    }

    // IManager
    function callback(
        bytes calldata data
    ) external returns (uint144 positions) {
        require(msg.sender == address(account));

        (Action action, uint256 amount0, uint256 amount1) = abi.decode(data, (Action, uint256, uint256));

        if (action == Action.WITHDRAW) {
            if (amount0 > 0) asset0.transferFrom(address(account), address(this), amount0);
            if (amount1 > 0) asset1.transferFrom(address(account), address(this), amount1);
        } else if (action == Action.BORROW) {
            account.borrow(amount0, amount1, msg.sender);
        } else if (action == Action.UNI_DEPOSIT) {
            account.uniswapDeposit(-75600, -75540, 200000000000000000);
            positions = zip([-75600, -75540, 0, 0, 0, 0]);
        }
    }

    // ILiquidator
    receive() external payable {}

    function swap1For0(
        bytes calldata data,
        uint256 actual,
        uint256 expected0
    ) external {
        uint256 expected = abi.decode(data, (uint256));
        if (expected == type(uint256).max) {
            Borrower(msg.sender).liquidate(this, data, 1);
        }
        assertEq(actual, expected);
        pool.swap(msg.sender, false, -int256(expected0), TickMath.MAX_SQRT_RATIO - 1, bytes(""));
    }

    function swap0For1(
        bytes calldata data,
        uint256 actual,
        uint256 expected1
    ) external {
        uint256 expected = abi.decode(data, (uint256));
        if (expected == type(uint256).max) {
            Borrower(msg.sender).liquidate(this, data, 1);
        }
        assertEq(actual, expected);
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

    function setInterest(Lender lender, uint256 amount) private {
        bytes32 ID = bytes32(uint256(1));
        uint256 slot1 = uint256(vm.load(address(lender), ID));

        uint256 borrowBase = slot1 % (1 << 184);
        uint256 borrowIndex = slot1 >> 184;

        uint256 newSlot1 = borrowBase + ((borrowIndex * amount / 10_000) << 184);
        vm.store(address(lender), ID, bytes32(newSlot1));
    }
}
