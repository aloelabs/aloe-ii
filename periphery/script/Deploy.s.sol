// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import "forge-std/Script.sol";

import {Factory} from "aloe-ii-core/Factory.sol";

import {BorrowerLens} from "src/BorrowerLens.sol";
import {BorrowManager} from "src/BorrowManager.sol";
import {FrontendManager} from "src/FrontendManager.sol";
import {LenderLens} from "src/LenderLens.sol";
import {Router} from "src/Router.sol";

Factory constant FACTORY = Factory(address(0));

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
