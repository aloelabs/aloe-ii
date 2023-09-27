// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import "forge-std/Script.sol";

import {Factory} from "aloe-ii-core/Factory.sol";

import {BoostNFT} from "src/boost/BoostNFT.sol";
import {INonfungiblePositionManager as IUniswapNFT} from "src/interfaces/INonfungiblePositionManager.sol";
import {BoostManager} from "src/managers/BoostManager.sol";

bytes32 constant TAG = bytes32(uint256(0xA10EBE1AB0051));
address constant OWNER = 0xC3feD7757CD3eb12b155F230Fa057396e9D78EAa;

contract DeployBoostScript is Script {
    string[] chains = ["optimism", "arbitrum", "base"];

    Factory[] factories = [
        Factory(0x3A0a11A7829bfB34400cE338a0442877FBC8582e),
        Factory(0x3A0a11A7829bfB34400cE338a0442877FBC8582e),
        Factory(0x00000006d6C0519e0eB953CFfeb7007e5200680B)
    ];

    IUniswapNFT[] uniswapNfts = [
        IUniswapNFT(0xC36442b4a4522E871399CD717aBDD847Ab11FE88),
        IUniswapNFT(0xC36442b4a4522E871399CD717aBDD847Ab11FE88),
        IUniswapNFT(0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1)
    ];

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        for (uint256 i = 0; i < chains.length; i++) {
            Factory factory = factories[i];
            IUniswapNFT uniswapNft = uniswapNfts[i];

            vm.createSelectFork(vm.rpcUrl(chains[i]));
            vm.startBroadcast(deployerPrivateKey);

            BoostNFT boostNft = new BoostNFT{salt: TAG}(deployer, factory);
            BoostManager boostManager = new BoostManager{salt: TAG}(factory, address(boostNft), uniswapNft);

            boostNft.setBoostManager(boostManager);
            boostNft.setOwner(OWNER);

            vm.stopBroadcast();
        }
    }
}

contract UpdateBoostManagerScript is Script {
    string[] chains = ["optimism", "arbitrum", "base"];

    Factory[] factories = [
        Factory(0x3A0a11A7829bfB34400cE338a0442877FBC8582e),
        Factory(0x3A0a11A7829bfB34400cE338a0442877FBC8582e),
        Factory(0x00000006d6C0519e0eB953CFfeb7007e5200680B)
    ];

    IUniswapNFT[] uniswapNfts = [
        IUniswapNFT(0xC36442b4a4522E871399CD717aBDD847Ab11FE88),
        IUniswapNFT(0xC36442b4a4522E871399CD717aBDD847Ab11FE88),
        IUniswapNFT(0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1)
    ];

    BoostNFT[] boostNfts = [
        BoostNFT(0x6A493103db746451E1B0a927f85D82F3624E407c),
        BoostNFT(0x6A493103db746451E1B0a927f85D82F3624E407c),
        BoostNFT(0xb60A0537908C5D750483750C3172ff437fcA9f32)
    ];

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        for (uint256 i = 0; i < chains.length; i++) {
            Factory factory = factories[i];
            IUniswapNFT uniswapNft = uniswapNfts[i];
            BoostNFT boostNft = boostNfts[i];

            vm.createSelectFork(vm.rpcUrl(chains[i]));
            vm.startBroadcast(deployerPrivateKey);

            BoostManager boostManager = new BoostManager{salt: TAG}(factory, address(boostNft), uniswapNft);

            boostNft.setBoostManager(boostManager);

            vm.stopBroadcast();
        }
    }
}
