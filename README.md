# About Glif
GLIF is the first and most popular DeFi protocol for Filecoin. It's like Lido/Jito but specifically tailored to the unique nuances of the Filecoin network. 

You can see more on our website - https://glif.io

# Documentation for the Contract `LiquidityMine.sol`
The contract implements accrual basis accounting for rewards by:

1. Keeping track of how many GLIF tokens each locked token (iFIL) is worth
2. Creating atomic units of time where the accounting of the system is consistent, which gets updated on every external call of the contract. Every time a user deposits, harvests rewards, or withdraws iFIL from the liquidity mine contract, the accounting of the system updates

The liquidity mine is funded with GLF tokens, unlike masterchef, it is not a minter of GLIF tokens. There's an associated "cap" of max rewards that the contract will eventually disperse, which can be updated by the owner

Basically, as long as:

- there is at least 1 wei of locked tokens (iFIL) in the contract
- the liquidity mine contract is funded with reward tokens (GLF)
- the liquidity mine contract has not already accrued all of its "capped" rewards in distributions to users

Then stakers who have put iFIL in the liquidity mine contract will accrue rewards every block. There is a fixed amount of GLF tokens that are "distributed" in each block. "Distributed" is in quotes because tokens are not necessarily transferred out of the contract, rather they accrue to the accounts

The heart of the accrual based accounting logic lives in the internal _computeAccRewards function

The main logic there is:

- Depending on the amount of iFIL tokens staked in the LM contract, each iFIL token accrues GLF tokens each block. The accRewardsPerLockToken tracks this amount, and this number should only ever increase
- accRewardsTotal tracks the total amoutn of accrued GLF distribution, and is mainly used to check against the totalRewardCap as to not over allocate rewards that the contract can't spend. This number should also only ever increase, and always be smaller than totalRewardCap

The UserInfo struct type keeps track of the per account accounting. 

The most confusing variable in there is `rewardDebt`. In a way, you could think of `rewardDebt` as an amount of GLF tokens the staker actually owes the LM, with no expectation that it will pay those tokens back.

So the accounting works such that, you're always owed the:

`accRewardsPerLockToken * lockedTokens`

However, since the accRewardsPerLockToken may contain both (1) rewards you already claimed and (2) rewards that were accrued when you had 0 iFIL staked in the contract, the accounting uses rewardDebt to track both of these values

So when you compute the amount of tokens you're owed for a specific period of time, you can always do:

(`accRewardsPerLockToken * lockedTokens`) - rewardDebt to tell you how many tokens you've earned. Since accRewardsPerLockToken will increase and rewardDebt and lockedTokens don't change, then the tokens you earn for this period of accrual will be >0. So the contract will accrue the owed rewards to an unclaimedRewards bucket, and increase the rewardDebt to equal (`accRewardsPerLockToken * lockedTokens`) as to say the account is "up to date"

Of course the lockedTokens will change if the user deposits or withdraws iFIL, but that will trigger an accounting update beforehand.

These are some of the considered Invariants that should never be broken:

- The LM `accRewardsTotal` should always be less than or equal to `totalRewardCap`
- The LM `rewardTokensClaimed` should always be less than or equal `toaccRewardsTotal`
- The LM balanceOf GLF tokens + `rewardTokensClaimed` should always equal `totalRewardCap`

.

# Questions & Answers

Below you will find a list of questions that are meant to be read as a starting point. Here you will find answer to many relevant questions you might have and relevant information about the dev team and the protocol itself.

##  Communications

- Who's going to be the main point of contact during the audit?
Jonathan Schwartz 
Telegram: @jpschwartz

- What should be the main comms channel with the development team?
Telegram

- Should we share drafts of potentially severe issues in advance? Where? With whom?
Yes, can share immediately with Jonathan

- Would you rather have sync meetings during the course of the audit to share progress?
No async is fine unless we need a call to discuss a specific issue in more detail - can do ad hoc


##  Documentation

- What's the available documentation? Where can we find it?
The source code is well commented and I will walk the auditors through the code and architecture

- Is the documentation up-to-date?
Yes

- Does the documentation match the version of the system about to be audited?
Yes


##  Prior security work

- Is this the first audit you're getting? If not, can you share who else audited it? Can we read previous audit reports?
We've had 2 security researchers help review the code and write fuzz tests + formal verification

- Are you planning to formally verify parts of the system?
Yes

- Does your team run security-oriented tooling? Which? How (manually, CI, etc)?
Yes - forge fuzz tests, Echidna + Medusa


