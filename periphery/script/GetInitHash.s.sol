// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "forge-std/Script.sol";

import {FrontendManager} from "src/FrontendManager.sol";

address constant FACTORY = 0x00001e0800ef386E00005Ad9e11C82c8b800BF4f;

contract GetInitHashScript is Script {
    event GetInitHash(bytes32 initHash);

    function run() external {
        bytes memory args;
        bytes memory creationCode;
        bytes memory initializationCode;

        args = abi.encode(FACTORY);
        creationCode = type(FrontendManager).creationCode;
        initializationCode = abi.encodePacked(creationCode, args);

        emit GetInitHash(keccak256(initializationCode));
    }
}
