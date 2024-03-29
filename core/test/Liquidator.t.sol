// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

import "forge-std/Test.sol";

import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";

import {
    DEFAULT_ANTE,
    DEFAULT_N_SIGMA,
    LIQUIDATION_INCENTIVE,
    LIQUIDATION_GRACE_PERIOD
} from "src/libraries/constants/Constants.sol";
import {Q96} from "src/libraries/constants/Q.sol";
import {zip} from "src/libraries/Positions.sol";

import "src/Borrower.sol";
import "src/Factory.sol";
import "src/Lender.sol";
import "src/RateModel.sol";

import {FatFactory, VolatilityOracleMock} from "./Utils.sol";

contract LiquidatorTest is Test, IManager, ILiquidator {
    IUniswapV3Pool constant pool = IUniswapV3Pool(0xC2e9F25Be6257c210d7Adf0D4Cd6E3E881ba25f8);
    ERC20 constant asset0 = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    ERC20 constant asset1 = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    uint256 constant TIME_OF_5_PERCENT = 5 minutes;

    Lender immutable lender0;
    Lender immutable lender1;
    Borrower immutable account;

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
    }

    function setUp() public {
        // deal to lender and deposit (so that there are assets to borrow)
        deal(address(asset0), address(lender0), 10000e18); // DAI
        deal(address(asset1), address(lender1), 10000e18); // WETH
        lender0.deposit(10000e18, address(12345));
        lender1.deposit(10000e18, address(12345));

        deal(address(account), DEFAULT_ANTE + 1);
    }

    /// forge-config: default.fuzz.runs = 16
    function test_fuzz_warn(uint8 seed0, uint8 seed1) public {
        uint256 margin0 = 1e18 * ((seed0 % 8) + 1);
        uint256 margin1 = 0.1e18 * ((seed1 % 8) + 1);
        uint256 borrows0 = margin0 * 200;
        uint256 borrows1 = margin1 * 200;

        // Extra due to rounding up in liabilities
        margin1 += 1;

        deal(address(asset0), address(account), margin0);
        deal(address(asset1), address(account), margin1);

        bytes memory data = abi.encode(Action.BORROW, borrows0, borrows1);
        account.modify(this, data, (1 << 32));

        assertEq(lender0.borrowBalance(address(account)), borrows0);
        assertEq(lender1.borrowBalance(address(account)), borrows1);
        assertEq(asset0.balanceOf(address(account)), borrows0 + margin0);
        assertEq(asset1.balanceOf(address(account)), borrows1 + margin1);

        vm.expectRevert(bytes("Aloe: healthy"));
        account.warn(1 << 32);

        vm.expectRevert(bytes(""));
        account.liquidate(this, bytes(""), 10000, (1 << 32));

        _setInterest(lender0, 10010);
        _setInterest(lender1, 10010);
        assertEq(lender0.borrowBalance(address(account)), (borrows0 * 10010) / 10000);
        assertEq(lender1.borrowBalance(address(account)), (borrows1 * 10010) / 10000);

        account.warn(1 << 32);
        vm.expectRevert(bytes(""));
        account.warn(1 << 32);

        uint40 unleashLiquidationTime = uint40((account.slot0() >> 208) % (1 << 40));
        assertEq(unleashLiquidationTime, block.timestamp);
        skip(LIQUIDATION_GRACE_PERIOD + 169 seconds);

        // MARK: actual command
        account.liquidate(this, abi.encode(uint256(0)), 10000, (1 << 32));

        assertEq(lender0.borrowBalance(address(account)), 0);
        assertEq(lender1.borrowBalance(address(account)), 0);
        uint256 f = BalanceSheet.auctionCurve(169 seconds);
        assertApproxEqRel(
            asset0.balanceOf(address(account)),
            borrows0 + margin0 - (borrows0 * 10010 * f) / 1e16,
            0.001e18
        );
        assertApproxEqRel(
            asset1.balanceOf(address(account)),
            borrows1 + margin1 - (borrows1 * 10010 * f) / 1e16,
            0.001e18
        );
    }

    function test_spec_repayDAI() public {
        uint16 closeFactor = 10000;
        // give the account 1 DAI (plus a little due to liabilities rounding up)
        deal(address(asset0), address(account), 1e18 + 1750);

        // borrow 200 DAI
        bytes memory data = abi.encode(Action.BORROW, 200e18, 0);
        account.modify(this, data, (1 << 32));

        assertEq(lender0.borrowBalance(address(account)), 200e18);
        assertEq(asset0.balanceOf(address(account)), 201e18 + 1750);

        vm.expectRevert(bytes("Aloe: healthy"));
        account.warn(1 << 32);

        _setInterest(lender0, 10010);
        assertEq(lender0.borrowBalance(address(account)), 200.2e18);

        account.warn(1 << 32);
        skip(LIQUIDATION_GRACE_PERIOD + 170 seconds);

        // MARK: actual command
        account.liquidate(this, abi.encode(uint256(0)), closeFactor, (1 << 32));

        assertEq(lender0.borrowBalance(address(account)), 0);
        assertEq(asset0.balanceOf(address(account)), 0.558651792067358746e18);
        assertEq(account.slot0(), uint256(0x800000000000f0f0f0f0f0f0f0f0000000000000000000000000000000000000));
    }

    function test_spec_repayETH() public {
        uint16 closeFactor = 10000;
        // give the account 0.1 ETH
        deal(address(asset1), address(account), 0.1e18);

        // borrow 20 ETH
        bytes memory data = abi.encode(Action.BORROW, 0, 20e18);
        account.modify(this, data, (1 << 32));

        assertEq(lender1.borrowBalance(address(account)), 20e18);
        assertEq(asset1.balanceOf(address(account)), 20.1e18);

        vm.expectRevert(bytes("Aloe: healthy"));
        account.warn(1 << 32);

        _setInterest(lender1, 10010);
        assertEq(lender1.borrowBalance(address(account)), 20.02e18);

        account.warn(1 << 32);
        skip(LIQUIDATION_GRACE_PERIOD + 170 seconds);

        // MARK: actual command
        account.liquidate(this, abi.encode(uint256(0)), closeFactor, (1 << 32));

        assertEq(lender1.borrowBalance(address(account)), 0);
        assertEq(asset1.balanceOf(address(account)), 0.055865282831508020e18);
        assertEq(account.slot0(), uint256(0x800000000000f0f0f0f0f0f0f0f0000000000000000000000000000000000000));
    }

    function test_spec_repayDAIAndETH() public {
        uint16 closeFactor = 10000;
        // give the account 1 DAI and 0.1 ETH
        deal(address(asset0), address(account), 1e18);
        deal(address(asset1), address(account), 0.1e18 + 1);

        // borrow 200 DAI and 20 ETH
        bytes memory data = abi.encode(Action.BORROW, 200e18, 20e18);
        account.modify(this, data, (1 << 32));

        assertEq(lender0.borrowBalance(address(account)), 200e18);
        assertEq(lender1.borrowBalance(address(account)), 20e18);
        assertEq(asset0.balanceOf(address(account)), 201e18);
        assertEq(asset1.balanceOf(address(account)), 20.1e18 + 1);

        vm.expectRevert(bytes("Aloe: healthy"));
        account.warn(1 << 32);

        _setInterest(lender0, 10010);
        _setInterest(lender1, 10010);
        assertEq(lender0.borrowBalance(address(account)), 200.2e18);
        assertEq(lender1.borrowBalance(address(account)), 20.02e18);

        account.warn(1 << 32);
        skip(LIQUIDATION_GRACE_PERIOD + 170 seconds);

        // MARK: actual command
        account.liquidate(this, abi.encode(uint256(0)), closeFactor, (1 << 32));

        assertEq(lender0.borrowBalance(address(account)), 0);
        assertEq(lender1.borrowBalance(address(account)), 0);
        assertEq(asset0.balanceOf(address(account)), 0.558652822916151063e18);
        assertEq(asset1.balanceOf(address(account)), 0.055865282291615107e18);
        assertEq(account.slot0(), uint256(0x800000000000f0f0f0f0f0f0f0f0000000000000000000000000000000000000));
    }

    function test_spec_repayDAIAndETHWithUniswapPosition() public {
        uint16 closeFactor = 10000;
        // give the account 1 DAI and 0.1 ETH
        deal(address(asset0), address(account), 1.1e18);
        deal(address(asset1), address(account), 0.1e18);

        // borrow 200 DAI and 20 ETH
        bytes memory data = abi.encode(Action.BORROW, 200e18, 20e18);
        account.modify(this, data, (1 << 32));

        // create a small Uniswap position
        data = abi.encode(Action.UNI_DEPOSIT, 0, 0);
        account.modify(this, data, (1 << 32));

        assertEq(lender0.borrowBalance(address(account)), 200e18);
        assertEq(lender1.borrowBalance(address(account)), 20e18);

        vm.expectRevert(bytes("Aloe: healthy"));
        account.warn(1 << 32);

        _setInterest(lender0, 10010);
        _setInterest(lender1, 10010);
        assertEq(lender0.borrowBalance(address(account)), 200.2e18);
        assertEq(lender1.borrowBalance(address(account)), 20.02e18);

        account.warn(1 << 32);
        skip(LIQUIDATION_GRACE_PERIOD + 170 seconds);

        // MARK: actual command
        account.liquidate(this, abi.encode(uint256(0)), closeFactor, (1 << 32));

        assertEq(lender0.borrowBalance(address(account)), 0);
        assertEq(lender1.borrowBalance(address(account)), 0);
        assertEq(asset0.balanceOf(address(account)), 559450576288129311);
        assertEq(asset1.balanceOf(address(account)), 55917238107366481);

        (uint128 liquidity, , , , ) = pool.positions(
            keccak256(abi.encodePacked(address(account), int24(-75600), int24(-75540)))
        );
        assertEq(liquidity, 0);
        assertEq(account.slot0(), uint256(0x800000000000f0f0f0f0f0f0f0f0000000000000000000000000000000000000));
    }

    /// forge-config: default.fuzz.runs = 16
    function test_fuzz_interestTriggerRepayDAIUsingSwap(uint16 closeFactor) public {
        closeFactor = uint16(bound(closeFactor, 1, 10000));

        // give the account 1 WETH
        deal(address(asset1), address(account), 1e18);

        uint256 debt = 1595e18;

        // borrow `debt` DAI
        bytes memory data = abi.encode(Action.BORROW, debt, 0);
        account.modify(this, data, (1 << 32));

        assertEq(lender0.borrowBalance(address(account)), debt);
        assertEq(asset0.balanceOf(address(account)), debt);
        assertEq(asset1.balanceOf(address(account)), 1e18);

        // withdraw `debt` DAI
        data = abi.encode(Action.WITHDRAW, debt, 0);
        account.modify(this, data, (1 << 32));

        assertEq(asset0.balanceOf(address(account)), 0);

        vm.expectRevert(bytes("Aloe: healthy"));
        account.warn(1 << 32);

        _setInterest(lender0, 10010);
        debt = lender0.borrowBalance(address(account));
        assertLe(debt - (1595e18 * 10010) / 10000, 1);

        // Disable warn() requirement by setting auctionTime
        uint256 warnTime = block.timestamp - LIQUIDATION_GRACE_PERIOD - TIME_OF_5_PERCENT;
        vm.store(
            address(account),
            bytes32(uint256(0)),
            bytes32(uint256(warnTime << 208))
        );

        (Prices memory prices, , , ) = account.getPrices(1 << 32);
        uint256 price = Math.mulDiv(prices.c, prices.c, Q96);
        uint256 assets1 = Math.mulDiv(debt, price, Q96);
        assets1 += assets1 / LIQUIDATION_INCENTIVE;
        assets1 = (assets1 * closeFactor) / 10000;

        // MARK: actual command
        data = abi.encode(assets1);
        account.liquidate(this, data, closeFactor, (1 << 32));

        assertLe(lender0.borrowBalance(address(account)) - (debt - (debt * closeFactor) / 10000), 1);
        assertGt(asset1.balanceOf(address(this)), 0);
        if (closeFactor <= TERMINATING_CLOSE_FACTOR) {
            assertEq(account.slot0(), uint256(0x8000000000000000000000000000000000000000000000000000000000000000) + (warnTime << 208));
        }
    }

    /// forge-config: default.fuzz.runs = 16
    function test_fuzz_cannotReenterLiquidate(uint256 closeFactor) public {
        closeFactor = bound(closeFactor, 1, 10000);

        // give the account 1 WETH
        deal(address(asset1), address(account), 1e18);

        uint256 debt = 1595e18;

        // borrow `debt` DAI
        bytes memory data = abi.encode(Action.BORROW, debt, 0);
        account.modify(this, data, (1 << 32));

        // withdraw `debt` DAI
        data = abi.encode(Action.WITHDRAW, debt, 0);
        account.modify(this, data, (1 << 32));

        _setInterest(lender0, 10010);
        debt = (debt * 10010) / 10000;

        // Disable warn() requirement by setting auctionTime
        vm.store(
            address(account),
            bytes32(uint256(0)),
            bytes32(uint256((block.timestamp - LIQUIDATION_GRACE_PERIOD - TIME_OF_5_PERCENT) << 208))
        );

        (Prices memory prices, , , ) = account.getPrices(1 << 32);
        uint256 price = Math.mulDiv(prices.c, prices.c, Q96);
        uint256 incentive1 = Math.mulDiv(debt / LIQUIDATION_INCENTIVE, price, Q96);
        uint256 assets1 = Math.mulDiv((debt * closeFactor) / 10000, price, Q96) + (incentive1 * closeFactor) / 10000;

        vm.expectRevert();
        data = abi.encode(type(uint256).max); // Special value that we're using to tell our test callback to try to re-enter
        account.liquidate(this, data, closeFactor, (1 << 32));

        // MARK: actual command
        data = abi.encode(assets1, false);
        account.liquidate(this, data, closeFactor, (1 << 32));
    }

    /// forge-config: default.fuzz.runs = 16
    function test_fuzz_interestTriggerRepayETHUsingSwap(uint8 scale, uint256 closeFactor) public {
        // These tests are forked, so we don't want to spam the RPC with too many fuzzing values
        closeFactor = bound(closeFactor, 1, 10000);

        (Prices memory prices, , , ) = account.getPrices(1 << 32);
        uint256 borrow1 = 1e18 * ((scale % 4) + 1); // Same concern here
        {
            uint256 effectiveLiabilities1 = borrow1 + borrow1 / 200 + borrow1 / 20;
            uint256 margin0 = Math.mulDiv(effectiveLiabilities1, Q96, Math.mulDiv(prices.a, prices.a, Q96));
            // give the account its margin
            deal(address(asset0), address(account), margin0 + 1);
        }

        // borrow ETH
        bytes memory data = abi.encode(Action.BORROW, 0, borrow1);
        account.modify(this, data, (1 << 32));

        assertEq(lender1.borrowBalance(address(account)), borrow1);
        assertEq(asset1.balanceOf(address(account)), borrow1);

        // withdraw ETH
        data = abi.encode(Action.WITHDRAW, 0, borrow1);
        account.modify(this, data, (1 << 32));

        assertEq(asset1.balanceOf(address(account)), 0);

        vm.expectRevert(bytes("Aloe: healthy"));
        account.warn(1 << 32);

        _setInterest(lender1, 10010);
        borrow1 = (borrow1 * 10010) / 10000;
        assertEq(lender1.borrowBalance(address(account)), borrow1);

        // Disable warn() requirement by setting auctionTime
        vm.store(
            address(account),
            bytes32(uint256(0)),
            bytes32(uint256((block.timestamp - LIQUIDATION_GRACE_PERIOD - TIME_OF_5_PERCENT) << 208))
        );

        uint256 price = Math.mulDiv(prices.c, prices.c, Q96);
        uint256 incentive1 = borrow1 / LIQUIDATION_INCENTIVE;
        uint256 assets0 = Math.mulDiv(((borrow1 + incentive1) * closeFactor) / 10000, Q96, price);

        // MARK: actual command
        data = abi.encode(assets0);
        account.liquidate(this, data, closeFactor, (1 << 32));

        assertApproxEqAbs(lender1.borrowBalance(address(account)), borrow1 - (borrow1 * closeFactor) / 10000, 1);
        assertGt(asset0.balanceOf(address(this)), 0);
    }

    function test_spec_priceTriggerRepayDAIUsingSwap() public {
        uint16 closeFactor = 10000;

        (Prices memory prices, , , ) = account.getPrices(1 << 32);
        uint256 borrow0 = 1000e18;
        {
            uint256 effectiveLiabilities0 = borrow0 + borrow0 / 20 + borrow0 / 200;
            uint256 margin1 = Math.mulDiv(effectiveLiabilities0, Math.mulDiv(prices.b, prices.b, Q96), Q96);
            // give the account its margin
            deal(address(asset1), address(account), margin1 + 1);
        }

        // borrow DAI
        bytes memory data = abi.encode(Action.BORROW, borrow0, 0);
        account.modify(this, data, (1 << 32));

        assertEq(lender0.borrowBalance(address(account)), borrow0);
        assertEq(asset0.balanceOf(address(account)), borrow0);

        // withdraw DAI
        data = abi.encode(Action.WITHDRAW, borrow0, 0);
        account.modify(this, data, (1 << 32));

        assertEq(asset0.balanceOf(address(account)), 0);

        vm.expectRevert(bytes("Aloe: healthy"));
        account.warn(1 << 32);

        // increase price of DAI by 1 tick
        {
            uint32[] memory t = new uint32[](3);
            t[0] = 3600;
            t[1] = 1800;
            t[2] = 0;
            (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s) = pool.observe(t);
            int24 newTick = TickMath.getTickAtSqrtRatio(prices.c) + 1;
            tickCumulatives[0] = 0;
            tickCumulatives[1] = int56(newTick) * 1800;
            tickCumulatives[2] = int56(newTick) * 3600;
            vm.mockCall(
                address(pool),
                abi.encodeWithSelector(pool.observe.selector),
                abi.encode(tickCumulatives, secondsPerLiquidityCumulativeX128s)
            );
        }

        // Disable warn() requirement by setting auctionTime
        vm.store(
            address(account),
            bytes32(uint256(0)),
            bytes32(uint256((block.timestamp - LIQUIDATION_GRACE_PERIOD - TIME_OF_5_PERCENT) << 208))
        );

        (prices, , , ) = account.getPrices(1 << 32);

        uint256 price = Math.mulDiv(prices.c, prices.c, Q96);
        uint256 assets1 = Math.mulDiv((borrow0 * closeFactor) / 10000, price, Q96);
        assets1 += assets1 / LIQUIDATION_INCENTIVE;

        // MARK: actual command
        data = abi.encode(assets1);
        account.liquidate(this, data, closeFactor, (1 << 32));

        assertLe(lender0.borrowBalance(address(account)) - (borrow0 - (borrow0 * closeFactor) / 10000), 1);
        assertGt(asset1.balanceOf(address(this)), 0);
    }

    function test_spec_warnDoesProtect() public {
        uint16 closeFactor = 10000;

        (Prices memory prices, , , ) = account.getPrices(1 << 32);
        uint256 borrow0 = 1000e18;
        {
            uint256 effectiveLiabilities0 = borrow0 + borrow0 / 20 + borrow0 / 200;
            uint256 margin1 = Math.mulDiv(effectiveLiabilities0, Math.mulDiv(prices.b, prices.b, Q96), Q96);
            // give the account its margin
            deal(address(asset1), address(account), margin1 + 1);
        }

        // borrow DAI
        bytes memory data = abi.encode(Action.BORROW, borrow0, 0);
        account.modify(this, data, (1 << 32));

        // withdraw DAI
        data = abi.encode(Action.WITHDRAW, borrow0, 0);
        account.modify(this, data, (1 << 32));

        vm.expectRevert(bytes("Aloe: healthy"));
        account.warn(1 << 32);

        // increase price of DAI by 1 tick
        {
            uint32[] memory t = new uint32[](3);
            t[0] = 3600;
            t[1] = 1800;
            t[2] = 0;
            (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s) = pool.observe(t);
            int24 newTick = TickMath.getTickAtSqrtRatio(prices.c) + 1;
            tickCumulatives[0] = 0;
            tickCumulatives[1] = int56(newTick) * 1800;
            tickCumulatives[2] = int56(newTick) * 3600;
            vm.mockCall(
                address(pool),
                abi.encodeWithSelector(pool.observe.selector),
                abi.encode(tickCumulatives, secondsPerLiquidityCumulativeX128s)
            );
        }

        vm.expectRevert();
        account.liquidate(this, bytes(""), 10000, 1 << 32);

        account.warn(1 << 32);

        vm.expectRevert(bytes("Aloe: grace"));
        account.liquidate(this, bytes(""), 10000, 1 << 32);

        skip(LIQUIDATION_GRACE_PERIOD - 1);

        vm.expectRevert(bytes("Aloe: grace"));
        account.liquidate(this, bytes(""), 10000, 1 << 32);

        skip(TIME_OF_5_PERCENT + 1);
        borrow0 = lender0.borrowBalance(address(account));

        (prices, , , ) = account.getPrices(1 << 32);

        uint256 price = Math.mulDiv(prices.c, prices.c, Q96);
        uint256 assets1 = Math.mulDiv((borrow0 * closeFactor) / 10000, price, Q96);
        assets1 += assets1 / LIQUIDATION_INCENTIVE;

        // MARK: actual command
        data = abi.encode(assets1);
        account.liquidate(this, data, closeFactor, (1 << 32));

        uint40 unleashLiquidationTime = uint40((account.slot0() >> 208) % (1 << 40));
        assertEq(unleashLiquidationTime, 0);
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
            account.uniswapDeposit(-75600, -75540, 200000000000000000);
            positions = zip([-75600, -75540, 0, 0, 0, 0]);
        }

        positions |= 0xf0f0f0f0f0f0f0f0 << 144;
    }

    // ILiquidator
    receive() external payable {}

    function callback(bytes calldata data, address, AuctionAmounts memory amounts) external {
        int256 x = int256(amounts.out0) - int256(amounts.repay0);
        int256 y = int256(amounts.out1) - int256(amounts.repay1);

        if (x >= 0 && y >= 0) {
            // Don't need to do anything here
        } else if (y < 0) {
            pool.swap(address(this), true, y, TickMath.MIN_SQRT_RATIO + 1, bytes(""));
        } else if (x < 0) {
            pool.swap(address(this), false, x, TickMath.MAX_SQRT_RATIO - 1, bytes(""));
        } else {
            // Can't do much unless we want to donate
        }

        if (amounts.repay0 > 0) asset0.transfer(address(lender0), amounts.repay0);
        if (amounts.repay1 > 0) asset1.transfer(address(lender1), amounts.repay1);

        // checking that out amounts match expectations
        uint256 expected = abi.decode(data, (uint256));
        // special case where we test reentrancy
        if (expected == type(uint256).max) {
            Borrower(payable(msg.sender)).liquidate(this, data, 1, (1 << 32));
        } else if (expected > 0) {
            assertApproxEqRel(x > 0 ? amounts.out0 : amounts.out1, expected, 0.0001e18);
        }
    }

    // IUniswapV3SwapCallback
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata) external {
        if (amount0Delta > 0) asset0.transfer(msg.sender, uint256(amount0Delta));
        if (amount1Delta > 0) asset1.transfer(msg.sender, uint256(amount1Delta));
    }

    // Factory mock
    function getParameters(IUniswapV3Pool) external pure returns (uint248 ante, uint8 nSigma) {
        ante = DEFAULT_ANTE;
        nSigma = DEFAULT_N_SIGMA;
    }

    // (helpers)
    function _setInterest(Lender lender, uint256 amount) private {
        bytes32 ID = bytes32(uint256(1));
        uint256 slot1 = uint256(vm.load(address(lender), ID));

        uint256 borrowBase = slot1 % (1 << 184);
        uint256 borrowIndex = slot1 >> 184;

        uint256 newSlot1 = borrowBase + (((borrowIndex * amount) / 10_000) << 184);
        vm.store(address(lender), ID, bytes32(newSlot1));
    }
}
