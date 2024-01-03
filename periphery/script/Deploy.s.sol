// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.23;

import "forge-std/Script.sol";

import {Factory} from "aloe-ii-core/Factory.sol";

import {BorrowerLens} from "src/BorrowerLens.sol";
import {LenderLens} from "src/LenderLens.sol";
import {Router, IPermit2} from "src/Router.sol";

import {BorrowerNFT, IBorrowerURISource} from "src/borrower-nft/BorrowerNFT.sol";

import {IUniswapPositionNFT} from "src/interfaces/IUniswapPositionNFT.sol";
import {BoostManager} from "src/managers/BoostManager.sol";
import {BorrowerNFTMultiManager} from "src/managers/BorrowerNFTMultiManager.sol";
import {BorrowerNFTSimpleManager} from "src/managers/BorrowerNFTSimpleManager.sol";
import {FrontendManager} from "src/managers/FrontendManager.sol";
import {Permit2Manager} from "src/managers/Permit2Manager.sol";
import {SimpleManager} from "src/managers/SimpleManager.sol";
import {UniswapNFTManager} from "src/managers/UniswapNFTManager.sol";

bytes32 constant TAG = 0x0000000000000000000000000000000000000000A10EA10EA10EA10EA10EA10E;

contract DeployScript is Script {
    /// @dev Aloe II `Factory`, constant across chains
    Factory constant FACTORY = Factory(0x000000009efdB26b970bCc0085E126C9dfc16ee8);

    /// @dev Aloe II `IBorrowerURISource`, constant across chains
    IBorrowerURISource constant BORROWER_URI_SOURCE = IBorrowerURISource(0xb932F8c0474c307a8fc780FaA86eCB05F7D8F3d6);

    /// @dev Uniswap `Permit2`, constant across chains
    IPermit2 constant PERMIT2 = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    /// @dev Uniswap non-fungible position manager addresses, differ across chains
    mapping(uint256 => IUniswapPositionNFT) uniswapPositionNfts;

    function run() external {
        uniswapPositionNfts[1] = IUniswapPositionNFT(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
        uniswapPositionNfts[10] = IUniswapPositionNFT(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
        uniswapPositionNfts[42161] = IUniswapPositionNFT(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
        uniswapPositionNfts[8453] = IUniswapPositionNFT(0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1);
        IUniswapPositionNFT uniswapPositionNft = uniswapPositionNfts[block.chainid];

        bytes32 saltA = vm.envBytes32("saltA");
        bytes32 saltB = vm.envBytes32("saltB");
        _printAddresses(saltA, saltB);

        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        // Lenses
        new BorrowerLens{salt: TAG}();
        new LenderLens{salt: TAG}();

        // User-facing contracts
        new Router{salt: saltA}(PERMIT2);
        BorrowerNFT borrowerNft = new BorrowerNFT{salt: saltB}(FACTORY, BORROWER_URI_SOURCE);

        // BorrowerNFT-style managers
        new BorrowerNFTMultiManager{salt: TAG}();
        new BorrowerNFTSimpleManager{salt: TAG}();
        new BoostManager{salt: TAG}(FACTORY, address(borrowerNft), uniswapPositionNft);
        new Permit2Manager{salt: TAG}(PERMIT2, FACTORY, address(borrowerNft));
        new UniswapNFTManager{salt: TAG}(FACTORY, address(borrowerNft), uniswapPositionNft);

        // Plain managers
        new FrontendManager{salt: TAG}(FACTORY);
        new SimpleManager{salt: TAG}();

        vm.stopBroadcast();
    }

    function _printAddresses(bytes32 saltA, bytes32 saltB) private view {
        bytes32 ichRouter = hashInitCode(type(Router).creationCode, abi.encode(PERMIT2));
        bytes32 ichBorrowerNft = hashInitCode(type(BorrowerNFT).creationCode, abi.encode(FACTORY, BORROWER_URI_SOURCE));

        address addrRouter = computeCreate2Address(saltA, ichRouter);
        address addrBorrowerNft = computeCreate2Address(saltB, ichBorrowerNft);

        console2.log("\ninitCode hashes");
        console2.log("\tRouter:\t\t", vm.toString(ichRouter));
        console2.log("\tBorrowerNFT:\t", vm.toString(ichBorrowerNft));

        console2.log("\naddresses");
        console2.log("\tRouter:\t\t", addrRouter);
        console2.log("\tBorrowerNFT:\t", addrBorrowerNft);
    }
}
