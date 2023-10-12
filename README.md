# Aloe II

This repository contains smart contracts for the Aloe II Protocol.

## Bug Bounty

Certain contracts in this repository are covered in Aloe Labs'
[Immunefi bug bounty program](https://immunefi.com/bounty/aloeprotocol/).

## Disclaimer

This is experimental software and is provided on an "as is" and "as available" basis. We **do not provide any
warranties** and **will not be liable for any loss incurred** through any use of this codebase.

## Usage

This is just a snippet. See [here](https://github.com/aloelabs/aloe-ii-examples) for further examples.

```bash
forge install aloelabs/aloe-ii
```

```solidity
import {Borrower, IManager} from "aloe-ii-core/Borrower.sol";
import {zip} from "aloe-ii-core/libraries/Positions.sol";

contract MyManager is IManager {
    /**
     * @notice An example of what you can do with a `Borrower` － in this case,
     * borrowing both pair assets and creating a Uniswap V3 position.
     * @dev To trigger this callback, you'd create a `Borrower` and call
     * `yourBorrower.modify(this, "", 1 << 32)`. Within this callback, you
     * have full control of the `Borrower` and its assets.
     * @param data Encoded parameters that were passed to `Borrower.modify`
     * @param owner The owner of the `Borrower` (NOT to be trusted unless you verify that the caller
     * is, in fact, a `Borrower` using `factory.isBorrower(msg.sender)`)
     * @param positions The `Borrower`'s current Uniswap positions. You can convert them to an array using
     * `Positions.extract`
     * @return Updated positions, encoded using `Positions.zip`. Return 0 if you don't wish to make any changes.
     */
    function callback(
        bytes calldata data,
        address owner,
        uint208 positions
    ) external returns (uint208) {
        account.borrow(1e18, 1500e6, msg.sender);
        account.uniswapDeposit(202650, 202660, uint128(99999999));

        return zip([202650, 202660, 0, 0, 0, 0]);
    }
}
```

> [!NOTE]
> For some reason, certain versions of Foundry fail to auto-detect our `solady`
> remapping. To fix this, add `'solady/=lib/aloe-ii/core/lib/solady/src'` to your
> remappings list in `foundry.toml`

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
|-- Exp -- "Exponential function (e^x)"
|-- LiquidityAmounts -- "Translates liquidity to amounts or vice versa"
|-- Log2 -- "Logarithm and exponentiation in base 2"
|-- MulDiv -- "Multiply and divide with 512 bit precision"
|-- Oracle -- "Provides functions to integrate with Uniswap V3 oracle"
|-- Positions -- "Packs Uniswap positions into Borrower's storage efficiently"
|-- Rewards -- "Implements logic for staking rewards"
|-- TickMath -- "Translates ticks to prices or vice versa"
|-- Volatility -- "Computes implied volatility from observed swap fee earnings"
```

## Development

We recommend the following extensions in VS Code:

- Solidity _by Nomic Foundation_
- Solidity Language & Themes _by tintinweb_
- TODO Highlight _by Wayou Liu_ (use custom settings to highlight "NOTE"s as well as "TODO"s)
- Coverage Gutters _by ryanluker_ (to see code coverage)
- SARIF Viewer _by Microsoft DevLabs_ (to see Slither output)

### Solidity

If you don't have Foundry installed, follow the instructions [here](https://book.getfoundry.sh/getting-started/installation).

```bash
git clone https://github.com/aloelabs/aloe-ii.git
cd aloe-ii
git submodule update --init --recursive

cd core # or periphery
forge build

# For gas snapshots (results in .gas-snapshot)
./snapshot.sh
# For storage layout (results in .storage-layout.md)
./layout.sh
# For gambit mutation testing
./gambit.sh
# For slither code analysis (run, then cmd+shift+p > SARIF: Show Panel)
./slither.sh
# For code coverage (run, then cmd+shift+p > Coverage Gutters: Display Coverage)
./test.sh
```

> [!NOTE]
> LiquidityAmounts.t.sol does differential testing using Python and `--ffi`. Borrower.t.sol uses tmux, anvil,
> and `--ffi` to do fuzz testing without burning through RPC credits. To avoid these and just run the basic
> test suite, use:
> ```bash
> forge test -vv --no-match-contract ".*Gas|BorrowerTest" --no-match-test "historical|Ffi"
> ```

### Linting

```bash
yarn install
yarn lint
```

### Documentation

Generated docs for master are available [here](https://aloelabs.github.io/aloe-ii/). If you want to build locally, you'll
need to [install mdBook](https://rust-lang.github.io/mdBook/guide/installation.html), then:

```bash
./docs.sh
mdbook serve docs
```
