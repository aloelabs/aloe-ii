// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

import {Uniswap} from "src/libraries/Uniswap.sol";

import {IManager, MarginAccount} from "src/MarginAccount.sol";

contract FrontendManager is IManager {
    function modify(
        MarginAccount account,
        uint256 borrow0,
        uint256 borrow1,
        uint256 repay0,
        uint256 repay1,
        uint256 withdraw0,
        uint256 withdraw1,
        int24[] memory lowers,
        int24[] memory uppers,
        int128[] memory liquidity
    ) external {
        bytes memory data = abi.encode(
            borrow0,
            borrow1,
            repay0,
            repay1,
            withdraw0,
            withdraw1,
            lowers,
            uppers,
            liquidity
        );

        uint256[4] memory allowances;
        allowances[0] = type(uint256).max;
        allowances[1] = type(uint256).max;
        allowances[2] = type(uint256).max;
        allowances[3] = type(uint256).max;

        account.modify(this, data, allowances);
    }

    function callback(bytes calldata data)
        external
        returns (Uniswap.Position[] memory positions, bool includeKittyReceipts)
    {
        (
            uint256 borrow0,
            uint256 borrow1,
            uint256 repay0,
            uint256 repay1,
            uint256 withdraw0,
            uint256 withdraw1,
            int24[] memory lowers,
            int24[] memory uppers,
            int128[] memory liquidity
        ) = abi.decode(data, (uint256, uint256, uint256, uint256, uint256, uint256, int24[], int24[], int128[]));

        MarginAccount account = MarginAccount(msg.sender);

        if (borrow0 != 0 || borrow1 != 0) account.borrow(borrow0, borrow1);
        if (repay0 != 0 || repay1 != 0) account.repay(repay0, repay1);
        if (withdraw0 != 0) account.KITTY0().asset().transferFrom(address(account), account.OWNER(), withdraw0);
        if (withdraw1 != 0) account.KITTY1().asset().transferFrom(address(account), account.OWNER(), withdraw1);

        for (uint256 i = 0; i < liquidity.length; i++) {
            if (liquidity[i] > 0) {
                account.uniswapDeposit(lowers[i], uppers[i], uint128(liquidity[i]));
            } else {
                account.uniswapWithdraw(lowers[i], uppers[i], uint128(-liquidity[i]));
            }
        }
    }
}
