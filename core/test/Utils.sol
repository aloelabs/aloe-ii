// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {ClonesWithImmutableArgs} from "clones-with-immutable-args/ClonesWithImmutableArgs.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

import {IUniswapV3Pool} from "v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {Oracle, UNISWAP_AVG_WINDOW} from "src/libraries/Oracle.sol";

import {Borrower} from "src/Borrower.sol";
import {Factory, BorrowerDeployer} from "src/Factory.sol";
import {Lender} from "src/Lender.sol";
import {RateModel, IRateModel} from "src/RateModel.sol";
import {VolatilityOracle} from "src/VolatilityOracle.sol";

contract FatFactory is Factory {
    constructor(
        address governor,
        address reserve,
        VolatilityOracle oracle,
        IRateModel defaultRateModel
    ) Factory(governor, reserve, oracle, new BorrowerDeployer(), defaultRateModel) {}
}

contract FactoryForLenderTests is FatFactory {
    constructor(
        RateModel rateModel,
        ERC20 rewardsToken_
    ) FatFactory(address(0), address(this), VolatilityOracle(address(0)), rateModel) {
        rewardsToken = rewardsToken_;
    }

    function deploySingleLender(ERC20 asset) external returns (Lender) {
        address proxy = ClonesWithImmutableArgs.clone(LENDER_IMPLEMENTATION, abi.encodePacked(address(asset)));
        peer[proxy] = address(1);

        Lender(proxy).initialize();
        Lender(proxy).setRateModelAndReserveFactor(DEFAULT_RATE_MODEL, 8);
        return Lender(proxy);
    }
}

contract Router {
    function deposit(Lender lender, uint256 amount, address beneficiary) external returns (uint256 shares) {
        lender.asset().transferFrom(msg.sender, address(lender), amount);
        shares = lender.deposit(amount, beneficiary);
    }
}

contract VolatilityOracleMock {
    function prepare(IUniswapV3Pool pool) external {}

    function consult(IUniswapV3Pool pool, uint40 seed) external view returns (uint56, uint160, uint256) {
        (Oracle.PoolData memory data, uint56 metric) = Oracle.consult(pool, seed);
        return (metric, data.sqrtMeanPriceX96, 0.025e12);
    }
}

function getSeed(IUniswapV3Pool pool) view returns (uint32) {
    (, , uint16 index, uint16 cardinality, , , ) = pool.slot0();

    uint32 target = uint32(block.timestamp - UNISWAP_AVG_WINDOW);
    uint32 seed30Min;
    while (true) {
        uint32 next = (seed30Min + 1) % cardinality;
        (uint32 timeL, , , ) = pool.observations(seed30Min);
        (uint32 timeR, , , ) = pool.observations(next);

        if (timeL <= target && target <= timeR) break;
        if (timeL <= target && seed30Min == index) break;

        seed30Min = next;
    }

    target = uint32(block.timestamp - 2 * UNISWAP_AVG_WINDOW);
    uint32 seed60min;
    while (true) {
        uint32 next = (seed60min + 1) % cardinality;
        (uint32 timeL, , , ) = pool.observations(seed60min);
        (uint32 timeR, , , ) = pool.observations(next);

        if (timeL <= target && target <= timeR) break;
        if (timeL <= target && seed60min == index) break;

        seed60min = next;
    }

    return (seed60min << 16) + seed30Min;
}
