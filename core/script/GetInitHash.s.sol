// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "forge-std/Script.sol";

import {Factory} from "../src/Factory.sol";
import {RateModel} from "../src/RateModel.sol";

address constant RATE_MODEL = 0x00000000a6f937BCB46F1dB682Ce4F0CDD99Afb1;

contract GetInitHashScript is Script {
    event GetInitHash(bytes32 initHash);

    function run() external {
        bytes memory args;
        bytes memory creationCode;
        bytes memory initializationCode;

        creationCode = type(RateModel).creationCode;
        initializationCode = abi.encodePacked(creationCode);
        emit GetInitHash(keccak256(initializationCode));

        args = abi.encode(RATE_MODEL);
        creationCode = type(Factory).creationCode;
        initializationCode = abi.encodePacked(creationCode, args);

        emit GetInitHash(keccak256(initializationCode));
    }
}
