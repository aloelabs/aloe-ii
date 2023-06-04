// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {Clones} from "clones-with-immutable-args/Clones.sol";
import {ClonesWithImmutableArgs} from "clones-with-immutable-args/ClonesWithImmutableArgs.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {IUniswapV3Pool} from "v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {DEFAULT_ANTE, DEFAULT_N_SIGMA} from "./libraries/constants/Constants.sol";

import {Borrower} from "./Borrower.sol";
import {Lender} from "./Lender.sol";
import {RateModel} from "./RateModel.sol";
import {VolatilityOracle} from "./VolatilityOracle.sol";

/// @title Factory
/// @author Aloe Labs, Inc.
/// @dev "Test everything; hold fast what is good." - 1 Thessalonians 5:21
contract Factory {
    using ClonesWithImmutableArgs for address;

    event CreateMarket(IUniswapV3Pool indexed pool, Lender lender0, Lender lender1);

    event CreateBorrower(IUniswapV3Pool indexed pool, address indexed owner, address account);

    struct Market {
        Lender lender0;
        Lender lender1;
        Borrower borrowerImplementation;
    }

    struct Parameters {
        uint248 ante;
        uint8 nSigma;
    }

    VolatilityOracle public immutable ORACLE;

    RateModel public immutable RATE_MODEL;

    address public immutable lenderImplementation;

    mapping(IUniswapV3Pool => Market) public getMarket;

    mapping(IUniswapV3Pool => Parameters) public getParameters;

    mapping(address => bool) public isBorrower;

    constructor(VolatilityOracle oracle, RateModel rateModel, ERC20 rewardsToken) {
        ORACLE = oracle;
        RATE_MODEL = rateModel;
        lenderImplementation = address(new Lender(address(this), rewardsToken));
    }

    function createMarket(IUniswapV3Pool pool) external {
        ORACLE.prepare(pool);

        address asset0 = pool.token0();
        address asset1 = pool.token1();

        bytes32 salt = keccak256(abi.encode(pool));
        Lender lender0 = Lender(lenderImplementation.cloneDeterministic({salt: salt, data: abi.encodePacked(asset0)}));
        Lender lender1 = Lender(lenderImplementation.cloneDeterministic({salt: salt, data: abi.encodePacked(asset1)}));

        lender0.initialize(RATE_MODEL, 8);
        lender1.initialize(RATE_MODEL, 8);

        Borrower borrowerImplementation = new Borrower(ORACLE, pool, lender0, lender1);

        getMarket[pool] = Market(lender0, lender1, borrowerImplementation);
        getParameters[pool] = Parameters(DEFAULT_ANTE, DEFAULT_N_SIGMA);
        emit CreateMarket(pool, lender0, lender1);
    }

    function createBorrower(IUniswapV3Pool pool, address owner) external returns (address account) {
        Market memory market = getMarket[pool];

        account = Clones.clone(address(market.borrowerImplementation));
        Borrower(account).initialize(owner);
        isBorrower[account] = true;

        market.lender0.whitelist(account);
        market.lender1.whitelist(account);

        emit CreateBorrower(pool, owner, account);
    }
}
