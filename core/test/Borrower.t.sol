// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";
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
import {zip} from "src/libraries/Positions.sol";
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

contract AttackingManager is IManager {
    function callback(bytes calldata data, address, uint208) external override returns (uint208) {
        Borrower borrower = Borrower(payable(msg.sender));

        (int24 lower, uint128 liquidity) = abi.decode(data, (int24, uint128));

        borrower.UNISWAP_POOL().mint(msg.sender, lower, lower + 10, liquidity, abi.encode(borrower));
        return zip([lower, lower + 10, 0, 0, 0, 0]);
    }

    function uniswapV3MintCallback(uint256 amount0, uint256, bytes calldata data) external {
        Borrower borrower = abi.decode(data, (Borrower));

        uint256 balance0 = borrower.TOKEN0().balanceOf(address(borrower));
        borrower.transfer(balance0, 0, msg.sender);
        borrower.borrow(amount0 - balance0, 0, msg.sender);
    }
}

contract Liquidator is ILiquidator {
    receive() external payable {}

    function callback(bytes calldata data, address, AuctionAmounts memory amounts) external {
        (bool check, uint256 o0, uint256 o1, uint256 r0, uint256 r1) = abi.decode(
            data,
            (bool, uint256, uint256, uint256, uint256)
        );
        if (check) {
            bool a = o0 <= amounts.out0 && o0 + 20 >= amounts.out0;
            bool b = o1 <= amounts.out1 && o1 + 20 >= amounts.out1;
            bool c = r0 <= amounts.repay0 && r0 + 10 >= amounts.repay0;
            bool d = r1 <= amounts.repay1 && r1 + 10 >= amounts.repay1;

            if (a && b && c && d) revert("AuctionAmounts matched!");
            console2.log(o0, amounts.out0);
            console2.log(o1, amounts.out1);
            console2.log(r0, amounts.repay0);
            console2.log(r1, amounts.repay1);
            revert("AuctionAmounts mismatch");
        }

        int256 x = int256(amounts.out0) - int256(amounts.repay0);
        int256 y = int256(amounts.out1) - int256(amounts.repay1);

        IUniswapV3Pool pool = Borrower(payable(msg.sender)).UNISWAP_POOL();
        ERC20 asset0 = Borrower(payable(msg.sender)).TOKEN0();
        ERC20 asset1 = Borrower(payable(msg.sender)).TOKEN1();
        address lender0 = address(Borrower(payable(msg.sender)).LENDER0());
        address lender1 = address(Borrower(payable(msg.sender)).LENDER1());

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
    Liquidator liquidator;

    int256[] private _swapAmounts;
    bool private _recordSwapAmounts;

    receive() external payable {}

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"), 15_348_451);

        VolatilityOracle oracle = new VolatilityOracle();
        RateModel rateModel = new RateModel();
        factory = new FatFactory(address(0), address(0), oracle, rateModel);

        factory.createMarket(pool);
        (lender0, lender1, impl) = factory.getMarket(pool);
        account = factory.createBorrower(pool, address(this), bytes12(0));
        liquidator = new Liquidator();

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
        vm.makePersistent(address(liquidator));

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

    function test_liquidateRequiresValidCloseFactor(
        ILiquidator callee,
        bytes memory data,
        uint256 closeFactor,
        uint40 oracleSeed
    ) external {
        if (closeFactor <= 10000) {
            vm.selectFork(0);
            vm.store(address(account), bytes32(uint256(0)), bytes32(uint256(block.timestamp << 208)));

            deal(address(asset1), address(account), 1);

            vm.expectRevert(bytes("Aloe: zero impact"));
            account.liquidate(callee, data, 0, 1 << 32);
            return;
        }

        vm.expectRevert(bytes("Aloe: close"));
        account.liquidate(callee, data, closeFactor, oracleSeed);
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
        (Prices memory pricesA, bool seemsLegitA, , ) = account.getPrices(1 << 32);
        (Prices memory pricesB, bool seemsLegitB, , ) = account.getPrices(oracleSeed);

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

        (Prices memory pricesA, , , ) = account.getPrices(1 << 32);

        vm.mockCall(
            address(factory),
            abi.encodeCall(factory.getParameters, (pool)),
            abi.encode(uint208(0), uint8(80), uint8(12), uint32(0))
        );

        (Prices memory pricesB, , , ) = account.getPrices(1 << 32);

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

    function test_cannotWarnEmptyAccount() external {
        vm.selectFork(0);

        vm.expectRevert(bytes("Aloe: healthy"));
        account.warn(1 << 32);
    }

    function test_cannotLiquidateWithoutWarning(
        ILiquidator callee,
        bytes memory data,
        uint256 closeFactor,
        uint40 oracleSeed
    ) external {
        closeFactor = (closeFactor % 10000) + 1;

        vm.expectRevert(bytes(""));
        account.liquidate(callee, data, closeFactor, oracleSeed);

        vm.store(address(account), bytes32(uint256(0)), bytes32(uint256(block.timestamp << 208)));

        vm.mockCallRevert(address(factory), abi.encodeCall(factory.getParameters, (pool)), bytes("abcdefg"));
        vm.expectRevert(bytes("abcdefg"));
        account.liquidate(callee, data, closeFactor, oracleSeed);
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

        (Prices memory prices, , , uint208 ante) = account.getPrices(1 << 32);

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

        (Prices memory prices, , , uint208 ante) = account.getPrices(1 << 32);

        uint256 collateral0 = 1000e6;
        uint256 borrow1 = mulDiv128((collateral0 * (ltvMin ? LTV_MIN : LTV_MAX)) / 1e12, square(prices.c));

        deal(address(asset0), address(account), collateral0);
        deal(address(asset1), address(lender1), 10 * borrow1);
        deal(address(account), ante);
        lender1.deposit(10 * borrow1, address(this));

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

        (Prices memory prices, , , uint208 ante) = account.getPrices(1 << 32);

        uint256 collateral1 = 1 ether;
        uint256 borrow0 = Math.mulDiv((collateral1 * (ltvMin ? LTV_MIN : LTV_MAX)) / 1e12, 1 << 128, square(prices.c));
        borrow0 -= 2;

        deal(address(asset1), address(account), collateral1 + 1);
        deal(address(asset0), address(lender0), 10 * borrow0);
        deal(address(account), ante);
        lender0.deposit(10 * borrow0, address(this));

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
        (Prices memory prices, bool seemsLegit, , ) = account.getPrices(1 << 32);
        assertTrue(seemsLegit);

        _assertPercentDiffApproxEq(prices.a, prices.c, 0.0505e9, 1000); // 1 - (PROBE_SQRT_SCALER_MIN/1e12)^-2
        _assertPercentDiffApproxEq(prices.b, prices.c, 53185887, 1000); // (PROBE_SQRT_SCALER_MIN/1e12)^2 - 1

        _manipulateTWAP(20, upwards ? 205 : 130, upwards);

        // After manipulation, prices should be sus at min IV / max LTV
        vm.clearMockedCalls();
        _mockIV(account.ORACLE(), pool, 0);
        (prices, seemsLegit, , ) = account.getPrices(1 << 32);
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
        (Prices memory prices, bool seemsLegit, , ) = account.getPrices(1 << 32);
        assertTrue(seemsLegit);

        _assertPercentDiffApproxEq(prices.a, prices.c, 0.8945e9, 1000); // 1 - (PROBE_SQRT_SCALER_MAX/1e12)^-2
        _assertPercentDiffApproxEq(prices.b, prices.c, 8.478672985e9, 1000); // (PROBE_SQRT_SCALER_MAX/1e12)^2 - 1

        _manipulateTWAP(20, 3700, upwards);

        // After manipulation, prices should be sus at min IV / max LTV
        vm.clearMockedCalls();
        _mockIV(account.ORACLE(), pool, type(uint128).max);
        (prices, seemsLegit, , ) = account.getPrices(1 << 32);
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
                              LIQUIDATION
    //////////////////////////////////////////////////////////////*/

    uint256[] private liquidationTimes = [
        0 minutes,
        2 minutes,
        5 minutes,
        5 minutes + 12 seconds,
        5 minutes + 24 seconds,
        5 minutes + 36 seconds,
        5 minutes + 48 seconds,
        6 minutes,
        7 minutes,
        5 minutes + 168 seconds,
        8 minutes,
        9 minutes,
        10 minutes,
        5 minutes + 1 days,
        5 minutes + 2 days,
        5 minutes + 5 days,
        7 days
    ];

    uint256[] private liquidationIncentives = [
        0,
        0,
        0,
        0.415240559229e12,
        0.606056042223e12,
        0.715682709971e12,
        0.786848126590e12,
        0.836772585073e12,
        0.958397119151e12,
        0.999929300389e12,
        1.007204752788e12,
        1.033528701917e12,
        1.050000037841e12,
        1.149634653251e12,
        1.189774687552e12,
        1.550340596798e12,
        1000000e12
    ];

    function test_liquidateToken0Token0(uint256 closeFactor) external {
        closeFactor = bound(closeFactor, 1, 10_000);
        vm.selectFork(0);

        // Minimize IV, maximize LTV
        _mockIV(account.ORACLE(), pool, 0);

        // Prepare lender0 to be borrowed from
        deal(address(asset0), address(lender0), 10000e6);
        lender0.deposit(10000e6, address(0));

        uint256 collateral0 = 100e6;
        uint256 borrow0 = 99.50248e6;

        // Give the account 100e6 token0 collateral and borrow 99e6 token0
        deal(address(asset0), address(account), collateral0);
        deal(address(account), DEFAULT_ANTE);
        bytes memory data = abi.encode(borrow0, 0, true);
        account.modify(this, data, 1 << 32);

        // Accrue interest so the account is unhealthy
        uint256 inflation = 10001;
        _setInterest(lender0, inflation);

        account.warn(1 << 32);
        uint256 snapshot = vm.snapshot();

        for (uint256 i; i < liquidationTimes.length; i++) {
            skip(liquidationTimes[i]);
            borrow0 = lender0.borrowBalance(address(account));

            if (i < 2) {
                data = abi.encode(false, 0, 0, 0, 0);
                vm.expectRevert(bytes("Aloe: grace"));
                account.liquidate(liquidator, data, closeFactor, 1 << 32);
            } else {
                uint256 out0Expected = (borrow0 * liquidationIncentives[i] * closeFactor) / 1e16;
                if (out0Expected > collateral0) {
                    out0Expected = collateral0;
                }
                uint256 repay0Expected = (borrow0 * closeFactor) / 10_000;

                data = abi.encode(true, out0Expected, 0, repay0Expected, 0);
                vm.expectRevert(bytes("AuctionAmounts matched!"));
                account.liquidate(liquidator, data, closeFactor, 1 << 32);
            }

            vm.revertTo(snapshot);
        }
    }

    function test_liquidateToken1Token1(uint256 closeFactor) external {
        closeFactor = bound(closeFactor, 1, 10_000);
        vm.selectFork(0);

        // Minimize IV, maximize LTV
        _mockIV(account.ORACLE(), pool, 0);

        // Prepare lender1 to be borrowed from
        deal(address(asset1), address(lender1), 10000e18);
        lender1.deposit(10000e18, address(0));

        uint256 collateral1 = 10e18;
        uint256 borrow1 = 9.950248e18;

        // Give the account 10e18 token1 collateral and borrow 9.9e18 token1
        deal(address(asset1), address(account), collateral1);
        deal(address(account), DEFAULT_ANTE);
        bytes memory data = abi.encode(0, borrow1, true);
        account.modify(this, data, 1 << 32);

        // Accrue interest so the account is unhealthy
        uint256 inflation = 10001;
        _setInterest(lender1, inflation);

        account.warn(1 << 32);
        uint256 snapshot = vm.snapshot();

        for (uint256 i; i < liquidationTimes.length; i++) {
            skip(liquidationTimes[i]);
            borrow1 = lender1.borrowBalance(address(account));

            if (i < 2) {
                data = abi.encode(false, 0, 0, 0, 0);
                vm.expectRevert(bytes("Aloe: grace"));
                account.liquidate(liquidator, data, closeFactor, 1 << 32);
            } else {
                uint256 out1Expected = (borrow1 * liquidationIncentives[i] * closeFactor) / 1e16;
                if (out1Expected > collateral1) {
                    out1Expected = collateral1;
                }
                uint256 repay1Expected = (borrow1 * closeFactor) / 10_000;

                data = abi.encode(true, 0, out1Expected, 0, repay1Expected);
                vm.expectRevert(bytes("AuctionAmounts matched!"));
                account.liquidate(liquidator, data, closeFactor, 1 << 32);
            }

            vm.revertTo(snapshot);
        }
    }

    /*//////////////////////////////////////////////////////////////
                         UNISWAP DEPOSIT ATTACK
    //////////////////////////////////////////////////////////////*/

    function test_uniswapDepositAttack() external {
        vm.selectFork(0);

        uint160 sqrtPrice1000 = 2.5054144838e33;
        uint160 sqrtPrice2000 = uint160(vm.envOr("sqrtPrice", uint256(1.7715955711e33)));

        // Start price at $1000 per ETH
        _manipulateTWAP(300, 13000, true);
        _swapTo(sqrtPrice1000);

        // Maximize LTV
        _mockIV(account.ORACLE(), pool, 0);

        {
            (Prices memory prices, , , ) = account.getPrices(1 << 32);
            (uint160 current, , , , , , ) = pool.slot0();
            console2.log("Initial State ($1000):");
            console2.log("-> sqrtPrice  TWAP:", prices.c);
            console2.log("-> sqrtPrice slot0:", current);
        }

        // Manipulate instantaneous price to $2000 per ETH
        // (TWAP doesn't change)
        _recordSwapAmounts = true;
        _swapTo(sqrtPrice2000);
        _recordSwapAmounts = false;

        int24 lower;
        {
            (Prices memory prices, , , ) = account.getPrices(1 << 32);
            (uint160 current, int24 tick, , , , , ) = pool.slot0();
            console2.log("\nSwapping {1} USDC for {2} WETH to push price to $2000");
            console2.log("(1) ", _swapAmounts[0] / 1e6);
            console2.log("(2) ", _swapAmounts[1] / 1e18);
            console2.log("After 1st Swap:");
            console2.log("-> sqrtPrice  TWAP:", prices.c);
            console2.log("-> sqrtPrice slot0:", current);
            console2.log("-> tick slot0:", tick);

            lower = TickMath.ceil(tick, 10);
        }

        // Make 10M USDC available for borrowing
        deal(address(asset0), address(lender0), 10_000_000 * 1e6);
        lender0.deposit(10_000_000 * 1e6, address(1));

        // Collateralize account with 100k USDC
        deal(address(asset0), address(account), 100_000 * 1e6);
        IManager manager = new AttackingManager();

        // Solve for the largest, thinnest Uniswap position possible
        uint128 L;
        {
            uint128 l = 1;
            uint128 r = 100e18;
            uint256 snapshot = vm.snapshot();

            for (uint256 i; i < 70; i++) {
                L = (l + r) / 2;

                bytes memory data = abi.encodeCall(account.modify, (manager, abi.encode(lower, L), 1 << 32));
                (bool success, ) = address(account).call{value: 0.01 ether}(data);

                if (success) l = L;
                else r = L;
                vm.revertTo(snapshot);
            }
        }

        // Create the largest, thinnest Uniswap position possible, just below the manipulated tick
        // --> Prove that this is the maximum amount
        vm.expectRevert(bytes("Aloe: unhealthy"));
        account.modify{value: 0.01 ether}(manager, abi.encode(lower, L + 1), 1 << 32);
        // --> Execute
        account.modify{value: 0.01 ether}(manager, abi.encode(lower, L + 0), 1 << 32);

        {
            uint256 borrows0 = account.LENDER0().borrowBalance(address(account));
            (uint256 current, , , , , , ) = pool.slot0();
            (uint256 usdc, ) = LiquidityAmounts.getAmountsForLiquidity(
                uint160(current),
                TickMath.getSqrtRatioAtTick(lower),
                TickMath.getSqrtRatioAtTick(lower + 10),
                L
            );
            console2.log("\nBalance Sheet:");
            console2.log("->", 100_000, "USDC upfront capital");
            console2.log("->", borrows0 / 1e6, "USDC borrowed");
            console2.log("->", usdc / 1e6, "USDC in Uniswap position");
            console2.log("-> Approx. leverage:", 100 + (100 * borrows0) / (100_000 * 1e6), "/ 100");
        }

        // Manipulate instantaneous price to back to $1000 per ETH
        // (TWAP doesn't change)
        _recordSwapAmounts = true;
        _swapTo(sqrtPrice1000);
        _recordSwapAmounts = false;

        {
            (Prices memory prices, , , ) = account.getPrices(1 << 32);
            (uint160 current, , , , , , ) = pool.slot0();
            console2.log("\nSwapping {1} WETH for {2} USDC to push price back to $1000");
            console2.log("(1) ", _swapAmounts[3] / 1e18);
            console2.log("(2) ", _swapAmounts[2] / 1e6);
            console2.log("After 2nd Swap:");
            console2.log("-> sqrtPrice  TWAP:", prices.c);
            console2.log("-> sqrtPrice slot0:", current);
        }

        // If this call succeeds, we know the account is healthy
        account.modify(this, abi.encode(0, 0, false), 1 << 32);

        {
            uint256 borrows0 = account.LENDER0().borrowBalance(address(account));
            (uint256 current, , , , , , ) = pool.slot0();
            (, uint256 eth) = LiquidityAmounts.getAmountsForLiquidity(
                uint160(current),
                TickMath.getSqrtRatioAtTick(lower),
                TickMath.getSqrtRatioAtTick(lower + 10),
                L
            );
            console2.log("\nBalance Sheet (still healthy!):");
            console2.log("->", 100_000, "USDC upfront capital");
            console2.log("->", borrows0 / 1e6, "USDC borrowed");
            console2.log("->", eth / 1e18, "ETH in Uniswap position");

            current = ((current * current) >> 96) * 1e6;

            int256 swapDiff0 = -_swapAmounts[2] - _swapAmounts[0];
            int256 swapDiff1 = -_swapAmounts[3] - _swapAmounts[1];
            console2.log("\nOn their swaps, attacker gained:");
            console2.log("-> USDC:", swapDiff0 / 1e6);
            console2.log("-> WETH:", swapDiff1 / 1e18);
            console2.log("-> (dollar value) ", swapDiff0 / 1e6 + (swapDiff1 * (1 << 96)) / int256(current));
            console2.log("In their Borrower, attacker gained:");
            console2.log("-> USDC:", -int256(borrows0 / 1e6 + 100_000));
            console2.log("-> WETH:", eth / 1e18);
            console2.log("-> (dollar value) ", int256((eth << 96) / current) - int256(borrows0 / 1e6 + 100_000));
        }
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function _setInterest(Lender lender, uint256 bips) private {
        bytes32 ID = bytes32(uint256(1));
        uint256 slot1 = uint256(vm.load(address(lender), ID));

        uint256 borrowBase = slot1 % (1 << 184);
        uint256 borrowIndex = ((slot1 >> 184) * bips) / 10_000;

        uint256 newSlot1 = borrowBase + (borrowIndex << 184);
        vm.store(address(lender), ID, bytes32(newSlot1));
    }

    function _swapTo(uint160 sqrtPriceX96) private {
        (uint160 current, , , , , , ) = pool.slot0();
        bool upwards = sqrtPriceX96 > current;

        int256 amountIn = upwards ? type(int256).min : type(int256).max;
        pool.swap(address(this), !upwards, amountIn, sqrtPriceX96, "");

        (current, , , , , , ) = pool.slot0();
        assertEq(current, sqrtPriceX96);
    }

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
        assertApproxEqAbs(currentTick, targetTick, 1);

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
        if (_recordSwapAmounts) {
            _swapAmounts.push(amount0Delta);
            _swapAmounts.push(amount1Delta);
        }
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
