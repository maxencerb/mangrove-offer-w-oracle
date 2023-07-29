# Mangrove Offer with price oracle

The goal here is to create a Direct offer for [Mangrove exchange](https://www.mangrove.exchange/) linked with a Price oracle to limit slippage when a taker takes the offer.

e.g. If we create an order to sell an asset `base_asset` at 1000 USDC at some point, the offer could be taken much later. In this case, the price of the `base_asset` could have changed and the taker would pay the `base_asset` with a discount. If the asset is valued at 1200 USDC, then it would be a 20% loss for the maker.

## Choices

### The market

We will only allow assets which have a pair with a chainlink USD pair. This is to ensure that we have a reliable price feed for the asset.

In a future implementation, we could allow creating price routes with multiple pairs in order to include more assets.

The orcale contact should be inputted by the user as a source. This could also be done with a forwader contract by listing assets price source contracts like aave-core v3.

### Chainlink Oracle

Chainlink Oracle is a great choice for this project because it is an oracle with a great track record. It is also very easy to use and has a great documentation.

## Installation

### Prerequisites

View the [installation guide](https://docs.mangrove.exchange/strat-lib/getting-started/preparation) from Mangrove for more info on how to get started.

Here, only run `npm i` and create a `.env` file with the following variables:

```shell
# Default keys for forge and default anvil url
export PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
export ADMIN_ADDRESS=0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266
# Put a polygon mainnet RPC URL here
export RPC_URL=<YOUR_POLYGON_RPC_URL>
export LOCAL_URL=http://127.0.0.1:8545
```

## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

- **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
- **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
- **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
- **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
