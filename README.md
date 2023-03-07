# Sports Betting Contracts

This project contains smart contract definitions for a decentralized sports betting application, among library code, deployment scripts and tests. The Sports Betting contract suite contains all contract functions necessary to allow addresses to stake and unstake ERC-20 tokens on sports matches (referred to here as 'fixtures') and claim winnings or refunds depending on the fixture result. The fixture result is denoted as H Fixtures are represented by their 'fixtureID' as defined by an external API and have an internal state which determines eligibility for e.g. staking on the fixture. The SportsOracleConsumer defines functions for the Sports Betting contract to interact with the external sports API via a decentralized oracle, which allows the contract to retrieve fixture kickoff time and result.

# How to deploy

You can deploy the code via hardhat-deploy to a given network via

```
npx hardhat --network <network>
```

The corresponding front-end repo depends on a reference to the deployment information, which can be exported to the repo on the same level as sports-betting-dapp at the time of deployment. The following is an example when deploying to Goerli.

```
npx hardhat --network goerli deploy --export ../sports-betting-ui/sports-betting-ui/src/deployments.json
```

# SportsBetting.sol

This contract contains the major public functions for interacting with the dApp via staking/unstaking ERC-20 tokens. It also contains the business logic that determines a particular user's entitlement for claiming a certain amount of staked ERC-20 tokens as winnings or refunds depending on the fixture result. 

The fixture betting workflow is co-ordinated via the fixture's BettingState, which is an internal state representing the fixture. Fixture state transitions occur due to changes in time, e.g. the kick-off time approaches, or changes in API response, such as the fixture result becoming retrievable and therefore allowing payouts to occur. The fixture states are summarized below:
- CLOSED
  The default state of a fixture. In the CLOSED state, the fixture result cannot be staked on. 
  The state transition OPENING->CLOSED occurs if the contract receives a fixture kickoff time for the fixture which is too far ahead in the future relative to block timestamp, e.g. 1 week. 
- OPENING
  The state transition CLOSED->OPENING occurs when an oracle request to the sports API is made to retrieve the fixture kick-off time. 
- OPEN
  The OPEN state defines a fixture eligible for addresses to stake/unstake ERC-20 tokens on a given result.
  The state transition OPENING->OPEN occurs if the contract receives a fixture kickoff time that is in a certain time range relative to the block timestamp, e.g. block timestamp is not 1 week before the kickoff time and not within 90 minutes of it. 
- AWAITING
  The AWAITING state defines a fixture that is no longer eligible for staking, but the contract has not yet received the fixture result so payouts are not possible.
  The OPEN->AWAITING state transition occurs when the block timestamp becomes too close to the kick-off time, e.g. within 90 minutes of it. Note that this does not rely on automated functions but occurs if a stake action is taken on a fixture with such a time or if a public transition function is called.
- PAYABLE
  The PAYABLE state defines a fixture that has its result fulfilled, where the result is one of HOME, DRAW or AWAY. In this state, addresses can claim winnings or refunds where applicable.
  The AWAITING->PAYABLE state transition occurs if the contract receives a fixture result from the sports oracle for that fixture.
- CANCELLED
  The CANCELLED state defines a fixture that has its result fulfilled, where the result is CANCELLED. This result signifies that the fixture could not occur and ERC-20 tokens staked on any result for that fixture should be claimable by stakers.
  
When a fixture is OPEN, addresses can call stake or unstake with the corresponding fixture_id and stake/unstake quantities to perform the stake action. This can be done infinitely many times while the fixture is in this state. If the fixture eventually becomes PAYABLE or CANCELLED, addresses can call withdrawPayout which performs different actions depending on the fixture state. 

If a fixture is PAYABLE and the user has an active stake on the winning result, the user will receive a quantity of ERC-20 tokens that represents their share of all stakes made on all results for that fixture. The amount a winning staker is owed is calculated via the SportsBettingLib library function calculateStakerObligation and is equivalent to ((totalAmount/winningAmount)*stakerAmount) where totalAmount is the total amount bet on all results for that fixture, winningAmount is the total amount bet on the correct result for that fixture, and stakerAmount is the amount bet by the staker on the winning result for that fixture.

