// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

import {ClonesWithImmutableArgs} from "clones-with-immutable-args/ClonesWithImmutableArgs.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

import {RateModel} from "src/RateModel.sol";
import {Lender} from "src/Lender.sol";

function deploySingleLender(ERC20 asset, address treasury, RateModel rateModel) returns (Lender) {
    address impl = address(new Lender(treasury));
    address proxy = ClonesWithImmutableArgs.clone(address(impl), abi.encodePacked(address(asset)));

    Lender(proxy).initialize(rateModel, 8);
    return Lender(proxy);
}
