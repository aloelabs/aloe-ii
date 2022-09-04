// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

import {ERC20} from "@rari-capital/solmate/src/tokens/ERC20.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {InterestModel} from "src/InterestModel.sol";
import {Kitty} from "src/Kitty.sol";
import {MarginAccount} from "src/MarginAccount.sol";

contract Factory {
    event CreateMarket(IUniswapV3Pool indexed pool, Kitty indexed kitty0, Kitty indexed kitty1);

    event CreateMarginAccount(IUniswapV3Pool indexed pool, MarginAccount indexed account);

    struct Market {
        Kitty kitty0;
        Kitty kitty1;
    }

    InterestModel public immutable INTEREST_MODEL;

    mapping(IUniswapV3Pool => Market) public getMarket;

    mapping(Kitty => mapping(address => bool)) public isMarginAccountAllowed;

    constructor() {
        INTEREST_MODEL = new InterestModel();
    }

    function createMarket(IUniswapV3Pool _pool) external {
        ERC20 asset0 = ERC20(_pool.token0());
        ERC20 asset1 = ERC20(_pool.token1());

        Kitty kitty0 = new Kitty{salt: keccak256(abi.encode(_pool))}(
            asset0,
            INTEREST_MODEL,
            address(this)
        );
        Kitty kitty1 = new Kitty{salt: keccak256(abi.encode(_pool))}(
            asset1,
            INTEREST_MODEL,
            address(this)
        );

        getMarket[_pool] = Market(kitty0, kitty1);
        emit CreateMarket(_pool, kitty0, kitty1);
    }

    function createMarginAccount(IUniswapV3Pool _pool, address _owner) external returns (MarginAccount account) {
        Market memory market = getMarket[_pool];
        account = new MarginAccount(_pool, market.kitty0, market.kitty1, _owner);

        isMarginAccountAllowed[market.kitty0][address(account)] = true;
        isMarginAccountAllowed[market.kitty1][address(account)] = true;
        emit CreateMarginAccount(_pool, account);
    }
}
