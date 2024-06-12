
| Section | Description |
|---------|-------------|
| [Installation](#installation) | Setup and installation requirements. |
| [Init](#init) | Initial setup and build commands. |
| [Where to Find the Tests](#where-to-find-the-tests) | Locations of different test suites. |
| [Testing Environments](#testing-environments) | Overview of testing environments: Foundry, Echidna, Halmos, and Ityfuzz. |
| [Foundry Tests](#foundry) | How to run Foundry tests and where to find them. |
| [Echidna Tests](#echidna) | Setup and execution of Echidna tests. |
| [Halmos Tests](#halmos) | Information on setting up and running Halmos tests. |
| [Ityfuzz Tests](#ityfuzz) | Details on Ityfuzz testing environment and usage. |
| [Test Coverage](#test-coverage) | Test coverage information for various contracts and functionalities. |

## Installation

To be able to use this repository, you need to have the following installed:

- [Foundry]( https://book.getfoundry.sh/getting-started/installation)
- [Echidna]( https://github.com/crytic/echidna?tab=readme-ov-file#installation)
- [Medusa](https://github.com/crytic/medusa)
- [Halmos](https://github.com/a16z/halmos/tree/main)
- [Kontrol](https://github.com/runtimeverification/kontrol/tree/master)
- [Ityfuzz](https://github.com/fuzzland/ityfuzz)


## Init:

```js
 git submodule update --init --recursive
```
```js
sudo forge build -force
```
### You can find more information on this repository:
- [Example implementation 1](https://github.com/ZealynxSecurity/Zealynx/blob/main/OurWork/Fuzzing-and-Formal-Verification/public-contests/Olas%20Protocol/Readme-Olas.md)
- [Example implementation 2](https://github.com/ZealynxSecurity/BastionWallet)
- [Example implementation 3](https://github.com/ZealynxSecurity/Portals-local/tree/main)

## Where to find the tests

You can find the tests in various folders:

`The "onchain" folder is used to compile Halmos tests as they are configured through mocks since native FV testing is not available for onchain contracts`

- Foundry in the `test/Fuzz` folder
- Echidna in the `src/Echidna` folder
- Medusa in the `src/Echidna` folder
- Halmos in the `test/FormalVerification` folder
- Kontrol in the `test/FormalVerification` folder
- Ityfuzz in the `test/Fuzz` folder


# Testing Environments


## Foundry

### Resources to set up environment and understand approach

- [Documentation](https://book.getfoundry.sh/)
- [Create Invariant Tests for DeFi AMM Smart Contract](https://youtu.be/dWyJq8KGATg?si=JGYpABuOqR-1T6m3)

### Where are tests

- Foundry in the `test/Fuzz` folder

### How to run them

#### LiquidityMine.sol

- test/Fuzz/FuzzLiquidityMine.t.sol
  
```solidity
forge test --mc FuzzLiquidityMine
forge test --mc FuzzLiquidityMine --mt <test>
```


## Echidna

### Resources to set up environment and understand approach

- [Documentation](https://secure-contracts.com/index.html)
- [Properties](https://github.com/crytic/properties)
- [echidna](https://github.com/crytic/echidna)
- [Echidna Tutorial: #2 Fuzzing with Assertion Testing Mode](https://www.youtube.com/watch?v=em8xXB9RHi4&ab_channel=bloqarl)
- [Echidna Tutorial: #1 Introduction to create Invariant tests with Solidity](https://www.youtube.com/watch?v=yUC3qzZlCkY&ab_channel=bloqarl)
- [Echidna Tutorial: Use Echidna Cheatcodes while Fuzzing](https://www.youtube.com/watch?v=SSzh5GlqteI&ab_channel=bloqarl)


### Where are tests

- Echidna in the `src/Echidna` folder

### How to run them

#### LiquidityMine.sol

- src/Echidna/EchidnaLiquidityMine.sol

```solidity
 echidna . --contract EchidnaLiquidityMine --config config.yaml
```

## Medusa

### Resources to set up environment and understand approach

- [Documentation](https://github.com/crytic/medusa)
- [Properties](https://github.com/crytic/properties)
- [echidna](https://github.com/crytic/echidna)
- [Fuzzing Smart Contracts with MEDUSA](https://youtu.be/I4MP-KXJE54?si=LolEZWBvjbgqr0be)

### Where are tests

- Medusa in the `src/Echidna` folder

### How to run them

#### LiquidityMine.sol

- src/Echidna/EchidnaLiquidityMine.sol


```solidity
medusa fuzz
```

## Halmos

### Resources to set up environment and understand approach

- [CheatCode](https://github.com/a16z/halmos-cheatcodes)
- [Documentation](https://github.com/a16z/halmos-cheatcodes)
- [Formal Verification In Practice: Halmos, Hevm, Certora, and Ityfuzz](https://allthingsfuzzy.substack.com/p/formal-verification-in-practice-halmos?r=1860oo&utm_campaign=post&utm_medium=web)
- [Examples](https://github.com/a16z/halmos/tree/main/examples)

### Where are tests

- Halmos in the `test/FormalVerification` folder

### How to run them

#### LiquidityMine.sol

- test/V2MultiAsset/Halmos/ZealynxHalmos_PortalV2.t.sol
  
```solidity
halmos --contract ZealynxHalmos_PortalV2 --solver-timeout-assertion 0
```


#### VirtualLP

- test/V2MultiAsset/Halmos/ZealynxHalmosVirtual.t.sol

```solidity
halmos --contract ZealynxHalmosVirtual --solver-timeout-assertion 0
```




## Ityfuzz

### Resources to set up environment and understand approach

- [GitHub](https://github.com/fuzzland/ityfuzz/tree/master)
- [Documentation](https://docs.ityfuzz.rs/)
- [Formal Verification In Practice: Halmos, Hevm, Certora, and Ityfuzz](https://allthingsfuzzy.substack.com/p/formal-verification-in-practice-halmos?r=1860oo&utm_campaign=post&utm_medium=web)
- [Examples](https://github.com/a16z/halmos/tree/main/examples)
- [Video examples](https://mirror.xyz/0x44bdEeB120E0fCfC40fad73883C8f4D60Dfd5A73/IQgirpcecGOqfWRozQ0vd8e5mLLjWfX5Pif2Fbynu6c)

### Where are tests

- Ityfuzz in the `test/V2MultiAsset/Ityfuzz` folder

### How to run them

- To run Ityfuzz, you need to delete the files in the "onchain" folder and comment out the files from Halmos.

#### PortalV2MultiAsset

- test/V2MultiAsset/Ityfuzz/ItyfuzzPortalV2MultiAsset.sol
  
```solidity
ityfuzz evm -m ItyfuzzPortalV2MultiAsset -- forge build

```


#### VirtualLP

- test/V2MultiAsset/Ityfuzz/ItyfuzzVirtuLp.sol

```solidity
ityfuzz evm -m ItyfuzzVirtuaLp -- forge build

```

<img width="700" alt="image" src="image/Ity.png">


# Test Coverage

`To view Foundry coverage, delete the "onchain" folder and comment out the Halmos folder`

## Echidna
