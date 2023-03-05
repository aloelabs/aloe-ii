// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {IUniswapV3Pool} from "v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {OracleUpdateHelper} from "src/helpers/OracleUpdateHelper.sol";

import {KeeperScript} from "./Keeper.s.sol";

contract UpdateOracleScript is KeeperScript {
    OracleUpdateHelper constant HELPER = OracleUpdateHelper(0x7dd9752f882d404717DaF52e9Ff3d1dE2aAccc4a);

    function run() external {
        vm.createSelectFork(vm.rpcUrl("optimism"));
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        HELPER.update(poolsOptimism);
        vm.stopBroadcast();

        vm.createSelectFork(vm.rpcUrl("arbitrum"));
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        HELPER.update(poolsArbitrum);
        vm.stopBroadcast();
    }
}
