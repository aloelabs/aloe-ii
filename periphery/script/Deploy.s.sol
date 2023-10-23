// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import "forge-std/Script.sol";

import {Factory} from "aloe-ii-core/Factory.sol";

import {BorrowerLens} from "src/BorrowerLens.sol";
import {LenderLens} from "src/LenderLens.sol";
import {Router, IPermit2} from "src/Router.sol";

import {BorrowerNFT, IBorrowerURISource} from "src/borrower-nft/BorrowerNFT.sol";

import {BoostManager} from "src/managers/BoostManager.sol";
import {FrontendManager} from "src/managers/FrontendManager.sol";
import {SimpleManager} from "src/managers/SimpleManager.sol";
import {UniswapNFTManager, INFTManager} from "src/managers/UniswapNFTManager.sol";

bytes32 constant TAG = bytes32(uint256(0xA10EBE1A3));

contract DeployScript is Script {
    string[] chains = ["optimism", "arbitrum", "base"];

    Factory[] factories = [
        Factory(0x000000F00500f8BC2a68D90723AC00fCf4AD4b4D),
        Factory(0x000000F00500f8BC2a68D90723AC00fCf4AD4b4D),
        Factory(0x00000006d6C0519e0eB953CFfeb7007e5200680B)
    ];

    IBorrowerURISource[] uriSources = [
        IBorrowerURISource(0x0000000000000000000000000000000000000000),
        IBorrowerURISource(0x0000000000000000000000000000000000000000),
        IBorrowerURISource(0x0000000000000000000000000000000000000000)
    ];

    INFTManager[] uniswapNfts = [
        INFTManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88),
        INFTManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88),
        INFTManager(0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1)
    ];

    IPermit2[] permit2s = [
        IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3),
        IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3),
        IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3)
    ];

    function run() external {
        for (uint256 i = 0; i < chains.length; i++) {
            Factory factory = factories[i];
            IBorrowerURISource uriSource = uriSources[i];
            INFTManager uniswapNft = uniswapNfts[i];
            IPermit2 permit2 = permit2s[i];

            vm.createSelectFork(vm.rpcUrl(chains[i]));
            vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

            new BorrowerLens{salt: TAG}();
            new LenderLens{salt: TAG}();
            new Router{salt: TAG}(permit2);

            BorrowerNFT borrowerNft = new BorrowerNFT{salt: TAG}(factory, uriSource);

            new BoostManager{salt: TAG}(factory, address(borrowerNft), uniswapNft);
            new FrontendManager{salt: TAG}(factory);
            new SimpleManager{salt: TAG}();
            new UniswapNFTManager{salt: TAG}(factory, uniswapNft);

            vm.stopBroadcast();
        }
    }
}
