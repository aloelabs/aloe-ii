// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import "src/VolatilityOracle.sol";

contract VolatilityOracleTest is Test {
    uint256 constant START_BLOCK = 70_000_000;
    uint256 constant SIX_HOURS_LATER = 70_045_000;
    uint256 constant TWELVE_HOURS_LATER = 70_090_000;

    uint256 constant BLOCKS_PER_SECOND = 2;

    VolatilityOracle oracle;

    address[] pools = [
        0x68F5C0A2DE713a54991E01858Fd27a3832401849, // WETH/OP
        0x85149247691df622eaF1a8Bd0CaFd40BC45154a9, // WETH/USDC
        0x03aF20bDAaFfB4cC0A521796a223f7D85e2aAc31, // WETH/DAI
        0x73B14a78a0D396C521f954532d43fd5fFe385216, // WETH/WBTC
        0x1C3140aB59d6cAf9fa7459C6f83D4B52ba881d36, // OP/USDC
        0x535541F1aa08416e69Dc4D610131099FA2Ae7222, // WETH/PERP
        0xF334F6104A179207DdaCfb41FA3567FEea8595C2 // WETH/LYRA
    ];

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("optimism"));
        vm.rollFork(START_BLOCK);

        oracle = new VolatilityOracle();
    }

    function test_spec_consultWithoutPreparation() public {
        uint256 count = pools.length;
        for (uint256 i = 0; i < count; i++) {
            IUniswapV3Pool pool = IUniswapV3Pool(pools[i]);

            (uint56 metric, uint160 price, uint256 iv) = oracle.consult(pool, (1 << 32));

            assertGt(metric, 0);
            assertGt(price, 0);
            assertEqDecimal(iv, 0, 12);
        }
    }

    function test_spec_updateWithoutPreparation() public {
        uint256 count = pools.length;
        for (uint256 i = 0; i < count; i++) {
            IUniswapV3Pool pool = IUniswapV3Pool(pools[i]);

            vm.expectRevert(bytes(""));
            oracle.update(pool, (1 << 32));
        }
    }

    function test_spec_prepare() public {
        uint256 count = pools.length;
        for (uint256 i = 0; i < count; i++) {
            IUniswapV3Pool pool = IUniswapV3Pool(pools[i]);

            oracle.prepare(pool);

            (uint256 gamma0, uint256 gamma1, ) = oracle.cachedMetadata(pool);
            (uint256 fgg0, uint256 fgg1, uint256 fggTime) = oracle.feeGrowthGlobals(pool, 0);
            (uint256 index, uint256 time, uint256 iv) = oracle.lastWrites(pool);

            assertGt(gamma0, 0);
            assertGt(gamma1, 0);
            assertGt(fgg0, 0);
            assertGt(fgg1, 0);
            assertEq(fggTime, block.timestamp);
            assertEq(index, 0);
            assertEq(time, block.timestamp);
            assertEqDecimal(iv, IV_COLD_START, 12);
        }

        vm.expectRevert(bytes("Aloe: cardinality"));
        oracle.prepare(IUniswapV3Pool(0xbf16ef186e715668AA29ceF57e2fD7f9D48AdFE6));
    }

    function test_spec_updateTooLate() public {
        _prepareAllPools();

        vm.makePersistent(address(oracle));
        vm.rollFork(TWELVE_HOURS_LATER);

        uint256 count = pools.length;
        for (uint256 i = 0; i < count; i++) {
            IUniswapV3Pool pool = IUniswapV3Pool(pools[i]);

            (uint256 index, uint256 time, uint256 ivOldExpected) = oracle.lastWrites(pool);
            assertEq(index, 0);
            assertGe(block.timestamp, time + 6 hours + 7.5 minutes);

            (, , uint256 ivOld) = oracle.consult(pool, (1 << 32));
            (, , uint256 ivNew) = oracle.update(pool, (1 << 32));

            assertEqDecimal(ivOld, ivOldExpected, 12);
            assertEqDecimal(ivNew, ivOld, 12);

            (index, time, ivNew) = oracle.lastWrites(pool);

            assertEqDecimal(ivNew, ivOld, 12);
            assertEq(index, 1);
            assertEq(time, block.timestamp);
        }
    }

    function test_spec_updateTooSoon() public {
        _prepareAllPools();

        vm.makePersistent(address(oracle));
        vm.rollFork(START_BLOCK + 16 seconds / 2 seconds); // roll forward approx. 16 seconds, assuming 2 seconds per block

        uint256 count = pools.length;
        for (uint256 i = 0; i < count; i++) {
            IUniswapV3Pool pool = IUniswapV3Pool(pools[i]);

            (uint256 index, uint256 time, uint256 ivOld) = oracle.lastWrites(pool);
            assertEq(index, 0);
            assertLt(block.timestamp, time + FEE_GROWTH_SAMPLE_PERIOD);

            vm.record();
            (, , uint256 ivNew) = oracle.update(pool, (1 << 32));
            (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(address(oracle));

            assertEqDecimal(ivNew, ivOld, 12);
            assertEq(reads.length, 1);
            assertEq(writes.length, 0);
        }
    }

    function test_spec_updateNormal() public {
        _prepareAllPools();

        vm.makePersistent(address(oracle));
        vm.rollFork(SIX_HOURS_LATER);

        uint256 count = pools.length;
        for (uint256 i = 0; i < count; i++) {
            IUniswapV3Pool pool = IUniswapV3Pool(pools[i]);

            vm.record();
            (, , uint256 iv) = oracle.update(pool, (1 << 32));
            (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(address(oracle));

            assertEq(reads.length, 10);
            assertEq(writes.length, 4);

            (uint256 index, uint256 time, uint256 ivStored) = oracle.lastWrites(pool);

            assertEq(index, 1);
            assertEq(time, block.timestamp);
            assertEq(ivStored, iv);
        }
    }

    function test_historical_updateSequenceETHUSDC() public {
        uint256 currentBlock = 109019618;
        vm.createSelectFork("optimism", currentBlock);

        IUniswapV3Pool pool = IUniswapV3Pool(pools[1]); // WETH/USDC
        oracle = new VolatilityOracle();
        oracle.prepare(pool);

        vm.makePersistent(address(oracle));

        (uint256 currentIndex, uint256 currentTime, uint256 currentIV) = oracle.lastWrites(pool);

        uint256 initialTime = currentTime;

        for (uint256 i = 0; i < 48; i++) {
            console2.log(currentTime, currentIV);

            uint256 interval = FEE_GROWTH_SAMPLE_PERIOD * 2;
            currentBlock += BLOCKS_PER_SECOND * interval;
            vm.createSelectFork("optimism", currentBlock);

            (, , uint256 ivWritten) = oracle.update(pool, (1 << 32));
            (uint256 newIndex, uint256 newTime, uint256 ivStored) = oracle.lastWrites(pool);

            assertEqDecimal(ivStored, ivWritten, 12);
            assertEq(newIndex, (currentIndex + 1) % FEE_GROWTH_ARRAY_LENGTH);

            uint256 maxChange = IV_CHANGE_PER_UPDATE;
            assertLe(ivWritten, currentIV + maxChange);
            assertGe(ivWritten + maxChange, currentIV);

            currentIndex = newIndex;
            currentTime = newTime;
            currentIV = ivWritten;
        }

        console2.log("Time Simulated:", currentTime - initialTime, "seconds");
    }

    function test_historical_ETHUSDC() public {
        IUniswapV3Pool pool = IUniswapV3Pool(pools[1]); // WETH/USDC
        oracle.prepare(pool);
        vm.makePersistent(address(oracle));

        uint256 currentBlock = START_BLOCK;
        uint256 totalGas = 0;

        for (uint256 i = 0; i < 600; i++) {
            currentBlock += (1 + (uint256(blockhash(block.number)) % 3)) * 7200;
            vm.createSelectFork("optimism", currentBlock);

            uint256 g = gasleft();
            (uint56 metric, uint160 sqrtPriceX96, uint256 iv) = oracle.update(pool, (1 << 32));
            totalGas += g - gasleft();

            console2.log(block.timestamp, sqrtPriceX96, iv, metric);
        }

        console2.log("avg gas to update oracle:", totalGas / 600);
    }

    function _prepareAllPools() private {
        uint256 count = pools.length;
        for (uint256 i = 0; i < count; i++) {
            IUniswapV3Pool pool = IUniswapV3Pool(pools[i]);
            oracle.prepare(pool);
        }
    }
}
