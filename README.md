# Aloe II

This repository contains smart contracts for the Aloe II Protocol.

## Bug Bounty

Contracts in this repository will soon be included in Aloe Labs' Immunefi bug bounty program. In the meantime,
if you find a critical vulnerability, please reach out to us on Discord.

## Disclaimer

This is experimental software and is provided on an "as is" and "as available" basis. We **do not provide any
warranties** and **will not be liable for any loss incurred** through any use of this codebase.

## Usage

```bash
forge install aloelabs/aloe-ii
```

```solidity
import {Borrower, IManager} from "aloe-ii-core/Borrower.sol";
import {zip} from "aloe-ii-core/libraries/Positions.sol";

contract MyManager is IManager {
    Borrower immutable account;

    constructor(Borrower account_) {
        account = account_;
    }

    function callback(bytes calldata data) external returns (uint144 positions) {
        require(msg.sender == address(account));

        account.borrow(1e18, 1500e6, msg.sender);
        account.uniswapDeposit(202650, 202660, uint128(99999999));

        return zip([202650, 202660, 0, 0, 0, 0]);
    }
}
```

## Contracts

```
Borrower -- "Allows its owner to create and manage leveraged Uniswap positions"
Factory -- "Deploys new lending pairs"
Ledger -- "Contains storage and view methods for Lender"
Lender -- "Allows users to deposit and earn yield (ERC4626)"
RateModel -- "Computes interest rates from utilization"
VolatilityOracle -- "Estimates implied volatility for any Uniswap V3 pair"

libraries
|-- constants
    |-- Constants -- "Defines important protocol parameters"
    |-- Q -- "Defines Q numbers"
|-- BalanceSheet -- "Provides functions for computing a Borrower's health"
|-- LiquidityAmounts -- "Translates liquidity to amounts or vice versa"
|-- Oracle -- "Provides functions to integrate with Uniswap V3 oracle"
|-- Positions -- "Packs Uniswap positions into Borrower's storage efficiently"
|-- SafeCastLib
|-- TickMath -- "Translates ticks to prices or vice versa"
|-- Volatility -- "Computes implied volatility from observed swap fee earnings"
```

## Development

```bash
git clone https://github.com/aloelabs/aloe-ii.git
git submodule update --init --recursive

cd core # or periphery
forge build
```
