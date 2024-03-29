// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

import "forge-std/Test.sol";

import {Q32} from "src/libraries/constants/Q.sol";

import "src/libraries/Oracle.sol";

contract LibraryWrapper {
    function observe(IUniswapV3Pool pool, uint32 target, uint256 seed) external view returns (int56, uint160) {
        (, int24 tick, uint16 observationIndex, uint16 observationCardinality, , , ) = pool.slot0();
        {
            (, , , bool initialized) = pool.observations((observationIndex + 1) % observationCardinality);
            if (!initialized) observationCardinality = observationIndex + 1;
        }
        return Oracle.observe(pool, target, seed, tick, observationIndex, observationCardinality);
    }
}

contract OracleTest is Test {
    IUniswapV3Pool constant POOL = IUniswapV3Pool(0x85149247691df622eaF1a8Bd0CaFd40BC45154a9);

    // `POOL`'s oracle is fully populated in this block
    uint256 constant BLOCK_A = 70_000_000;
    // `POOL`'s oracle was expanded with some number of uninitialized entries, and `observationCardinalityNext`
    // was set. It has now reached the edge of initialized entries, increased `observationCardinality` to
    // `observationCardinalityNext`, and has started writing into the new, uninitialized entries.
    uint256 constant BLOCK_B = 10_800_600;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("optimism"), BLOCK_A);
    }

    function test_blockBHasDesiredQualities() public {
        vm.createSelectFork("optimism", BLOCK_B);

        (, , uint16 idx, uint16 cardinality, uint16 cardinalityNext, , ) = POOL.slot0();
        assertEq(cardinality, cardinalityNext);
        (, , , bool initialized) = POOL.observations(idx + 1);
        assertFalse(initialized);
    }

    /*//////////////////////////////////////////////////////////////
                              COMPARATIVE
    //////////////////////////////////////////////////////////////*/

    /// forge-config: default.fuzz.runs = 1024
    function test_comparative_observe(uint32 secondsAgo, uint256 seed, bool initializing) public {
        if (initializing) vm.createSelectFork("optimism", BLOCK_B);
        else vm.createSelectFork("optimism", BLOCK_A);

        (uint32 oldest, ) = _oldestAndNewest();
        secondsAgo = uint32(bound(secondsAgo, 0, block.timestamp - oldest));

        // Uniswap method
        uint32[] memory secondsAgos = new uint32[](1);
        secondsAgos[0] = secondsAgo;
        (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s) = POOL.observe(
            secondsAgos
        );
        int56 tickCumA = tickCumulatives[0];
        uint160 liqCumA = secondsPerLiquidityCumulativeX128s[0];

        // Our method
        LibraryWrapper wrapper = new LibraryWrapper();
        (int56 tickCumB, uint160 liqCumB) = wrapper.observe(POOL, uint32(block.timestamp - secondsAgo), seed % Q32);
        (int56 tickCumC, uint160 liqCumC) = wrapper.observe(POOL, uint32(block.timestamp - secondsAgo), seed);

        // Make sure they're the same
        assertEq(tickCumB, tickCumA);
        assertEq(tickCumC, tickCumA);
        assertEq(liqCumB, liqCumA);
        assertEq(liqCumC, liqCumA);
    }

    /// forge-config: default.fuzz.runs = 1024
    function test_comparative_observeOld(uint32 secondsAgo, uint256 seed, bool initializing) public {
        if (initializing) vm.createSelectFork("optimism", BLOCK_B);
        else vm.createSelectFork("optimism", BLOCK_A);

        (uint32 oldest, ) = _oldestAndNewest();
        secondsAgo = uint32(bound(secondsAgo, block.timestamp - oldest + 1, block.timestamp));

        // Uniswap method
        uint32[] memory secondsAgos = new uint32[](1);
        secondsAgos[0] = secondsAgo;
        vm.expectRevert(bytes("OLD"));
        POOL.observe(secondsAgos);

        // Our method (need to put it in wrapper for cheatcode to work right)
        LibraryWrapper wrapper = new LibraryWrapper();
        vm.expectRevert(bytes("OLD"));
        wrapper.observe(POOL, uint32(block.timestamp - secondsAgo), seed);
    }

    function test_comparative_observeCurrent() public {
        (, int24 tick, uint16 idx, , , , ) = POOL.slot0();
        uint128 liquidity = POOL.liquidity();

        // Uniswap method
        uint32[] memory secondsAgos = new uint32[](1);
        secondsAgos[0] = 0;
        (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s) = POOL.observe(
            secondsAgos
        );
        int56 tickCumA = tickCumulatives[0];
        uint160 liqCumA = secondsPerLiquidityCumulativeX128s[0];

        // Our method
        (int56 tickCumB, uint160 liqCumB) = _observeCurrent(tick, idx, liquidity);

        // Make sure they're the same
        assertEq(tickCumB, tickCumA);
        assertEq(liqCumB, liqCumA);
    }

    /*//////////////////////////////////////////////////////////////
                       GAS - CURRENT OBSERVATION
    //////////////////////////////////////////////////////////////*/

    function test_gas_currentObs_uniswap() public view {
        uint32[] memory secondsAgos = new uint32[](1);
        secondsAgos[0] = 0;
        POOL.observe(secondsAgos);
    }

    function test_gas_currentObs_oursA() public view {
        (, int24 tick, uint16 index, , , , ) = POOL.slot0();
        uint128 liquidity = POOL.liquidity();
        _observeCurrent(tick, index, liquidity);
    }

    function test_gas_currentObs_oursB() public view {
        (, int24 tick, uint16 index, uint16 cardinality, , , ) = POOL.slot0();
        unchecked {
            (, , , bool initialized) = POOL.observations((index + 1) % cardinality);
            if (!initialized) cardinality = index + 1;
        }
        Oracle.observe(POOL, uint32(block.timestamp), index, tick, index, cardinality);
    }

    /*//////////////////////////////////////////////////////////////
                      GAS - REALISTIC OBSERVATION
    //////////////////////////////////////////////////////////////*/

    function test_gas_realisticObs_uniswap() public view {
        uint32[] memory secondsAgos = new uint32[](3);
        secondsAgos[0] = 60 minutes;
        secondsAgos[1] = 30 minutes;
        secondsAgos[2] = 0;
        POOL.observe(secondsAgos);
    }

    function test_gas_realisticObs_oursA() public view {
        (, int24 tick, uint16 idx, uint16 cardinality, , , ) = POOL.slot0();
        unchecked {
            (, , , bool initialized) = POOL.observations((idx + 1) % cardinality);
            if (!initialized) cardinality = idx + 1;
        }
        uint128 liquidity = POOL.liquidity();

        _observeCurrent(tick, idx, liquidity);
        Oracle.observe(POOL, uint32(block.timestamp - 30 minutes), 178, tick, idx, cardinality);
        Oracle.observe(POOL, uint32(block.timestamp - 60 minutes), 112, tick, idx, cardinality);
    }

    function test_gas_realisticObs_oursB() public view {
        (, int24 tick, uint16 idx, uint16 cardinality, , , ) = POOL.slot0();
        unchecked {
            (, , , bool initialized) = POOL.observations((idx + 1) % cardinality);
            if (!initialized) cardinality = idx + 1;
        }

        Oracle.observe(POOL, uint32(block.timestamp), idx, tick, idx, cardinality);
        Oracle.observe(POOL, uint32(block.timestamp - 30 minutes), 178, tick, idx, cardinality);
        Oracle.observe(POOL, uint32(block.timestamp - 60 minutes), 112, tick, idx, cardinality);
    }

    /*//////////////////////////////////////////////////////////////
                        GAS - RANDOM OBSERVATION
    //////////////////////////////////////////////////////////////*/

    /// forge-config: default.fuzz.runs = 1024
    function test_gas_upToCurrentObs_uniswap(uint32 secondsAgo) public {
        vm.pauseGasMetering();
        {
            (uint32 oldest, ) = _oldestAndNewest();
            secondsAgo = uint32(bound(secondsAgo, 0, block.timestamp - oldest));
        }
        vm.resumeGasMetering();

        uint32[] memory secondsAgos = new uint32[](1);
        secondsAgos[0] = secondsAgo;
        POOL.observe(secondsAgos);
    }

    /// forge-config: default.fuzz.runs = 1024
    function test_gas_upToCurrentObs_ours(uint32 secondsAgo) public {
        vm.pauseGasMetering();

        uint256 seed;
        {
            (, , uint16 index, uint16 cardinality, , , ) = POOL.slot0();
            (uint32 oldest, ) = _oldestAndNewest();
            secondsAgo = uint32(bound(secondsAgo, 0, block.timestamp - oldest));

            uint32 target = uint32(block.timestamp - secondsAgo);
            while (true) {
                uint256 next = (seed + 1) % cardinality;
                (uint32 timeL, , , ) = POOL.observations(seed);
                (uint32 timeR, , , ) = POOL.observations(next);

                if (timeL <= target && target <= timeR) break;
                if (timeL <= target && seed == index) break;

                seed = next;
            }
        }

        LibraryWrapper wrapper = new LibraryWrapper();
        vm.resumeGasMetering();

        wrapper.observe(POOL, uint32(block.timestamp - secondsAgo), seed);
    }

    /// forge-config: default.fuzz.runs = 1024
    function test_gas_upToMostRecentObs_uniswap(uint32 secondsAgo) public {
        vm.pauseGasMetering();
        {
            (uint32 oldest, uint32 newest) = _oldestAndNewest();
            secondsAgo = uint32(bound(secondsAgo, block.timestamp - newest, block.timestamp - oldest));
        }
        vm.resumeGasMetering();

        uint32[] memory secondsAgos = new uint32[](1);
        secondsAgos[0] = secondsAgo;
        POOL.observe(secondsAgos);
    }

    /// forge-config: default.fuzz.runs = 1024
    function test_gas_upToMostRecentObsSeedExact_ours(uint32 secondsAgo) public {
        vm.pauseGasMetering();

        uint256 seed;
        {
            (, , , uint16 cardinality, , , ) = POOL.slot0();
            (uint32 oldest, uint32 newest) = _oldestAndNewest();
            secondsAgo = uint32(bound(secondsAgo, block.timestamp - newest, block.timestamp - oldest));

            uint32 target = uint32(block.timestamp - secondsAgo);
            while (true) {
                uint256 next = (seed + 1) % cardinality;
                (uint32 timeL, , , ) = POOL.observations(seed);
                (uint32 timeR, , , ) = POOL.observations(next);

                if (timeL <= target && target <= timeR) break;

                seed = next;
            }
        }

        LibraryWrapper wrapper = new LibraryWrapper();
        vm.resumeGasMetering();

        wrapper.observe(POOL, uint32(block.timestamp - secondsAgo), seed);
    }

    /// forge-config: default.fuzz.runs = 1024
    function test_gas_upToMostRecentObsSeedOffBy05_ours(uint32 secondsAgo) public {
        vm.pauseGasMetering();

        uint256 seed;
        {
            (, , , uint16 cardinality, , , ) = POOL.slot0();
            (uint32 oldest, uint32 newest) = _oldestAndNewest();
            secondsAgo = uint32(bound(secondsAgo, block.timestamp - newest, block.timestamp - oldest));

            uint32 target = uint32(block.timestamp - secondsAgo);
            while (true) {
                uint256 next = (seed + 1) % cardinality;
                (uint32 timeL, , , ) = POOL.observations(seed);
                (uint32 timeR, , , ) = POOL.observations(next);

                if (timeL <= target && target <= timeR) break;

                seed = next;
            }
            seed = (seed + cardinality - 5) % cardinality;
        }

        LibraryWrapper wrapper = new LibraryWrapper();
        vm.resumeGasMetering();

        wrapper.observe(POOL, uint32(block.timestamp - secondsAgo), seed);
    }

    /// forge-config: default.fuzz.runs = 1024
    function test_gas_upToMostRecentObsSeedOffBy10_ours(uint32 secondsAgo) public {
        vm.pauseGasMetering();

        uint256 seed;
        {
            (, , , uint16 cardinality, , , ) = POOL.slot0();
            (uint32 oldest, uint32 newest) = _oldestAndNewest();
            secondsAgo = uint32(bound(secondsAgo, block.timestamp - newest, block.timestamp - oldest));

            uint32 target = uint32(block.timestamp - secondsAgo);
            while (true) {
                uint256 next = (seed + 1) % cardinality;
                (uint32 timeL, , , ) = POOL.observations(seed);
                (uint32 timeR, , , ) = POOL.observations(next);

                if (timeL <= target && target <= timeR) break;

                seed = next;
            }
            seed = (seed + cardinality - 10) % cardinality;
        }

        LibraryWrapper wrapper = new LibraryWrapper();
        vm.resumeGasMetering();

        wrapper.observe(POOL, uint32(block.timestamp - secondsAgo), seed);
    }

    function _observeCurrent(
        int56 currentTick,
        uint16 observationIndex,
        uint128 liquidity
    ) private view returns (int56 tickCumulative, uint160 secondsPerLiquidityCumulativeX128) {
        uint32 timestamp;
        (timestamp, tickCumulative, secondsPerLiquidityCumulativeX128, ) = POOL.observations(observationIndex);

        if (timestamp != block.timestamp) {
            unchecked {
                uint56 delta = uint56(block.timestamp - timestamp);

                tickCumulative += currentTick * int56(delta);
                secondsPerLiquidityCumulativeX128 += (uint160(delta) << 128) / (liquidity > 0 ? liquidity : 1);
            }
        }
    }

    function _oldestAndNewest() private view returns (uint32 oldest, uint32 newest) {
        (, , uint16 observationIndex, uint16 observationCardinality, , , ) = POOL.slot0();

        // newest is easy
        (newest, , , ) = POOL.observations(observationIndex);

        // oldest depends on whether the next index is initialized or not
        bool init;
        (oldest, , , init) = POOL.observations((observationIndex + 1) % observationCardinality);
        if (!init) (oldest, , , ) = POOL.observations(0);
    }
}
