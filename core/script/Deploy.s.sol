// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

import "forge-std/Script.sol";

import {Factory, BorrowerDeployer, ERC20} from "src/Factory.sol";
import {Lender} from "src/Lender.sol";
import {RateModel} from "src/RateModel.sol";
import {VolatilityOracle} from "src/VolatilityOracle.sol";

address constant GOVERNOR = 0xFb6520d40fF68d9088d9e55F44f6C44bb2967Fb9;
address constant RESERVE = 0xB0e822D7073f0cE223256AEf04d59b0e06AeE8f9;

contract DeployScript is Script {
    function run() external {
        bytes32 saltA = vm.envBytes32("saltA");
        bytes32 saltB = vm.envBytes32("saltB");
        bytes32 saltC = vm.envBytes32("saltC");
        bytes32 saltD = vm.envBytes32("saltD");

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

        VolatilityOracle oracle = vm.envBool("deployOracle")
            ? new VolatilityOracle{salt: saltA}()
            : VolatilityOracle(addrVolatilityOracle);
        RateModel rateModel = vm.envBool("deployRateModel") ? new RateModel{salt: saltB}() : RateModel(addrRateModel);
        BorrowerDeployer borrowerDeployer = vm.envBool("deployBorrowerDeployer")
            ? new BorrowerDeployer{salt: saltC}()
            : BorrowerDeployer(addrBorrowerDeployer);
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
