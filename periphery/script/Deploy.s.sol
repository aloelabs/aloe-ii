// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "forge-std/Script.sol";

import {Factory} from "aloe-ii-core/Factory.sol";

import {BorrowerLens} from "src/BorrowerLens.sol";
import {BorrowManager} from "src/BorrowManager.sol";
import {FrontendManager} from "src/FrontendManager.sol";
import {LenderLens} from "src/LenderLens.sol";
import {Router} from "src/Router.sol";

Factory constant FACTORY = Factory(0x7BFAAC3EEBe085f91E440E9Fc62394112b533da4);

contract MyScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // BorrowerLens borrowerLens = new BorrowerLens();
        // BorrowManager borrowManager = new BorrowManager(FACTORY);
        // FrontendManager frontendManager = new FrontendManager(FACTORY);
        // LenderLens lenderLens = new LenderLens();
        Router router = new Router();

        vm.stopBroadcast();
    }
}

// 0x9190f254ac4af226077aa58785bbbf329629a921
// 0xe218e53de8d9aeb05f745f019e6a5ef2ad0c93df
// 0x55d6fd22240169d16f0dc1a0c70d3597873a9ede
// 0xc55d96b0e3e1d8cd14346c5c7c5ec3f945eeb34a

// ETHERSCAN_API_KEY=$ETHERSCAN_API_KEY forge verify-contract --chain-id 5 --watch 0x9190f254ac4af226077aa58785bbbf329629a921 src/BorrowerLens.sol:BorrowerLens
// ETHERSCAN_API_KEY=$ETHERSCAN_API_KEY forge verify-contract --chain-id 5 --watch 0xe218e53de8d9aeb05f745f019e6a5ef2ad0c93df src/BorrowerLens.sol:BorrowerLens
// ETHERSCAN_API_KEY=$ETHERSCAN_API_KEY forge verify-contract --chain-id 5 --watch 0x55d6fd22240169d16f0dc1a0c70d3597873a9ede src/BorrowerLens.sol:BorrowerLens
// ETHERSCAN_API_KEY=$ETHERSCAN_API_KEY forge verify-contract --chain-id 5 --watch 0xc55d96b0e3e1d8cd14346c5c7c5ec3f945eeb34a src/LenderLens.sol:LenderLens
