// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

import "forge-std/Test.sol";

import "src/VolatilityOracle.sol";

contract VolatilityOracleTest is Test {
    using stdStorage for StdStorage;

    uint256 constant START_BLOCK = 70_000_000;

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
        vm.createSelectFork(vm.rpcUrl("optimism"), START_BLOCK);
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
            (uint256 index, uint256 time, uint256 oldIV, uint256 newIV) = oracle.lastWrites(pool);

            assertGt(gamma0, 0);
            assertGt(gamma1, 0);
            assertGt(fgg0, 0);
            assertGt(fgg1, 0);
            assertEq(fggTime, block.timestamp);
            assertEq(index, 0);
            assertEq(time, block.timestamp);
            assertEqDecimal(oldIV, IV_COLD_START, 12);
            assertEqDecimal(newIV, IV_COLD_START, 12);
        }

        vm.expectRevert(bytes("Aloe: cardinality"));
        oracle.prepare(IUniswapV3Pool(0xbf16ef186e715668AA29ceF57e2fD7f9D48AdFE6));
    }

    uint256[] weekBlocks = [
        16314442, // 01/01/23
        16364593,
        16414717,
        16464865,
        16514997,
        16565106, // 02/05/23
        16615200,
        16665143,
        16714917,
        16764702, // 03/05/23
        16814158,
        16863970,
        16913810,
        16963603, // 04/02/23
        17012926,
        17061640,
        17111224,
        17161077,
        17210866, // 05/07/23
        17260300,
        17309940,
        17359732,
        17409440, // 06/04/23
        17459071,
        17508877,
        17558704,
        17608537, // 07/02/23
        17658356,
        17708064,
        17758034,
        17808064,
        17858133, // 08/06/23
        17908161,
        17958178,
        18008217,
        18058185, // 09/03/23
        18108193,
        18157945,
        18207875,
        18257907, // 10/01/23
        18307977,
        18358000,
        18408050,
        18458055
    ];

    function test_historical_ETHUSDC() public {
        _test_historical(
            IUniswapV3Pool(0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640),
            0.0345e12,
            0xbe2fa84a9dc9b3744200a739246fcad3762e18a06020b4a5584b5623a1bef42f
        );
    }

    function test_historical_BTCUSDC() public {
        _test_historical(
            IUniswapV3Pool(0x99ac8cA7087fA4A2A1FB6357269965A2014ABc35),
            0.026e12,
            0x28c05b3a958d5487d5602d8e48154200a9bcc77d1a3c5189ea02ab1bd5ee2058
        );
    }

    function _test_historical(IUniswapV3Pool pool, uint256 init, bytes32 slot) private {
        vm.makePersistent(address(oracle));
        vm.createSelectFork(vm.rpcUrl("mainnet"), 16314442);
        oracle.prepare(pool);

        uint256 totalGas = 0;

        for (uint256 i = 0; i < weekBlocks.length; i++) {
            uint256 weekStartBlock = weekBlocks[i];

            for (uint256 j = 0; j < 12; j++) {
                uint256 currentBlock = weekStartBlock + ((j * 12 hours) / 12 seconds);
                vm.createSelectFork("mainnet", currentBlock);

                uint256 g = gasleft();
                (uint56 metric, uint160 sqrtPriceX96, uint256 iv) = oracle.update(pool, (1 << 32));
                totalGas += g - gasleft();

                if (i == 0 && j == 0) {
                    // uint256 k = stdstore
                    //     .target(address(oracle))
                    //     .sig("lastWrites(address)")
                    //     .with_key(address(pool))
                    //     .find();
                    // console2.log(k);

                    iv = init;
                    uint256 val = uint256(vm.load(address(oracle), slot));
                    vm.store(address(oracle), slot, bytes32(uint48(val) + (iv << 48) + (iv << 152)));
                }

                console2.log(block.timestamp, sqrtPriceX96, iv, metric);
            }
        }

        console2.log("avg gas to update oracle:", totalGas / (weekBlocks.length * 12));
    }

    function _prepareAllPools() private {
        uint256 count = pools.length;
        for (uint256 i = 0; i < count; i++) {
            IUniswapV3Pool pool = IUniswapV3Pool(pools[i]);
            oracle.prepare(pool);
        }
    }
}
