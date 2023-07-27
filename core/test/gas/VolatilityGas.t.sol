// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import "src/VolatilityOracle.sol";

import {getSeed} from "../Utils.sol";

contract VolatilityGasTest is Test {
    uint256 constant START_BLOCK = 70_000_000;
    uint256 constant SIX_HOURS_LATER = 70_045_000;

    IUniswapV3Pool constant pool = IUniswapV3Pool(0x85149247691df622eaF1a8Bd0CaFd40BC45154a9);

    VolatilityOracle oracle;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("optimism"));
        vm.rollFork(START_BLOCK);

        oracle = new VolatilityOracle();
        oracle.prepare(pool);

        vm.makePersistent(address(oracle));
        vm.rollFork(SIX_HOURS_LATER);
    }

    function test_updateNoBinarySearch() public {
        vm.pauseGasMetering();
        uint32 seed = getSeed(pool);
        vm.resumeGasMetering();
        oracle.update(pool, seed);
    }

    function test_consult() public {
        vm.pauseGasMetering();
        uint32 seed = getSeed(pool);
        oracle.update(pool, seed);
        vm.resumeGasMetering();

        oracle.consult(pool, seed);
    }
}
