// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import "forge-std/Script.sol";

import {Factory} from "aloe-ii-core/Factory.sol";

import {BorrowerLens} from "src/BorrowerLens.sol";
import {LenderLens} from "src/LenderLens.sol";
import {Router, IPermit2} from "src/Router.sol";
import {LenderAccrualHelper} from "src/helpers/LenderAccrualHelper.sol";
import {OracleUpdateHelper} from "src/helpers/OracleUpdateHelper.sol";
import {FrontendManager} from "src/managers/FrontendManager.sol";
import {SimpleManager} from "src/managers/SimpleManager.sol";
import {UniswapNFTManager, INFTManager} from "src/managers/UniswapNFTManager.sol";
import {WithdrawManager} from "src/managers/WithdrawManager.sol";

IPermit2 constant PERMIT2 = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);

Factory constant ALOE_II_FACTORY = Factory(0x95110C9806833d3D3C250112fac73c5A6f631E80);
INFTManager constant UNISWAP_NFT_MANAGER = INFTManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
bytes32 constant TAG = bytes32(uint256(0xA10EBE1A2));

contract DeployScript is Script {
    string[] chains = ["optimism", "arbitrum", "goerli"];

    function run() external {
        for (uint256 i = 0; i < chains.length; i++) {
            vm.createSelectFork(vm.rpcUrl(chains[i]));
            vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

            new BorrowerLens{salt: TAG}();
            new LenderLens{salt: TAG}();
            new Router{salt: TAG}(PERMIT2);

            new LenderAccrualHelper{salt: TAG}();
            new OracleUpdateHelper{salt: TAG}(ALOE_II_FACTORY.ORACLE());

            new FrontendManager{salt: TAG}(ALOE_II_FACTORY);
            new SimpleManager{salt: TAG}();
            new UniswapNFTManager{salt: TAG}(ALOE_II_FACTORY, UNISWAP_NFT_MANAGER);
            new WithdrawManager{salt: TAG}();

            vm.stopBroadcast();
        }
    }
}
