// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import "forge-std/Script.sol";

import {IUniswapV3Pool} from "v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {OracleUpdateHelper} from "src/OracleUpdateHelper.sol";

contract UpdateOracleScript is Script {
    OracleUpdateHelper constant HELPER = OracleUpdateHelper(0x7dd9752f882d404717DaF52e9Ff3d1dE2aAccc4a);

    function run() external {
        IUniswapV3Pool[] memory pools = new IUniswapV3Pool[](11);
        pools[0] = IUniswapV3Pool(0x68F5C0A2DE713a54991E01858Fd27a3832401849); // WETH/OP
        pools[1] = IUniswapV3Pool(0xbf16ef186e715668AA29ceF57e2fD7f9D48AdFE6); // USDC/DAI
        pools[2] = IUniswapV3Pool(0x85149247691df622eaF1a8Bd0CaFd40BC45154a9); // WETH/USDC
        pools[3] = IUniswapV3Pool(0x4a5a2A152e985078e1A4AA9C3362c412B7dd0a86); // wstETH/WETH
        pools[4] = IUniswapV3Pool(0x03aF20bDAaFfB4cC0A521796a223f7D85e2aAc31); // WETH/DAI
        pools[5] = IUniswapV3Pool(0x73B14a78a0D396C521f954532d43fd5fFe385216); // WETH/WBTC
        pools[6] = IUniswapV3Pool(0x1C3140aB59d6cAf9fa7459C6f83D4B52ba881d36); // OP/USDC
        pools[7] = IUniswapV3Pool(0xF334F6104A179207DdaCfb41FA3567FEea8595C2); // WETH/LYRA
        pools[8] = IUniswapV3Pool(0x535541F1aa08416e69Dc4D610131099FA2Ae7222); // WETH/PERP
        pools[9] = IUniswapV3Pool(0x98D9aE198f2018503791D1cAf23c6807C135bB6b); // FRAX/USDC
        pools[10] = IUniswapV3Pool(0xAD4c666fC170B468B19988959eb931a3676f0e9F);  // WETH/UNI

        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        HELPER.update(pools);
        vm.stopBroadcast();
    }
}
