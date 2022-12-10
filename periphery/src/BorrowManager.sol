// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

import {ERC20, SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import "v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {Uniswap} from "aloe-ii-core/libraries/Uniswap.sol";
import {Factory} from "aloe-ii-core/Factory.sol";
import {IManager, Borrower} from "aloe-ii-core/Borrower.sol";
import {Lender} from "aloe-ii-core/Lender.sol";

contract BorrowManager is IManager {
    using SafeTransferLib for ERC20;

    Factory public immutable FACTORY;

    constructor(Factory _factory) {
        FACTORY = _factory;
    }

    /* solhint-disable code-complexity */

    /**
     * @notice This should be called by a borrower during its modify function
     * @param data actions, amount0, amount1
     * @dev actions: 0 = borrow, 1 = repay, 2 = withdraw
     * @return positions
     * @return includeLenderReceipts
     */
    function callback(
        bytes calldata data
    ) public returns (Uniswap.Position[] memory positions, bool includeLenderReceipts) {
        require(FACTORY.isBorrower(msg.sender), "Aloe: bad account");
        Borrower account = Borrower(msg.sender);
        (uint8[] memory actions, uint256[] memory amounts0, uint256[] memory amounts1) = abi.decode(
            data,
            (uint8[], uint256[], uint256[])
        );

        require(actions.length == amounts0.length && actions.length == amounts1.length, "Aloe: bad data");
        for (uint256 i; i < actions.length; i++) {
            uint8 action = actions[i];
            uint256 amount0 = amounts0[i];
            uint256 amount1 = amounts1[i];
            if (action == 0) {
                account.borrow(amount0, amount1, account.owner());
            } else if (action == 1) {
                if (amount0 != 0) {
                    ERC20 token0 = account.TOKEN0();
                    Lender lender0 = account.LENDER0();
                    token0.safeTransferFrom(account.owner(), address(lender0), amount0);
                    lender0.repay(amount0, address(account));
                }
                if (amount1 != 0) {
                    ERC20 token1 = account.TOKEN1();
                    Lender lender1 = account.LENDER1();
                    token1.safeTransferFrom(account.owner(), address(lender1), amount1);
                    lender1.repay(amount1, address(account));
                }
            } else if (action == 2) {
                if (amount0 != 0) {
                    ERC20 token0 = account.TOKEN0();
                    token0.safeTransferFrom(address(account), account.owner(), amount0);
                }
                if (amount1 != 0) {
                    ERC20 token1 = account.TOKEN1();
                    token1.safeTransferFrom(address(account), account.owner(), amount1);
                }
            }
        }
    }
}
