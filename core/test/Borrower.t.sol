// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import {IUniswapV3SwapCallback} from "v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";

import {
    DEFAULT_ANTE,
    DEFAULT_N_SIGMA,
    MAX_LEVERAGE,
    PROBE_SQRT_SCALER_MIN,
    PROBE_SQRT_SCALER_MAX,
    LTV_MIN,
    LTV_MAX,
    UNISWAP_AVG_WINDOW
} from "src/libraries/constants/Constants.sol";
import {square, mulDiv128} from "src/libraries/MulDiv.sol";
import {TickMath} from "src/libraries/TickMath.sol";

import "src/Borrower.sol";
import "src/Factory.sol";
import "src/Lender.sol";
import "src/RateModel.sol";
import {VolatilityOracle} from "src/VolatilityOracle.sol";

import {FatFactory} from "./Utils.sol";

contract ReenteringManager is IManager {
    function callback(bytes calldata data, address, uint208) external override returns (uint208) {
        (bool success, ) = msg.sender.call(data);
        require(success);
        return 0;
    }
}

contract BorrowerTest is Test, IManager, IUniswapV3SwapCallback {
    uint256 constant BLOCK_TIME = 12 seconds;

    ERC20 constant asset0 = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ERC20 constant asset1 = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IUniswapV3Pool constant pool = IUniswapV3Pool(0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640);

    Factory factory;
    Lender lender0;
    Lender lender1;
    Borrower impl;
    Borrower account;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"), 15_348_451);

        VolatilityOracle oracle = new VolatilityOracle();
        RateModel rateModel = new RateModel();
        factory = new FatFactory(address(0), address(0), oracle, rateModel);

        factory.createMarket(pool);
        (lender0, lender1, impl) = factory.getMarket(pool);
        account = factory.createBorrower(pool, address(this), bytes12(0));

        // Warmup storage
        pool.slot0();

        vm.makePersistent(address(asset0));
        vm.makePersistent(address(asset1));
        vm.makePersistent(address(pool));
        vm.makePersistent(address(factory));
        vm.makePersistent(address(factory.LENDER_IMPLEMENTATION()));
        vm.makePersistent(address(impl));
        vm.makePersistent(address(lender0));
        vm.makePersistent(address(lender1));
        vm.makePersistent(address(account));
        vm.makePersistent(address(oracle));
        vm.makePersistent(address(rateModel));

        string[] memory cmd = new string[](4);
        cmd[0] = "tmux";
        cmd[1] = "new-session";
        cmd[2] = "-d";
        cmd[3] = "anvil";
        vm.ffi(cmd);
        vm.createSelectFork(vm.rpcUrl("anvil"));
    }

    function test_stateMaskIsAddition(uint8 state) external {
        state = uint8(bound(state, 0, 127));
        assertEq(state | 0x80, state + 128);
        assertEq((state | 0x80) & 0x7f, state);
    }

    function test_permissionsModify(
        address owner,
        address caller,
        bytes12 salt,
        IManager arg0,
        bytes calldata arg1,
        uint40 arg2
    ) external {
        vm.assume(owner != caller);

        Borrower borrower = factory.createBorrower(pool, owner, salt);

        vm.prank(caller);
        vm.expectRevert(bytes("Aloe: only owner"));
        borrower.modify(arg0, arg1, arg2);
    }

    function test_permissionsMintCallback(address caller, uint256 arg0, uint256 arg1, bytes calldata arg2) external {
        vm.assume(caller != address(pool));

        vm.prank(caller);
        vm.expectRevert(bytes(""));
        account.uniswapV3MintCallback(arg0, arg1, arg2);

        vm.prank(address(pool));
        account.uniswapV3MintCallback(0, 0, "");
    }

    /// forge-config: default.fuzz.runs = 256
    function test_reentrancyLock(uint40 oracleSeed) external {
        ReenteringManager manager = new ReenteringManager();

        bytes[] memory lockedFunctions = new bytes[](3);
        lockedFunctions[0] = abi.encodeCall(Borrower.warn, (oracleSeed));
        lockedFunctions[1] = abi.encodeCall(Borrower.liquidate, (ILiquidator(payable(address(0))), "", 1, oracleSeed));
        lockedFunctions[2] = abi.encodeCall(Borrower.modify, (manager, "", oracleSeed));

        for (uint256 i = 0; i < lockedFunctions.length; i++) {
            vm.expectRevert(bytes(""));
            account.modify(manager, lockedFunctions[i], oracleSeed);
        }
    }

    function test_permissionsSubCommands() external {
        bytes[] memory subCommands = new bytes[](6);
        subCommands[0] = abi.encodeCall(Borrower.uniswapDeposit, (0, 0, 0));
        subCommands[1] = abi.encodeCall(Borrower.uniswapWithdraw, (0, 0, 0, address(0)));
        subCommands[2] = abi.encodeCall(Borrower.transfer, (0, 0, address(0)));
        subCommands[3] = abi.encodeCall(Borrower.borrow, (0, 0, address(0)));
        subCommands[4] = abi.encodeCall(Borrower.repay, (0, 0));
        subCommands[5] = abi.encodeCall(Borrower.withdrawAnte, payable(address(0)));

        for (uint256 i = 0; i < subCommands.length; i++) {
            vm.expectRevert(bytes(""));
            (bool success, ) = address(account).call(subCommands[i]);
            assertTrue(success);
        }

        uint256 slot0 = uint256(vm.load(address(account), bytes32(uint256(0))));
        slot0 += 2 << 248;
        vm.store(address(account), bytes32(uint256(0)), bytes32(slot0));

        for (uint256 i = 0; i < subCommands.length; i++) {
            if (i == 0) {
                // `uniswapDeposit` should call mint, but fail because args are 0
                vm.expectCall(address(pool), abi.encodeCall(pool.mint, (address(account), 0, 0, 0, "")), 1);
                (bool success, ) = address(account).call(subCommands[i]);
                assertFalse(success);
            } else if (i == 1) {
                // `uniswapWithdraw` should call burn, but fail because args are 0
                vm.expectCall(address(pool), abi.encodeCall(pool.burn, (0, 0, 0)), 1);
                (bool success, ) = address(account).call(subCommands[i]);
                assertFalse(success);
            } else {
                // All other sub-commands succeed as is
                (bool success, ) = address(account).call(subCommands[i]);
                assertTrue(success);
            }
        }
    }

    /// forge-config: default.fuzz.runs = 256
    function test_getPricesIsIndependentOfOracleSeed(uint40 oracleSeed) external {
        vm.selectFork(0);

        // `oracleSeed` shouldn't change result
        (Prices memory pricesA, bool seemsLegitA) = account.getPrices(1 << 32);
        (Prices memory pricesB, bool seemsLegitB) = account.getPrices(oracleSeed);

        assertEq(pricesB.a, pricesA.a);
        assertEq(pricesB.b, pricesA.b);
        assertEq(pricesB.c, pricesA.c);
        assertEq(seemsLegitB, seemsLegitA);
    }

    function test_getPricesDependsOnFactoryParameters() external {
        vm.selectFork(0);

        vm.mockCall(
            address(factory),
            abi.encodeCall(factory.getParameters, (pool)),
            abi.encode(uint208(0), uint8(40), uint8(12), uint32(0))
        );

        (Prices memory pricesA, ) = account.getPrices(1 << 32);

        vm.mockCall(
            address(factory),
            abi.encodeCall(factory.getParameters, (pool)),
            abi.encode(uint208(0), uint8(80), uint8(12), uint32(0))
        );

        (Prices memory pricesB, ) = account.getPrices(1 << 32);

        assertEq(pricesB.c, pricesA.c);
        assertLt(pricesB.a, pricesA.a);
        assertGt(pricesB.b, pricesA.b);
    }

    function test_needsAnte() external {
        vm.selectFork(0);

        uint256 collateral0 = 1000e6;
        uint256 borrow1 = 1;

        deal(address(asset0), address(account), collateral0);
        deal(address(asset1), address(lender1), 10 * borrow1);
        lender1.deposit(10 * borrow1, address(this));

        vm.expectRevert(bytes("Aloe: missing ante / sus price"));
        account.modify(this, abi.encode(0, borrow1, true), 1 << 32);

        (uint216 ante, , , ) = factory.getParameters(pool);
        deal(address(account), ante);

        account.modify(this, abi.encode(0, borrow1, true), 1 << 32);
    }

    function test_cannotWarnOrLiquidateEmptyAccount() external {
        vm.selectFork(0);

        vm.expectRevert(bytes("Aloe: healthy"));
        account.warn(1 << 32);

        vm.expectRevert(bytes("Aloe: healthy"));
        account.liquidate(ILiquidator(payable(address(0))), "", 1, 1 << 32);
    }

    function test_cannotBorrow0WithoutCollateral() external {
        vm.selectFork(0);

        uint256 borrow0 = 1;

        deal(address(asset0), address(lender0), 10 * borrow0);
        lender0.deposit(10 * borrow0, address(this));

        (uint216 ante, , , ) = factory.getParameters(pool);
        deal(address(account), ante);

        vm.expectRevert(bytes("Aloe: unhealthy"));
        account.modify(this, abi.encode(borrow0, 0, true), 1 << 32);
    }

    function test_cannotBorrow1WithoutCollateral() external {
        vm.selectFork(0);

        uint256 borrow1 = 1;

        deal(address(asset1), address(lender1), 10 * borrow1);
        lender1.deposit(10 * borrow1, address(this));

        (uint216 ante, , , ) = factory.getParameters(pool);
        deal(address(account), ante);

        vm.expectRevert(bytes("Aloe: unhealthy"));
        account.modify(this, abi.encode(0, borrow1, true), 1 << 32);
    }

    /// forge-config: default.fuzz.runs = 16
    function test_leverageInKind0(uint128 iv) external {
        vm.selectFork(0);
        _mockIV(account.ORACLE(), pool, iv);

        uint256 collateral0 = 1000e6;
        uint256 borrow0 = collateral0 * MAX_LEVERAGE;

        deal(address(asset0), address(account), collateral0);
        deal(address(asset1), address(account), 1); // easy way to eliminate impact of liabilities rounding up
        deal(address(asset0), address(lender0), 10 * borrow0);
        lender0.deposit(10 * borrow0, address(this));

        (uint216 ante, , , ) = factory.getParameters(pool);
        deal(address(account), ante);

        account.modify(this, abi.encode(borrow0, 0, false), 1 << 32);

        vm.expectRevert(bytes("Aloe: unhealthy"));
        account.modify(this, abi.encode(borrow0 / 1e9, 0, false), 1 << 32);
    }

    /// forge-config: default.fuzz.runs = 16
    function test_leverageInKind1(uint128 iv) external {
        vm.selectFork(0);
        _mockIV(account.ORACLE(), pool, iv);

        uint256 collateral1 = 1 ether;
        uint256 borrow1 = collateral1 * MAX_LEVERAGE;

        deal(address(asset1), address(account), collateral1);
        deal(address(asset1), address(lender1), 10 * borrow1);
        lender1.deposit(10 * borrow1, address(this));

        (uint216 ante, , , ) = factory.getParameters(pool);
        deal(address(account), ante);

        account.modify(this, abi.encode(0, borrow1, false), 1 << 32);

        vm.expectRevert(bytes("Aloe: unhealthy"));
        account.modify(this, abi.encode(0, borrow1 / 1e9, false), 1 << 32);
    }

    /*//////////////////////////////////////////////////////////////
                          LTV-COLLATERAL-MIXED
    //////////////////////////////////////////////////////////////*/

    /// forge-config: default.fuzz.runs = 16
    function test_ltvMinCollateralMixed(bool doBorrow0) external {
        _test_ltvCollateralMixed(true, doBorrow0);
    }

    /// forge-config: default.fuzz.runs = 16
    function test_ltvMaxCollateralMixed(bool doBorrow0) external {
        _test_ltvCollateralMixed(false, doBorrow0);
    }

    function _test_ltvCollateralMixed(bool ltvMin, bool doBorrow0) private {
        vm.selectFork(0);
        _mockIV(account.ORACLE(), pool, ltvMin ? type(uint128).max : 0);

        (Prices memory prices, ) = account.getPrices(1 << 32);

        uint256 collateral0 = 500e6;
        uint256 collateral1 = 0.5 ether;

        uint256 borrow0;
        uint256 borrow1;
        if (doBorrow0) {
            borrow0 =
                ((collateral0 * 1.05e18) / 1.055e18) +
                Math.mulDiv((collateral1 * (ltvMin ? LTV_MIN : LTV_MAX)) / 1e12, 1 << 128, square(prices.c));
            deal(address(asset0), address(lender0), 10 * borrow0);
            lender0.deposit(10 * borrow0, address(this));
        } else {
            borrow1 =
                ((collateral1 * 1.05e18) / 1.055e18) +
                mulDiv128((collateral0 * (ltvMin ? LTV_MIN : LTV_MAX)) / 1e12, square(prices.c));
            deal(address(asset1), address(lender1), 10 * borrow1);
            lender1.deposit(10 * borrow1, address(this));
        }

        deal(address(asset0), address(account), collateral0);
        deal(address(asset1), address(account), collateral1);

        (uint216 ante, , , ) = factory.getParameters(pool);
        deal(address(account), ante);

        account.modify(this, abi.encode(borrow0, borrow1, true), 1 << 32);

        if (doBorrow0) {
            vm.expectRevert(bytes("Aloe: unhealthy"));
            account.modify(this, abi.encode(borrow0 / 1_000_000, 0, true), 1 << 32);
        } else {
            vm.expectRevert(bytes("Aloe: unhealthy"));
            account.modify(this, abi.encode(0, borrow1 / 1_000_000, true), 1 << 32);
        }
    }

    /*//////////////////////////////////////////////////////////////
                            LTV-COLLATERAL0
    //////////////////////////////////////////////////////////////*/

    function test_ltvMinCollateral0() external {
        _test_ltvCollateral0(true);
    }

    function test_ltvMaxCollateral0() external {
        _test_ltvCollateral0(false);
    }

    function _test_ltvCollateral0(bool ltvMin) private {
        vm.selectFork(0);
        _mockIV(account.ORACLE(), pool, ltvMin ? type(uint128).max : 0);

        (Prices memory prices, ) = account.getPrices(1 << 32);

        uint256 collateral0 = 1000e6;
        uint256 borrow1 = mulDiv128((collateral0 * (ltvMin ? LTV_MIN : LTV_MAX)) / 1e12, square(prices.c));

        deal(address(asset0), address(account), collateral0);
        deal(address(asset1), address(lender1), 10 * borrow1);
        lender1.deposit(10 * borrow1, address(this));

        (uint216 ante, , , ) = factory.getParameters(pool);
        deal(address(account), ante);

        account.modify(this, abi.encode(0, borrow1, true), 1 << 32);

        vm.expectRevert(bytes("Aloe: unhealthy"));
        account.modify(this, abi.encode(0, borrow1 / 1_000_000, true), 1 << 32);
    }

    /*//////////////////////////////////////////////////////////////
                            LTV-COLLATERAL1
    //////////////////////////////////////////////////////////////*/

    function test_ltvMinCollateral1() external {
        _test_ltvCollateral1(true);
    }

    function test_ltvMaxCollateral1() external {
        _test_ltvCollateral1(false);
    }

    function _test_ltvCollateral1(bool ltvMin) private {
        vm.selectFork(0);
        _mockIV(account.ORACLE(), pool, ltvMin ? type(uint128).max : 0);

        (Prices memory prices, ) = account.getPrices(1 << 32);

        uint256 collateral1 = 1 ether;
        uint256 borrow0 = Math.mulDiv((collateral1 * (ltvMin ? LTV_MIN : LTV_MAX)) / 1e12, 1 << 128, square(prices.c));
        borrow0 -= 2;

        deal(address(asset1), address(account), collateral1 + 1);
        deal(address(asset0), address(lender0), 10 * borrow0);
        lender0.deposit(10 * borrow0, address(this));

        (uint216 ante, , , ) = factory.getParameters(pool);
        deal(address(account), ante);

        account.modify(this, abi.encode(borrow0, 0, true), 1 << 32);

        vm.expectRevert(bytes("Aloe: unhealthy"));
        account.modify(this, abi.encode(borrow0 / 1_000_000, 0, true), 1 << 32);
    }

    /*//////////////////////////////////////////////////////////////
                          MANIPULATION-MIN-IV
    //////////////////////////////////////////////////////////////*/

    function test_getPricesDetectsManipulationMinIVUp() external {
        _test_getPricesDetectsManipulationMinIV(true);
    }

    function test_getPricesDetectsManipulationMinIVDown() external {
        _test_getPricesDetectsManipulationMinIV(false);
    }

    function _test_getPricesDetectsManipulationMinIV(bool upwards) private {
        vm.selectFork(0);

        // Before manipulation, prices should seem legit, even at min IV / max LTV
        _mockIV(account.ORACLE(), pool, 0);
        (Prices memory prices, bool seemsLegit) = account.getPrices(1 << 32);
        assertTrue(seemsLegit);

        _assertPercentDiffApproxEq(prices.a, prices.c, 0.0505e9, 1000); // 1 - (PROBE_SQRT_SCALER_MIN/1e12)^-2
        _assertPercentDiffApproxEq(prices.b, prices.c, 53185887, 1000); // (PROBE_SQRT_SCALER_MIN/1e12)^2 - 1

        _manipulateTWAP(20, upwards ? 205 : 130, upwards);

        // After manipulation, prices should be sus at min IV / max LTV
        vm.clearMockedCalls();
        _mockIV(account.ORACLE(), pool, 0);
        (prices, seemsLegit) = account.getPrices(1 << 32);
        assertFalse(seemsLegit);

        // NOTE: The exact amount of manipulation is dependent on chain history. All that really
        // matters is that `seemsLegit` becomes false at a percentage *less* than (1 / LTV - 1).
        // In this case LTV is 90%, and 2% < 11.1%.

        // Manipulation shouldn't affect distance between probe prices
        _assertPercentDiffApproxEq(prices.a, prices.c, 0.0505e9, 1000); // 1 - (PROBE_SQRT_SCALER_MIN/1e12)^-2
        _assertPercentDiffApproxEq(prices.b, prices.c, 53185887, 1000); // (PROBE_SQRT_SCALER_MIN/1e12)^2 - 1

        factory.pause(pool, 1 << 32);
        (, , , uint32 pausedUntilTime) = factory.getParameters(pool);
        assertGt(pausedUntilTime, block.timestamp);
    }

    /*//////////////////////////////////////////////////////////////
                          MANIPULATION-MAX-IV
    //////////////////////////////////////////////////////////////*/

    function test_getPricesDetectsManipulationMaxIVUp() external {
        _test_getPricesDetectsManipulationMaxIV(true);
    }

    function test_getPricesDetectsManipulationMaxIVDown() external {
        _test_getPricesDetectsManipulationMaxIV(false);
    }

    function _test_getPricesDetectsManipulationMaxIV(bool upwards) private {
        vm.selectFork(0);

        // Before manipulation, prices should seem legit, even at min IV / max LTV
        _mockIV(account.ORACLE(), pool, type(uint128).max);
        (Prices memory prices, bool seemsLegit) = account.getPrices(1 << 32);
        assertTrue(seemsLegit);

        _assertPercentDiffApproxEq(prices.a, prices.c, 0.8945e9, 1000); // 1 - (PROBE_SQRT_SCALER_MAX/1e12)^-2
        _assertPercentDiffApproxEq(prices.b, prices.c, 8.478672985e9, 1000); // (PROBE_SQRT_SCALER_MAX/1e12)^2 - 1

        _manipulateTWAP(20, 3700, upwards);

        // After manipulation, prices should be sus at min IV / max LTV
        vm.clearMockedCalls();
        _mockIV(account.ORACLE(), pool, type(uint128).max);
        (prices, seemsLegit) = account.getPrices(1 << 32);
        assertFalse(seemsLegit);

        // NOTE: The exact amount of manipulation is dependent on chain history. All that really
        // matters is that `seemsLegit` becomes false at a percentage *less* than (1 / LTV - 1).
        // In this case LTV is 10%, and 45% < 900%.

        // Manipulation shouldn't affect distance between probe prices
        _assertPercentDiffApproxEq(prices.a, prices.c, 0.8945e9, 1000); // 1 - (PROBE_SQRT_SCALER_MAX/1e12)^-2
        _assertPercentDiffApproxEq(prices.b, prices.c, 8.478672985e9, 1000); // (PROBE_SQRT_SCALER_MAX/1e12)^2 - 1

        factory.pause(pool, 1 << 32);
        (, , , uint32 pausedUntilTime) = factory.getParameters(pool);
        assertGt(pausedUntilTime, block.timestamp);
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @dev `k` is the number of blocks to manipulate, and `d` is log(1 + percentChange) / log(1.0001)
    function _manipulateTWAP(uint256 k, uint256 d, bool upwards) private {
        uint256 ticks = (UNISWAP_AVG_WINDOW * d) / (k * BLOCK_TIME);
        uint256 nextBlock = block.number + (k + 1);
        uint256 nextTimestamp = block.timestamp + (k + 1) * BLOCK_TIME;

        (uint160 sqrtPrice, int24 currentTick, , , , , ) = pool.slot0();
        int24 targetTick;
        if (upwards) {
            targetTick = currentTick + int24(uint24(ticks));
        } else {
            targetTick = currentTick - int24(uint24(ticks));
        }
        uint160 sqrtPriceLimit = TickMath.getSqrtRatioAtTick(targetTick);

        int256 amountIn = upwards ? type(int256).min : type(int256).max;
        pool.swap(address(this), !upwards, amountIn, sqrtPriceLimit, "");

        (, currentTick, , , , , ) = pool.slot0();
        assertEq(currentTick, targetTick);

        vm.roll(nextBlock);
        vm.warp(nextTimestamp);

        amountIn = upwards ? type(int256).max : type(int256).min;
        pool.swap(address(this), upwards, amountIn, sqrtPrice, "");
    }

    function _mockIV(VolatilityOracle oracle, IUniswapV3Pool pool_, uint256 iv) private {
        (uint56 metric, uint160 sqrtMeanPrice, ) = oracle.consult(pool_, 1 << 32);

        vm.mockCall(
            address(oracle),
            abi.encodeCall(oracle.consult, (pool_, 1 << 32)),
            abi.encode(metric, sqrtMeanPrice, iv)
        );
    }

    function _assertPercentDiffApproxEq(uint160 sqrtPriceA, uint160 sqrtPriceB, uint256 expected, uint256 err) private {
        int256 priceA = int256(square(sqrtPriceA));
        int256 priceB = int256(square(sqrtPriceB));
        int256 percentDiff = ((priceA - priceB) * 1e9) / priceB;
        if (percentDiff < 0) percentDiff = -percentDiff;

        assertApproxEqAbs(uint256(percentDiff), expected, err);
    }

    /*//////////////////////////////////////////////////////////////
                               CALLBACKS
    //////////////////////////////////////////////////////////////*/

    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata) external override {
        if (amount0Delta > 0) deal(address(asset0), msg.sender, asset0.balanceOf(msg.sender) + uint256(amount0Delta));
        if (amount1Delta > 0) deal(address(asset1), msg.sender, asset1.balanceOf(msg.sender) + uint256(amount1Delta));
    }

    function callback(bytes calldata data, address, uint208) external returns (uint208) {
        Borrower account_ = Borrower(payable(msg.sender));

        (uint256 amount0, uint256 amount1, bool withdraw) = abi.decode(data, (uint256, uint256, bool));

        account_.borrow(amount0, amount1, withdraw ? address(this) : msg.sender);

        return 0;
    }
}
