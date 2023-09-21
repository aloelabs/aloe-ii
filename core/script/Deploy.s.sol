// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import "forge-std/Script.sol";

import {Factory, BorrowerDeployer, ERC20} from "src/Factory.sol";
import {Lender} from "src/Lender.sol";
import {RateModel} from "src/RateModel.sol";
import {VolatilityOracle} from "src/VolatilityOracle.sol";

address constant GOVERNOR = 0x2bf8eA41aF0695D482C4aa23d4f8aD7E9023b890;
address constant RESERVE = 0xAd236E154cbC33cFDB6CD7A4BA04679d9fb74A8C;

// Derived using https://github.com/0age/create2crunch/
bytes32 constant saltA = 0x0000000000000000000000000000000000000000aeeec55d74c86000021e5622;
bytes32 constant saltB = 0x00000000000000000000000000000000000000008a0ad7466accc00001d49926;
bytes32 constant saltC = 0x0000000000000000000000000000000000000000d36d6b3f5afc00000074870e;
bytes32 constant saltD = 0x00000000000000000000000000000000000000005f2f31da9d94e0001ab8274a;

contract DeployScript is Script {
    function run() external {
        bytes32 ichVolatilityOracle = hashInitCode(type(VolatilityOracle).creationCode);
        bytes32 ichRateModel = hashInitCode(type(RateModel).creationCode);
        bytes32 ichBorrowerDeployer = hashInitCode(type(BorrowerDeployer).creationCode);

        address addrVolatilityOracle = computeCreate2Address(saltA, ichVolatilityOracle);
        address addrRateModel = computeCreate2Address(saltB, ichRateModel);
        address addrBorrowerDeployer = computeCreate2Address(saltC, ichBorrowerDeployer);

        bytes32 ichFactory = hashInitCode(
            type(Factory).creationCode,
            abi.encode(GOVERNOR, RESERVE, addrVolatilityOracle, addrBorrowerDeployer, addrRateModel)
        );
        address addrFactory = computeCreate2Address(saltD, ichFactory);

        console2.log("\ninitCode hashes");
        console2.log("\tVolatilityOracle:\t", vm.toString(ichVolatilityOracle));
        console2.log("\tRateModel:\t\t", vm.toString(ichRateModel));
        console2.log("\tBorrowerDeployer:\t", vm.toString(ichBorrowerDeployer));
        console2.log("\tFactory:\t\t", vm.toString(ichFactory));

        console2.log("\naddresses");
        console2.log("\tVolatilityOracle:\t", addrVolatilityOracle);
        console2.log("\tRateModel:\t\t", addrRateModel);
        console2.log("\tBorrowerDeployer:\t", addrBorrowerDeployer);
        console2.log("\tFactory:\t\t", addrFactory);

        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        VolatilityOracle oracle = new VolatilityOracle{salt: saltA}();
        RateModel rateModel = new RateModel{salt: saltB}();
        BorrowerDeployer borrowerDeployer = new BorrowerDeployer{salt: saltC}();
        Factory factory = new Factory{salt: saltD}({
            governor: GOVERNOR,
            reserve: RESERVE,
            oracle: oracle,
            borrowerDeployer: borrowerDeployer,
            defaultRateModel: rateModel
        });

        vm.stopBroadcast();
        assert(address(factory) == addrFactory);
    }
}
