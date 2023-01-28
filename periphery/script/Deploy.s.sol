// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import "forge-std/Script.sol";

import {Factory} from "aloe-ii-core/Factory.sol";

import {BorrowerLens} from "src/BorrowerLens.sol";
import {FrontendManager} from "src/FrontendManager.sol";
import {LenderLens} from "src/LenderLens.sol";
import {Router} from "src/Router.sol";

interface ImmutableCreate2Factory {
    function safeCreate2(bytes32 salt, bytes memory initCode) external returns (address);

    function findCreate2Address(bytes32 salt, bytes memory initCode) external view returns (address);

    function findCreate2AddressViaHash(bytes32 salt, bytes32 initCodeHash) external view returns (address);

    function hasBeenDeployed(address deploymentAddress) external view returns (bool);
}

ImmutableCreate2Factory constant PR00XY_FACTORY = ImmutableCreate2Factory(0x0000000000FFe8B47B3e2130213B802212439497);

address constant ALOE_II_FACTORY = 0x315980E4a137633952917a656ECEBa74c8f39768;
bytes32 constant SALT_ALOE_II_FRONTEND_MANAGER = 0xbbc2cd847bdf10468861dab854cd2b2e315e28c8a03bc66dcbb0c001f6dbf5b1;
bytes32 constant SALT_ALOE_II_LENDER_LENS = 0xbbc2cd847bdf10468861dab854cd2b2e315e28c8a03bc66dcbb0c001f6dbf5b1;
bytes32 constant SALT_ALOE_II_BORROWER_LENS = 0xbbc2cd847bdf10468861dab854cd2b2e315e28c8a03bc66dcbb0c001f6dbf5b1;
bytes32 constant SALT_ALOE_II_ROUTER = 0xbbc2cd847bdf10468861dab854cd2b2e315e28c8a03bc66dcbb0c001f6dbf5b1;

contract DeployScript is Script {
    function run() external {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        bytes memory args;
        bytes memory creationCode;
        bytes memory initializationCode;

        args = abi.encode(ALOE_II_FACTORY);
        creationCode = type(FrontendManager).creationCode;
        initializationCode = abi.encodePacked(creationCode, args);
        address frontendManager = PR00XY_FACTORY.safeCreate2(SALT_ALOE_II_FRONTEND_MANAGER, initializationCode);

        creationCode = type(LenderLens).creationCode;
        initializationCode = abi.encodePacked(creationCode);
        PR00XY_FACTORY.safeCreate2(SALT_ALOE_II_LENDER_LENS, initializationCode);

        creationCode = type(BorrowerLens).creationCode;
        initializationCode = abi.encodePacked(creationCode);
        PR00XY_FACTORY.safeCreate2(SALT_ALOE_II_BORROWER_LENS, initializationCode);

        creationCode = type(Router).creationCode;
        initializationCode = abi.encodePacked(creationCode);
        PR00XY_FACTORY.safeCreate2(SALT_ALOE_II_ROUTER, initializationCode);

        vm.stopBroadcast();
    }
}
