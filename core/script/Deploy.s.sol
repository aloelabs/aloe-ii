// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import "forge-std/Script.sol";

import {Factory, IUniswapV3Pool} from "../src/Factory.sol";
import {RateModel} from "../src/RateModel.sol";

contract DeployScript is Script {
    function run() external {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        RateModel rateModel = new RateModel();
        Factory factory = new Factory(rateModel);

        // Create some markets to kick things off
        factory.createMarket(IUniswapV3Pool(0xfBe57C73A82171A773D3328F1b563296151be515));
        factory.createMarket(IUniswapV3Pool(0xc0A1c271efD6D6325D5db33db5e7cF42A715CD12));

        vm.stopBroadcast();
    }
}
