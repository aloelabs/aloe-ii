// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "forge-std/Script.sol";

import {Factory} from "aloe-ii-core/Factory.sol";

import {BorrowerLens} from "src/BorrowerLens.sol";
import {BorrowManager} from "src/BorrowManager.sol";
import {FrontendManager} from "src/FrontendManager.sol";
import {LenderLens} from "src/LenderLens.sol";
import {Router} from "src/Router.sol";

Factory constant FACTORY = Factory(0xa8a74E40d62CA77D9469E219794F9E56789c8612);

contract DeployScript is Script {
    function run() external {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        new BorrowerLens();
        new BorrowManager(FACTORY);
        new FrontendManager(FACTORY);
        new LenderLens();
        new Router();

        vm.stopBroadcast();
    }
}
