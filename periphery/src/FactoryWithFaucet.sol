// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

import {ERC20} from "solmate/tokens/ERC20.sol";
import "v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {Factory} from "aloe-ii-core/Factory.sol";

import {MockERC20} from "./MockERC20.sol";

contract FactoryWithFaucet {
    Factory public immutable FACTORY;

    constructor(Factory _factory) {
        FACTORY = _factory;
    }

    function createBorrower(IUniswapV3Pool _pool, address _owner) external {
        FACTORY.createBorrower(_pool, _owner);
        if (ERC20(0x3C80ca907Ee39f6C3021B66b5a55CCC18e07141A).balanceOf(address(this)) < 20e6) {
            MockERC20(0x3C80ca907Ee39f6C3021B66b5a55CCC18e07141A).request();
        }
        ERC20(0x3C80ca907Ee39f6C3021B66b5a55CCC18e07141A).transfer(msg.sender, 20e6);
    }
}