##  Project

- Is it possible to schedule a walkthrough of the code base with a developer? 45 min should do.
Yes

- Is the code forked from a well-known project? Or at least heavily inspired? Not necessarily as a whole – perhaps some parts. If so, what features did you add / remove? Why?
No

- Is the code already in production? If so, how should we proceed if we find a critical vulnerability?
No - report to Jonathan Schwartz

- If the code isn't deployed, is it *about* to be deployed? When?
Yes, probably july/august

- To which chains are you deploying it?
FEVM Filecoin

- Is the code frozen? Or do you expect changes during the audit? Where? When? Should we periodically incorporate those changes?
There may be additional view functions added, but no core logic should be changed. 

- What are the most sensitive parts of the codebase? What are you most fearful of?
I'm not fearful of any parts of the code. I'm concerned that we're forgetting helpful functionality to provide better UX. Currently investigating issues with imprecision.


- What parts of the project would you consider the least tested?
Complex scenario analysis.


- What parts of the code where the most difficult to tackle?
Getting the math and precision precision 

- Where did you make the most changes throughout the development process?
The core math aspects, mostly in `updateAccounting` and the various view functions

- Are there any attack vectors you've already thought of? Are they documented? How's the code preventing them?
I don't see any hack vectors currently, only potential annoying UX blockers and bad upgradeability.

- What are the most relevant integrations to consider? (oracles, DEXs, tokens, bridges, etc). Can we assume these external elements to work as documented?
Filecoin FEVM has unique precompiles, so we use certain libraries to call FEVM precompiles, which are not standard on EVM. The FEVM addres space also has some unique quirks, however these things have been audited and used in production for over a year. There are no external integration besides the GLIF token, these external elements work as documented.

- Are you implementing and/or following any known ERC?
Not in this contract

- Are you using well-known libraries as dependencies? Which ones? Any specific reason why you decided to use X instead of Y?
We're using Open Zeppelin libraries where applicable. We also use our own fork of the Open Zeppelin Ownable contract that handles Filecoin native addresses.

- Are there upgradeable contracts? Which ones? What does the upgrade process look like?
The contracts are not upgradeable.


##  Roles

- What are the main roles of the system? Any permissioned role worth highlighting?
The owner of the contract can set various parameters like the 

- Can we assume whoever holds these roles is benevolent and always act in the well-being of the protocol and its users?
Yes

- Who holds the permissioned roles in reality? EOAs, multisig wallets, governance, etc.
Multisig wallet

- If there are centralized roles, are there any plans for progressive decentralization of the system? How would that look like?
We're currently working on an Open Zeppelin Governor contract with the Tally team to make progress towards these efforts.


##  Report

- What's your preferred format to have the report? Could be a single PDF, plain-text files, GitHub issues, etc.
Whatever is easiest for the auditor, we're not worried so much about a polished report.

- Is it necessary to deliver status reports as the audit progresses? How often?
No we trust the auditors will get the job done

- Are you planning to make the report public?
Depends on what we find 

.

# Getting Started

Testing tools used:

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
forge install
forge build
```

## Foundry

```solidity
forge test --mc FuzzLiquidityMine
forge test --mc FuzzLiquidityMine --mt <test>
```
## Echidna
```solidity
 echidna . --contract EchidnaLiquidityMine --config config.yaml
```

## Medusa
```solidity
medusa fuzz
```

## Halmos
```solidity
halmos --contract HalmosFVLiquidityMine --solver-timeout-assertion 0 
halmos --contract HalmosFVLiquidityMine --function <test> --solver-timeout-assertion 0
```

## Ityfuzz
```solidity
ityfuzz evm -m ItyfuzzInvariant -- forge build
ityfuzz evm -m test/Fuzz/ItyfuzzInvariant.t.sol:ItyfuzzInvariant -- forge test --mc ItyfuzzInvariant --mt <test>
```

## Kontrol

```bash
forge build --force
```

```bash
kontrol build
```

```bash
kontrol prove --match-test KontrolFVLiquidityKontrol.<test> --max-depth 10000 --no-break-on-calls --max-frontier-parallel 2 --verbose
```

```bash
kontrol view-kcfg 'KontrolFVLiquidityKontrol.testFuzz_Deposit(uint256,address)' --version <specify version>
```
or
```bash
kontrol view-kcfg KontrolFVLiquidityKontrol.testFuzz_Deposit
```
or
```bash
kontrol show KontrolFVLiquidityKontrol.testFuzz_Deposit
```