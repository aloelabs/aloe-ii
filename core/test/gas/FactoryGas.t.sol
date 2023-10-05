// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import "src/Factory.sol";
import "src/RateModel.sol";

import {FatFactory} from "../Utils.sol";

contract FactoryGasTest is Test {
    IUniswapV3Pool constant poolA = IUniswapV3Pool(0xC2e9F25Be6257c210d7Adf0D4Cd6E3E881ba25f8);

    IUniswapV3Pool constant poolB = IUniswapV3Pool(0xCBCdF9626bC03E24f779434178A73a0B4bad62eD);

    Factory immutable factory;

    constructor() {
        vm.createSelectFork(vm.rpcUrl("mainnet"));
        vm.rollFork(15_348_451);

        factory = new FatFactory(
            address(0),
            address(0),
            new VolatilityOracle(),
            new RateModel()
        );
    }

    function setUp() public {
        factory.createMarket(poolB);
    }

    function test_createMarket() public {
        factory.createMarket(poolA);
    }

    function test_createBorrower() public {
        factory.createBorrower(poolB, address(this), bytes12(0));
    }
}
