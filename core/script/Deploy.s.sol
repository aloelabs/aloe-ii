// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import "forge-std/Script.sol";

import {Factory} from "../src/Factory.sol";
import {RateModel} from "../src/RateModel.sol";
import {VolatilityOracle} from "../src/VolatilityOracle.sol";

bytes32 constant TAG = bytes32(uint256(0xA10EBE1A));

contract DeployScript is Script {
    function run() external {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        VolatilityOracle oracle = new VolatilityOracle{salt: TAG}();
        RateModel rateModel = new RateModel{salt: TAG}();  
        /*Factory factory =*/ new Factory{salt: TAG}(oracle, rateModel);

        vm.stopBroadcast();
    }
}
