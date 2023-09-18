// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import {IUniswapV3SwapCallback} from "v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";

import {
    DEFAULT_ANTE,
    DEFAULT_N_SIGMA,
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
        factory = new Factory(address(0), address(0), oracle, rateModel);

        factory.createMarket(pool);
        (lender0, lender1, impl) = factory.getMarket(pool);
        account = Borrower(factory.createBorrower(pool, address(this)));

        // Warmup storage
        pool.slot0();

        // vm.makePersistent([
        //     address(pool),
        //     address(asset0),
        //     address(asset1),
        //     address(factory),
        //     address(lender0),
        //     address(lender1),
        //     address(account)
        // ]);
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

        // deal(address(account), DEFAULT_ANTE + 1);
    }

    function test_permissionsModify(
        address owner,
        address caller,
        IManager arg0,
        bytes calldata arg1,
        uint40 arg2
    ) external {
        vm.assume(owner != caller);

        Borrower borrower = Borrower(factory.createBorrower(pool, owner));

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
        // TODO:
    }

    function test_leverageMixed() external {
        // TODO:
    }

    function test_leverageInKind0() external {
        // TODO:
    }

    function test_leverageInKind1() external {
        // TODO:
    }

    function test_ltvMinCollateralMixed() external {
        // TODO:
    }

    function test_ltvMaxCollateralMixed() external {
        // TODO:
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

        account.modify(this, abi.encode(0, borrow1), 1 << 32);

        vm.expectRevert(bytes("Aloe: unhealthy"));
        account.modify(this, abi.encode(0, (borrow1 * 1) / 1_000_000), 1 << 32);
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

        uint256 collateral1 = 1e18;
        uint256 borrow0 = Math.mulDiv((collateral1 * (ltvMin ? LTV_MIN : LTV_MAX)) / 1e12, 1 << 128, square(prices.c));

        deal(address(asset1), address(account), collateral1);
        deal(address(asset0), address(lender0), 10 * borrow0);
        lender0.deposit(10 * borrow0, address(this));

        (uint216 ante, , , ) = factory.getParameters(pool);
        deal(address(account), ante);

        account.modify(this, abi.encode(borrow0, 0), 1 << 32);

        vm.expectRevert(bytes("Aloe: unhealthy"));
        account.modify(this, abi.encode((borrow0 * 1) / 1_000_000, 0), 1 << 32);
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

        _manipulateTWAP(20, 295, upwards); // 3% up/down

        // After manipulation by 3%, prices should be sus at min IV / max LTV
        vm.clearMockedCalls();
        _mockIV(account.ORACLE(), pool, 0);
        (prices, seemsLegit) = account.getPrices(1 << 32);
        assertFalse(seemsLegit);

        // NOTE: This 3% number is dependent on chain history. All that really matters
        // is that `seemsLegit` becomes false at a percentage *less* than (1 / LTV - 1).
        // In this case LTV is 90%, and 3% < 11.1%.

        // Manipulation shouldn't affect distance between probe prices
        _assertPercentDiffApproxEq(prices.a, prices.c, 0.0505e9, 1000); // 1 - (PROBE_SQRT_SCALER_MIN/1e12)^-2
        _assertPercentDiffApproxEq(prices.b, prices.c, 53185887, 1000); // (PROBE_SQRT_SCALER_MIN/1e12)^2 - 1

        // TODO: test pausing
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

        _manipulateTWAP(20, 3715, upwards); // 45% up/down

        // After manipulation by 45%, prices should be sus at min IV / max LTV
        vm.clearMockedCalls();
        _mockIV(account.ORACLE(), pool, type(uint128).max);
        (prices, seemsLegit) = account.getPrices(1 << 32);
        assertFalse(seemsLegit);

        // NOTE: This 45% number is dependent on chain history. All that really matters
        // is that `seemsLegit` becomes false at a percentage *less* than (1 / LTV - 1).
        // In this case LTV is 10%, and 45% < 900%.

        // Manipulation shouldn't affect distance between probe prices
        _assertPercentDiffApproxEq(prices.a, prices.c, 0.8945e9, 1000); // 1 - (PROBE_SQRT_SCALER_MAX/1e12)^-2
        _assertPercentDiffApproxEq(prices.b, prices.c, 8.478672985e9, 1000); // (PROBE_SQRT_SCALER_MAX/1e12)^2 - 1

        // TODO: test pausing
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

    // TODO: Test missing ante

    // function test_liquidateLogicBothAreZero(uint184 liabilities0, uint184 liabilities1) public {
    //     unchecked {
    //         bool a = liabilities0 == 0 && liabilities1 == 0;
    //         bool b = uint256(liabilities0) + uint256(liabilities1) == 0;
    //         assertEq(a, b);
    //     }
    // }

    // function test_empty() public {
    //     bytes memory data = abi.encode(0, 0, 0, 0, 0, 0);
    //     account.modify(this, data, (1 << 32));
    // }

    // function test_addMargin() public {
    //     // give this contract some tokens
    //     deal(address(asset0), address(this), 10e6);
    //     deal(address(asset1), address(this), 1e17);

    //     // add margin
    //     asset0.transfer(address(account), 10e6);
    //     asset1.transfer(address(account), 1e17);

    //     bytes memory data = abi.encode(0, 0, 0, 0, 0, 0);
    //     account.modify(this, data, (1 << 32));
    // }

    // function test_borrow() public {
    //     _prepareKitties();

    //     // give this contract some tokens
    //     deal(address(asset0), address(this), 10e6);
    //     deal(address(asset1), address(this), 1e17);

    //     // add margin
    //     asset0.transfer(address(account), 10e6);
    //     asset1.transfer(address(account), 1e17);

    //     bytes memory data = abi.encode(100e6, 1e18, 0, 0, 0, 0);
    //     account.modify(this, data, (1 << 32));

    //     assertEq(lender0.borrowBalance(address(account)), 100e6);
    //     assertEq(lender1.borrowBalance(address(account)), 1e18);
    //     assertEq(asset0.balanceOf(address(account)), 10e6 + 100e6);
    //     assertEq(asset1.balanceOf(address(account)), 1e17 + 1e18);
    // }

    // function test_repay() public {
    //     test_borrow();

    //     bytes memory data = abi.encode(0, 0, 40e6, 0.4e18, 0, 0);
    //     account.modify(this, data, (1 << 32));

    //     assertEq(lender0.borrowBalance(address(account)), 60e6);
    //     assertEq(lender1.borrowBalance(address(account)), 0.6e18);
    //     assertEq(asset0.balanceOf(address(account)), 10e6 + 60e6);
    //     assertEq(asset1.balanceOf(address(account)), 1e17 + 0.6e18);
    // }

    // function testFail_completelyInsolvent() public {
    //     test_borrow();

    //     skip(1 days);

    //     bytes memory data = abi.encode(0, 0, 0, 0, 10e6, 1e17);
    //     account.modify(this, data, (1 << 32));
    // }

    // function testFail_missingLiquidationIncentive() public {
    //     test_borrow();

    //     skip(1 days);

    //     lender0.accrueInterest();
    //     lender1.accrueInterest();

    //     uint256 liabilities0 = lender0.borrowBalance(address(account));
    //     uint256 liabilities1 = lender1.borrowBalance(address(account));
    //     uint256 assets0 = asset0.balanceOf(address(account));
    //     uint256 assets1 = asset1.balanceOf(address(account));

    //     bytes memory data = abi.encode(0, 0, 0, 0, assets0 - liabilities0, assets1 - liabilities1);
    //     account.modify(this, data, (1 << 32));
    // }

    // function test_barelySolvent() public {
    //     test_borrow();

    //     skip(1 days);

    //     lender0.accrueInterest();
    //     lender1.accrueInterest();

    //     uint256 liabilities0 = lender0.borrowBalance(address(account));
    //     uint256 liabilities1 = lender1.borrowBalance(address(account));
    //     uint256 assets0 = asset0.balanceOf(address(account));
    //     uint256 assets1 = asset1.balanceOf(address(account));

    //     bytes memory data = abi.encode(
    //         0,
    //         0,
    //         0,
    //         0,
    //         assets0 - ((liabilities0 * 1.005e8) / 1e8),
    //         assets1 - ((liabilities1 * 1.005e8) / 1e8)
    //     );
    //     account.modify(this, data, (1 << 32));
    // }

    // function _prepareKitties() private {
    //     address alice = makeAddr("alice");

    //     deal(address(asset0), address(lender0), 10000e6);
    //     lender0.deposit(10000e6, alice);

    //     deal(address(asset1), address(lender1), 3e18);
    //     lender1.deposit(3e18, alice);
    // }

    // function getParameters(IUniswapV3Pool) external pure returns (uint248 ante, uint8 nSigma) {
    //     ante = DEFAULT_ANTE;
    //     nSigma = DEFAULT_N_SIGMA;
    // }

    /*//////////////////////////////////////////////////////////////
                               CALLBACKS
    //////////////////////////////////////////////////////////////*/

    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata) external override {
        if (amount0Delta > 0) deal(address(asset0), msg.sender, asset0.balanceOf(msg.sender) + uint256(amount0Delta));
        if (amount1Delta > 0) deal(address(asset1), msg.sender, asset1.balanceOf(msg.sender) + uint256(amount1Delta));
    }

    function callback(bytes calldata data, address) external returns (uint144) {
        Borrower account_ = Borrower(payable(msg.sender));

        (uint256 amount0, uint256 amount1) = abi.decode(data, (uint256, uint256));

        account_.borrow(amount0, amount1, address(this));

        return 0;
    }
}
