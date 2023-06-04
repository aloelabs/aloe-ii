// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {ClonesWithImmutableArgs} from "clones-with-immutable-args/ClonesWithImmutableArgs.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

import {IUniswapV3Pool} from "v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {Oracle} from "src/libraries/Oracle.sol";

import {Borrower} from "src/Borrower.sol";
import {Lender} from "src/Lender.sol";
import {RateModel} from "src/RateModel.sol";
import {VolatilityOracle} from "src/VolatilityOracle.sol";

function deploySingleLender(ERC20 asset, address treasury, RateModel rateModel) returns (Lender) {
    address impl = address(new Lender(treasury, ERC20(address(0))));
    address proxy = ClonesWithImmutableArgs.clone(impl, abi.encodePacked(address(asset)));

    Lender(proxy).initialize(rateModel, 8);
    return Lender(proxy);
}

function deploySingleBorrower(IUniswapV3Pool pool, Lender lender0, Lender lender1) returns (Borrower) {
    address oracleMock = address(new VolatilityOracleMock());
    return new Borrower(VolatilityOracle(oracleMock), pool, lender0, lender1);
}

contract Router {
    function deposit(Lender lender, uint256 amount, address beneficiary) external returns (uint256 shares) {
        lender.asset().transferFrom(msg.sender, address(lender), amount);
        shares = lender.deposit(amount, beneficiary);
    }
}

contract VolatilityOracleMock {
    function consult(IUniswapV3Pool pool) external view returns (uint160, uint256) {
        (uint160 sqrtMeanPriceX96, ) = Oracle.consult(pool, 20 minutes);
        return (sqrtMeanPriceX96, 0.025e18);
    }
}
