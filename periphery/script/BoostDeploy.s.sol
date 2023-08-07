// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import "forge-std/Script.sol";

import {Factory} from "aloe-ii-core/Factory.sol";

import {BoostNFT} from "src/boost/BoostNFT.sol";
import {INonfungiblePositionManager as IUniswapNFT} from "src/interfaces/INonfungiblePositionManager.sol";
import {BoostManager} from "src/managers/BoostManager.sol";

Factory constant ALOE_II_FACTORY = Factory(0x95110C9806833d3D3C250112fac73c5A6f631E80);
IUniswapNFT constant UNISWAP_NFT_MANAGER = IUniswapNFT(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
bytes32 constant TAG = bytes32(uint256(0xA10EBE1A2));

contract DeployScript is Script {
    string[] chains = ["optimism", "arbitrum"];

    function run() external {
        for (uint256 i = 0; i < chains.length; i++) {
            vm.createSelectFork(vm.rpcUrl(chains[i]));
            vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

            BoostNFT boostNft = new BoostNFT(ALOE_II_FACTORY);
            BoostManager boostManager = new BoostManager(ALOE_II_FACTORY, address(boostNft), UNISWAP_NFT_MANAGER);

            boostNft.setBoostManager(boostManager);
            boostNft.setOwner(0xC3feD7757CD3eb12b155F230Fa057396e9D78EAa);

            vm.stopBroadcast();
        }
    }
}
