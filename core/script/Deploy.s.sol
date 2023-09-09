// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import "forge-std/Script.sol";

import {Factory, ERC20} from "src/Factory.sol";
import {Lender} from "src/Lender.sol";
import {RateModel} from "src/RateModel.sol";
import {VolatilityOracle} from "src/VolatilityOracle.sol";

bytes32 constant TAG = bytes32(uint256(0xA10EBE1A));
address constant GOVERNOR = address(0);
address constant RESERVE = address(0);

contract DeployScript is Script {
    function run() external {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        VolatilityOracle oracle = new VolatilityOracle{salt: TAG}();
        RateModel rateModel = new RateModel{salt: TAG}();
        /*Factory factory =*/ new Factory{salt: TAG}({
            governor: GOVERNOR,
            reserve: RESERVE,
            oracle: oracle,
            defaultRateModel: rateModel
        });

        vm.stopBroadcast();
    }
}
