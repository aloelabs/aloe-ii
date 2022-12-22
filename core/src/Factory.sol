// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

import {Clones} from "clones-with-immutable-args/Clones.sol";
import {ClonesWithImmutableArgs} from "clones-with-immutable-args/ClonesWithImmutableArgs.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {IUniswapV3Pool} from "v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {InterestModel} from "./InterestModel.sol";
import {Lender} from "./Lender.sol";
import {Borrower} from "./Borrower.sol";

contract Factory {
    using ClonesWithImmutableArgs for address;

    event CreateMarket(IUniswapV3Pool indexed pool, Lender lender0, Lender lender1);

    event CreateBorrower(IUniswapV3Pool indexed pool, address indexed owner, address account);

    struct Market {
        Lender lender0;
        Lender lender1;
        Borrower borrowerImplementation;
    }

    InterestModel public immutable INTEREST_MODEL;

    address public immutable lenderImplementation;

    mapping(IUniswapV3Pool => Market) public getMarket;

    mapping(address => bool) public isBorrower;

    constructor(InterestModel _interestModel) {
        INTEREST_MODEL = _interestModel;
        lenderImplementation = address(new Lender(address(this)));
    }

    function createMarket(IUniswapV3Pool _pool) external {
        address asset0 = _pool.token0();
        address asset1 = _pool.token1();

        bytes32 salt = keccak256(abi.encode(_pool));
        Lender lender0 = Lender(lenderImplementation.cloneDeterministic({salt: salt, data: abi.encodePacked(asset0)}));
        Lender lender1 = Lender(lenderImplementation.cloneDeterministic({salt: salt, data: abi.encodePacked(asset1)}));

        lender0.initialize(INTEREST_MODEL, 8);
        lender1.initialize(INTEREST_MODEL, 8);

        Borrower borrowerImplementation = new Borrower(_pool, lender0, lender1);

        getMarket[_pool] = Market(lender0, lender1, borrowerImplementation);
        emit CreateMarket(_pool, lender0, lender1);
    }

    function createBorrower(IUniswapV3Pool _pool, address _owner) external returns (address account) {
        Market memory market = getMarket[_pool];

        account = Clones.clone(address(market.borrowerImplementation));
        Borrower(account).initialize(_owner);
        isBorrower[account] = true;

        market.lender0.whitelist(account);
        market.lender1.whitelist(account);

        emit CreateBorrower(_pool, _owner, account);
    }
}
