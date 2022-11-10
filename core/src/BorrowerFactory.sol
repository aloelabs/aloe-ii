// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

import "v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {Lender} from "./Lender.sol";
import {Borrower} from "./Borrower.sol";

contract BorrowerFactory {
    function createBorrower(
        IUniswapV3Pool _pool,
        Lender _lender0,
        Lender _lender1,
        address _owner
    ) external returns (Borrower account) {
        return new Borrower(_pool, _lender0, _lender1, _owner);
    }
}
