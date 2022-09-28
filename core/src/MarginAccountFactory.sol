// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

import "v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {Kitty} from "./Kitty.sol";
import {MarginAccount} from "./MarginAccount.sol";

contract MarginAccountFactory {
    function createMarginAccount(
        IUniswapV3Pool _pool,
        Kitty _kitty0,
        Kitty _kitty1,
        address _owner
    ) external returns (MarginAccount account) {
        return new MarginAccount(_pool, _kitty0, _kitty1, _owner);
    }
}
