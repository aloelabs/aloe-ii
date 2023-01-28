// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import "forge-std/Script.sol";

import {Factory} from "../src/Factory.sol";
import {RateModel} from "../src/RateModel.sol";

interface ImmutableCreate2Factory {
    function safeCreate2(bytes32 salt, bytes memory initCode) external returns (address);

    function findCreate2Address(bytes32 salt, bytes memory initCode) external view returns (address);

    function findCreate2AddressViaHash(bytes32 salt, bytes32 initCodeHash) external view returns (address);

    function hasBeenDeployed(address deploymentAddress) external view returns (bool);
}

ImmutableCreate2Factory constant PR00XY_FACTORY = ImmutableCreate2Factory(0x0000000000FFe8B47B3e2130213B802212439497);

bytes32 constant SALT_ALOE_II_RATE_MODEL = 0xbbc2cd847bdf10468861dab854cd2b2e315e28c82d7041b11db008801ba5ea44;
bytes32 constant SALT_ALOE_II_FACTORY = 0xbbc2cd847bdf10468861dab854cd2b2e315e28c84f81a0a48c5d550005aa9b34;

contract DeployScript is Script {
    event GetInitHash(bytes32 initHash);

    function run() external {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        bytes memory args;
        bytes memory creationCode;
        bytes memory initializationCode;

        creationCode = type(RateModel).creationCode;
        initializationCode = abi.encodePacked(creationCode);
        address rateModel = PR00XY_FACTORY.safeCreate2(SALT_ALOE_II_RATE_MODEL, initializationCode);

        args = abi.encode(rateModel);
        creationCode = type(Factory).creationCode;
        initializationCode = abi.encodePacked(creationCode, args);

        emit GetInitHash(keccak256(initializationCode));

        address factory = PR00XY_FACTORY.safeCreate2(SALT_ALOE_II_FACTORY, initializationCode);

        vm.stopBroadcast();
    }
}
