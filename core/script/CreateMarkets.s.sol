// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

import "forge-std/Script.sol";

import {Factory, IUniswapV3Pool} from "../src/Factory.sol";

Factory constant FACTORY = Factory(0x000000009efdB26b970bCc0085E126C9dfc16ee8);

contract CreateMarketsScript is Script {
    address[] poolsMainnet = [
        0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640, // USDC/WETH 0.05%
        0x4585FE77225b41b697C938B018E2Ac67Ac5a20c0, // WBTC/WETH 0.05%
        0x3416cF6C708Da44DB2624D63ea0AAef7113527C6, // USDC/USDT 0.01%
        0x11b815efB8f581194ae79006d24E0d814B7697F6, // WETH/USDT 0.05%
        0x109830a1AAaD605BbF02a9dFA7B0B92EC2FB7dAa, // wstETH/WETH 0.01%
        0xa6Cc3C2531FdaA6Ae1A3CA84c2855806728693e8, // LINK/WETH 0.30%
        0x60594a405d53811d3BC4766596EFD80fd545A270, // DAI/WETH 0.05%
        0x5777d92f208679DB4b9778590Fa3CAB3aC9e2168, // DAI/USDC 0.01%
        0x99ac8cA7087fA4A2A1FB6357269965A2014ABc35, // WBTC/USDC 0.30%
        0xe8c6c9227491C0a8156A0106A0204d881BB7E531, // MKR/WETH 0.30%
        0xa3f558aebAecAf0e11cA4b2199cC5Ed341edfd74, // LDO/WETH 0.30%
        0x1d42064Fc4Beb5F8aAF85F4617AE8b3b5B8Bd801, // UNI/WETH 0.30%
        0x290A6a7460B308ee3F19023D2D00dE604bcf5B42, // MATIC/WETH 0.30%
        0xe42318eA3b998e8355a3Da364EB9D48eC725Eb45, // WETH/RPL 0.30%
        0xAc4b3DacB91461209Ae9d41EC517c2B9Cb1B7DAF, // APE/WETH 0.30%
        0xe15e6583425700993bd08F51bF6e7B73cd5da91B // WBTC/BADGER 0.30%
    ];

    address[] poolsOptimism = [
        0x68F5C0A2DE713a54991E01858Fd27a3832401849, // WETH/OP 0.30%
        0x85149247691df622eaF1a8Bd0CaFd40BC45154a9, // WETH/USDC 0.05%
        0xF1F199342687A7d78bCC16fce79fa2665EF870E1, // USDC/USDT 0.01%
        0x85C31FFA3706d1cce9d525a00f1C7D4A2911754c, // WETH/WBTC 0.05%
        0xbf16ef186e715668AA29ceF57e2fD7f9D48AdFE6, // USDC/DAI 0.01%
        0x1C3140aB59d6cAf9fa7459C6f83D4B52ba881d36, // OP/USDC 0.30%
        0x535541F1aa08416e69Dc4D610131099FA2Ae7222 // WETH/PERP 0.30%
    ];

    address[] poolsArbitrum = [
        0xC31E54c7a869B9FcBEcc14363CF510d1c41fa443, // WETH/USDC.e 0.05%
        0xC6962004f452bE9203591991D15f6b388e09E8D0, // WETH/USDC 0.05%
        0xC6F780497A95e246EB9449f5e4770916DCd6396A, // WETH/ARB 0.05%
        0xcDa53B1F66614552F834cEeF361A8D12a0B8DaD8, // ARB/USDC 0.05%
        0x2f5e87C9312fa29aed5c179E456625D79015299c, // WBTC/WETH 0.05%
        0xC24f7d8E51A64dc1238880BD00bb961D54cbeb29, // WETH/UNI 0.30%
        0x35218a1cbaC5Bbc3E57fd9Bd38219D37571b3537 // wstETH/WETH 0.01%
    ];

    address[] poolsBase = [
        0x4C36388bE6F416A29C8d8Eee81C771cE6bE14B18, // WETH/USDbC 0.05%
        0x10648BA41B8565907Cfa1496765fA4D95390aa0d, // cbETH/WETH 0.05%
        0x9E37cb775a047Ae99FC5A24dDED834127c4180cD, // BALD/WETH 1.0%
        0xa555149210075702A734968F338d5E1CBd509354, // WETH/BASED 0.30%
        0xBA3F945812a83471d709BCe9C3CA699A19FB46f7, // WETH/BRETT 1.0%
        0x4b0Aaf3EBb163dd45F663b38b6d93f6093EBC2d3, // WETH/TOSHI 1.0%
        0xc9034c3E7F58003E6ae0C8438e7c8f4598d5ACAA // WETH/DEGEN 0.30%
    ];

    function run() external {
        vm.createSelectFork(vm.rpcUrl("mainnet"));
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        for (uint256 i = 0; i < poolsMainnet.length; i++) {
            FACTORY.createMarket(IUniswapV3Pool(poolsMainnet[i]));
        }
        vm.stopBroadcast();

        vm.createSelectFork(vm.rpcUrl("optimism"));
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        for (uint256 i = 0; i < poolsOptimism.length; i++) {
            FACTORY.createMarket(IUniswapV3Pool(poolsOptimism[i]));
        }
        vm.stopBroadcast();

        vm.createSelectFork(vm.rpcUrl("arbitrum"));
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        for (uint256 i = 0; i < poolsArbitrum.length; i++) {
            FACTORY.createMarket(IUniswapV3Pool(poolsArbitrum[i]));
        }
        vm.stopBroadcast();

        vm.createSelectFork(vm.rpcUrl("base"));
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        for (uint256 i = 0; i < poolsBase.length; i++) {
            FACTORY.createMarket(IUniswapV3Pool(poolsBase[i]));
        }
        vm.stopBroadcast();
    }
}
