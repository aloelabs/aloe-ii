// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import "forge-std/Script.sol";

import {Factory, IUniswapV3Pool} from "../src/Factory.sol";

contract CreateMarketsScript is Script {
    address[] poolsOptimism = [
        0x68F5C0A2DE713a54991E01858Fd27a3832401849, // WETH/OP
        0xbf16ef186e715668AA29ceF57e2fD7f9D48AdFE6, // USDC/DAI
        0x85149247691df622eaF1a8Bd0CaFd40BC45154a9, // WETH/USDC
        0x4a5a2A152e985078e1A4AA9C3362c412B7dd0a86, // wstETH/WETH
        0x03aF20bDAaFfB4cC0A521796a223f7D85e2aAc31, // WETH/DAI
        0x73B14a78a0D396C521f954532d43fd5fFe385216, // WETH/WBTC
        0x1C3140aB59d6cAf9fa7459C6f83D4B52ba881d36, // OP/USDC
        0xF334F6104A179207DdaCfb41FA3567FEea8595C2, // WETH/LYRA
        0x535541F1aa08416e69Dc4D610131099FA2Ae7222, // WETH/PERP
        0x98D9aE198f2018503791D1cAf23c6807C135bB6b, // FRAX/USDC
        0xAD4c666fC170B468B19988959eb931a3676f0e9F, // WETH/UNI
        0xF1F199342687A7d78bCC16fce79fa2665EF870E1 //  USDC/USDT
    ];

    address[] poolsArbitrum = [
        0x80A9ae39310abf666A87C743d6ebBD0E8C42158E, // WETH/GMX
        0xC31E54c7a869B9FcBEcc14363CF510d1c41fa443, // WETH/USDC
        0x27807dD7ADF218e1f4d885d54eD51C70eFb9dE50, // USDT/MIM
        0x2f5e87C9312fa29aed5c179E456625D79015299c, // WBTC/WETH
        0x2039f8c9cd32Ba9cD2Ea7e575d5B1ABeA93f7527, // GMX/USDC
        0x7e7FB3CCEcA5F2ac952eDF221fd2a9f62E411980, // MAGIC/WETH
        0x92c63d0e701CAAe670C9415d91C474F686298f00 //  WETH/ARB
    ];

    address[] poolsBase = [
        0x10648BA41B8565907Cfa1496765fA4D95390aa0d //  cbETH/WETH
    ];

    function run() external {
        vm.createSelectFork(vm.rpcUrl("optimism"));
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        for (uint256 i = 0; i < poolsOptimism.length; i++) {
            Factory(0x95110C9806833d3D3C250112fac73c5A6f631E80).createMarket(IUniswapV3Pool(poolsOptimism[i]));
        }
        vm.stopBroadcast();

        vm.createSelectFork(vm.rpcUrl("arbitrum"));
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        for (uint256 i = 0; i < poolsArbitrum.length; i++) {
            Factory(0x95110C9806833d3D3C250112fac73c5A6f631E80).createMarket(IUniswapV3Pool(poolsArbitrum[i]));
        }
        vm.stopBroadcast();

        vm.createSelectFork(vm.rpcUrl("base"));
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        for (uint256 i = 0; i < poolsBase.length; i++) {
            Factory(0xA56eA45565478Fcd131AEccaB2FE934F23BAD8dc).createMarket(IUniswapV3Pool(poolsBase[i]));
        }
        vm.stopBroadcast();
    }
}