If a fixture is CANCELLED, the user can call withdrawPayout to receive a refund for all of their stakes on that fixture.

# Fixture Result

The SportsBettingLib.FixtureResult enum defines the possible valid fixture outcomes.

- DEFAULT
- CANCELLED
- HOME
- DRAW
- AWAY

DEFAULT is a placeholder value which is used to prevent cases in which a fulfilled oracle result equal to zero is conflated with a failed oracle request fulfillment, in which the failed response may be the default uint256 value (zero). Therefore, if the contract receives a fixture result equal to zero, it is invalid and doesn't proceed.

CANCELLED is used to denote a fixture that did not occur or does not have a meaningful result. Per the workflow above, this result will change the state of the fixture to CANCELLED and allow addresses to withdraw their original stakes.

HOME, DRAW, AWAY represent the valid outcomes of a complete sports fixture. In these cases, per the workflow above, the state of the fixture will become PAYABLE and addresses that bet on the winning outcome can withdraw winnings.

NOTE: SportsBettingLib.FixtureResult is also the parameter for the stake and unstake functions that allow the address to stake/unstake on fixtures, where the parameter determines the result that the address is staking/unstaking on. Here, only HOME, DRAW and AWAY are valid values to bet on.

# SportsOracleConsumer.sol

SportsOracleConsumer contract defines the necessary functions for interaction with the external sports API via a decentralized Chainlink oracle. The SportsBetting workflow depends on external data for two purposes: retrieving fixture kickoff time, and retrieving fixture results.

- Requesting fixture kickoff time

SportsOracleConsumer exposes a function requestFixtureKickoffTimeParameter which inititates a Chainlink request to retrieve the kickoff time for the fixture with argument fixture_id. The contract defines a virtual function fulfillFixtureKickoffTime which is called with a bytes32 requestId and uint256 representing the kickoff time in UNIX timestamp format.

- Requesting fixture result

SportsOracleConsumer exposes a function requestFixtureResultParameter which inititates a Chainlink request to retrieve the result for the fixture with argument fixture_id. The contract defines a virtual function fulfillFixtureResult which is called with a bytes32 requestId and uint256 representing the result. The SportsBettingLib function getFixtureResultFromAPIResponse is used to interpret the uint256 response as SportsBettingLib.FixtureResult type (see the above section).

# Tests

A Foundry test suite is contained in test/foundry directory. The suite contains

- SportsBetting.t.sol

Unit tests for all points in the fixture staking workflow.

- SportsBettingInvariant.t.sol

Invariant tests asserting global contract state variables remain logically consistent throughout the fixture staking workflow

```shell
npx hardhat accounts
npx hardhat compile
npx hardhat clean
npx hardhat test
npx hardhat node
npx hardhat help
REPORT_GAS=true npx hardhat test
npx hardhat coverage
npx hardhat run scripts/deploy.ts
TS_NODE_FILES=true npx ts-node scripts/deploy.ts
npx eslint '**/*.{js,ts}'
npx eslint '**/*.{js,ts}' --fix
npx prettier '**/*.{json,sol,md}' --check
npx prettier '**/*.{json,sol,md}' --write
npx solhint 'contracts/**/*.sol'
npx solhint 'contracts/**/*.sol' --fix
```

# Etherscan verification

To try out Etherscan verification, you first need to deploy a contract to an Ethereum network that's supported by Etherscan, such as Ropsten.

In this project, copy the .env.example file to a file named .env, and then edit it to fill in the details. Enter your Etherscan API key, your Ropsten node URL (eg from Alchemy), and the private key of the account which will send the deployment transaction. With a valid .env file in place, first deploy your contract:

```shell
hardhat run --network ropsten scripts/deploy.ts
```

Then, copy the deployment address and paste it in to replace `DEPLOYED_CONTRACT_ADDRESS` in this command:

```shell
npx hardhat verify --network ropsten DEPLOYED_CONTRACT_ADDRESS "Hello, Hardhat!"
```

# Performance optimizations

For faster runs of your tests and scripts, consider skipping ts-node's type checking by setting the environment variable `TS_NODE_TRANSPILE_ONLY` to `1` in hardhat's environment. For more details see [the documentation](https://hardhat.org/guides/typescript.html#performance-optimizations).
