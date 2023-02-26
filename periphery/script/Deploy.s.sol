// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import "forge-std/Script.sol";

import {Factory} from "aloe-ii-core/Factory.sol";

import {BorrowerLens} from "src/BorrowerLens.sol";
import {LenderLens} from "src/LenderLens.sol";
import {Router} from "src/Router.sol";
import {FrontendManager} from "src/managers/FrontendManager.sol";
import {SimpleManager} from "src/managers/SimpleManager.sol";
import {UniswapNFTManager, INFTManager} from "src/managers/UniswapNFTManager.sol";
import {WithdrawManager} from "src/managers/WithdrawManager.sol";

Factory constant ALOE_II_FACTORY = Factory(0x95110C9806833d3D3C250112fac73c5A6f631E80);
INFTManager constant UNISWAP_NFT_MANAGER = INFTManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
bytes32 constant TAG = bytes32(uint256(0xA10EBE1A));

contract DeployScript is Script {
    function run() external {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        new BorrowerLens{salt: TAG}();
        new LenderLens{salt: TAG}();
        new Router{salt: TAG}();

        new FrontendManager{salt: TAG}(ALOE_II_FACTORY);
        new SimpleManager{salt: TAG}();
        new UniswapNFTManager{salt: TAG}(ALOE_II_FACTORY, UNISWAP_NFT_MANAGER);
        new WithdrawManager{salt: TAG}();

        vm.stopBroadcast();
    }
}
