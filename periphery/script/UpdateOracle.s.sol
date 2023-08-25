// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {IUniswapV3Pool} from "v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {OracleUpdateHelper} from "src/helpers/OracleUpdateHelper.sol";

import {KeeperScript} from "./Keeper.s.sol";

contract UpdateOracleScript is KeeperScript {
    function run() external {
        vm.createSelectFork(vm.rpcUrl("optimism"));
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        OracleUpdateHelper(0xB93d750Cc6CA3d1F494DC25e7375860feef74870).update(poolsOptimism);
        vm.stopBroadcast();

        vm.createSelectFork(vm.rpcUrl("arbitrum"));
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        OracleUpdateHelper(0xB93d750Cc6CA3d1F494DC25e7375860feef74870).update(poolsArbitrum);
        vm.stopBroadcast();

        vm.createSelectFork(vm.rpcUrl("base"));
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        OracleUpdateHelper(0x3C56D0B36Bfc486Eab4304Da6322b5A335552F55).update(poolsBase);
        vm.stopBroadcast();
    }
}
