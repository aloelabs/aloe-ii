// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import "forge-std/Script.sol";

import {IUniswapV3Pool} from "v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {Factory} from "aloe-ii-core/Factory.sol";

abstract contract KeeperScript is Script {
    Factory constant FACTORY = Factory(0x95110C9806833d3D3C250112fac73c5A6f631E80);

    IUniswapV3Pool[] poolsOptimism = [
        IUniswapV3Pool(0x68F5C0A2DE713a54991E01858Fd27a3832401849), // WETH/OP
        IUniswapV3Pool(0xbf16ef186e715668AA29ceF57e2fD7f9D48AdFE6), // USDC/DAI
        IUniswapV3Pool(0x85149247691df622eaF1a8Bd0CaFd40BC45154a9), // WETH/USDC
        IUniswapV3Pool(0x4a5a2A152e985078e1A4AA9C3362c412B7dd0a86), // wstETH/WETH
        IUniswapV3Pool(0x03aF20bDAaFfB4cC0A521796a223f7D85e2aAc31), // WETH/DAI
        IUniswapV3Pool(0x73B14a78a0D396C521f954532d43fd5fFe385216), // WETH/WBTC
        IUniswapV3Pool(0x1C3140aB59d6cAf9fa7459C6f83D4B52ba881d36), // OP/USDC
        IUniswapV3Pool(0xF334F6104A179207DdaCfb41FA3567FEea8595C2), // WETH/LYRA
        IUniswapV3Pool(0x535541F1aa08416e69Dc4D610131099FA2Ae7222), // WETH/PERP
        IUniswapV3Pool(0x98D9aE198f2018503791D1cAf23c6807C135bB6b), // FRAX/USDC
        IUniswapV3Pool(0xAD4c666fC170B468B19988959eb931a3676f0e9F)  // WETH/UNI
    ];

    IUniswapV3Pool[] poolsArbitrum = [
        IUniswapV3Pool(0x80A9ae39310abf666A87C743d6ebBD0E8C42158E), // WETH/GMX
        IUniswapV3Pool(0xC31E54c7a869B9FcBEcc14363CF510d1c41fa443), // WETH/USDC
        // IUniswapV3Pool(0x27807dD7ADF218e1f4d885d54eD51C70eFb9dE50), // USDT/MIM
        IUniswapV3Pool(0x2f5e87C9312fa29aed5c179E456625D79015299c), // WBTC/WETH
        IUniswapV3Pool(0x2039f8c9cd32Ba9cD2Ea7e575d5B1ABeA93f7527), // GMX/USDC
        IUniswapV3Pool(0x7e7FB3CCEcA5F2ac952eDF221fd2a9f62E411980), // MAGIC/WETH
        IUniswapV3Pool(0x92c63d0e701CAAe670C9415d91C474F686298f00)  // WETH/ARB
    ];

    IUniswapV3Pool[] poolsBase = [
        IUniswapV3Pool(0x10648BA41B8565907Cfa1496765fA4D95390aa0d) //  cbETH/WETH
    ];
}
