// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import "src/VolatilityOracle.sol";

contract VolatilityGasTest is Test {
    uint256 constant START_BLOCK = 60_533_513;
    uint256 constant ONE_HOUR_LATER = 60_568_200;

    IUniswapV3Pool constant pool = IUniswapV3Pool(0x03aF20bDAaFfB4cC0A521796a223f7D85e2aAc31);

    VolatilityOracle oracle;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("optimism"));
        vm.rollFork(START_BLOCK);

        oracle = new VolatilityOracle();
        oracle.prepare(pool);

        vm.makePersistent(address(oracle));
        vm.rollFork(ONE_HOUR_LATER);
    }

    function test_updateNoBinarySearch() public {
        oracle.update(pool);
    }

    function test_consult() public {
        vm.pauseGasMetering();
        oracle.update(pool);
        vm.resumeGasMetering();

        oracle.consult(pool);
    }
}
