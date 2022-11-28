// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {ClonesWithImmutableArgs} from "clones-with-immutable-args/ClonesWithImmutableArgs.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

import {InterestModel} from "src/InterestModel.sol";
import {Lender} from "src/Lender.sol";

function deploySingleLender(ERC20 asset, address treasury, InterestModel interestModel) returns (Lender) {
    address impl = address(new Lender(treasury));
    address proxy = ClonesWithImmutableArgs.clone(address(impl), abi.encodePacked(address(asset)));

    Lender(proxy).initialize(interestModel, 8);
    return Lender(proxy);
}
