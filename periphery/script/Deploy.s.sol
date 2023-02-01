// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import "forge-std/Script.sol";

import {Factory} from "aloe-ii-core/Factory.sol";

import {BorrowerLens} from "src/BorrowerLens.sol";
import {FrontendManager} from "src/FrontendManager.sol";
import {LenderLens} from "src/LenderLens.sol";
import {Router} from "src/Router.sol";

Factory constant ALOE_II_FACTORY = Factory(0x315980E4a137633952917a656ECEBa74c8f39768);
bytes32 constant TAG = bytes32(uint256(0xA10EBE1A));

contract DeployScript is Script {
    function run() external {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        new BorrowerLens{salt: TAG}();
        new FrontendManager{salt: TAG}(ALOE_II_FACTORY);
        new LenderLens{salt: TAG}();
        new Router{salt: TAG}();

        vm.stopBroadcast();
    }
}
