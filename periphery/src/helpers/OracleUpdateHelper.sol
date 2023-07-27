// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.17;

import {VolatilityOracle, IUniswapV3Pool} from "aloe-ii-core/VolatilityOracle.sol";

contract OracleUpdateHelper {
    VolatilityOracle immutable ORACLE;

    constructor(VolatilityOracle oracle) {
        ORACLE = oracle;
    }

    function update(IUniswapV3Pool[] calldata pools) external {
        unchecked {
            uint256 count = pools.length;
            for (uint256 i = 0; i < count; i++) {
                ORACLE.update(pools[i], 1 << 32);
            }
        }
    }
}
