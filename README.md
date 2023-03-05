# Sports Betting Contracts

This project contains smart contract definitions for a decentralized sports betting application, among library code, deployment scripts and comprehensive tests. The Sports Betting contract suite contains all contract functions necessary to allow users to stake and unstake ERC-20 tokens on sports matches (referred to here as 'fixtures') and claim winnings or refunds depending on the fixture result. The fixture result is denoted as H Fixtures are represented by their 'fixtureID' as defined by an external API and have an internal state which determines eligibility for e.g. staking on the fixture. The SportsOracleConsumer defines functions for the Sports Betting contract to interact with the external sports API via a decentralized oracle, which allows the contract to retrieve fixture kickoff time and result.

# SportsBetting.sol

This contract contains the major public functions for interacting with the dApp via staking/unstaking ERC-20 tokens. It also contains the business logic that determines a particular user's entitlement for claiming a certain amount of staked ERC-20 tokens as winnings or refunds depending on the fixture result. 

The fixture betting workflow is co-ordinated via the fixture's BettingState, which is an internal state representing the fixture. Fixture state transitions occur due to changes in time, e.g. the kick-off time approaches, or changes in API response, such as the fixture result becoming retrievable and therefore allowing payouts to occur. The fixture states are summarized below:
- CLOSED
  The default state of a fixture. In the CLOSED state, the fixture result cannot be staked on. 
  The state transition OPENING->CLOSED occurs if the contract receives a fixture kickoff time for the fixture which is too far ahead in the future relative to block timestamp, e.g. 1 week. 
- OPENING
  The state transition CLOSED->OPENING occurs when an oracle request to the sports API is made to retrieve the fixture kick-off time. 
- OPEN
  The OPEN state defines a fixture eligible for users to stake/unstake ERC-20 tokens on a given result.
  The state transition OPENING->OPEN occurs if the contract receives a fixture kickoff time that is in a certain time range relative to the block timestamp, e.g. block timestamp is not 1 week before the kickoff time and not within 90 minutes of it. 
- AWAITING
  The AWAITING state defines a fixture that is no longer eligible for staking, but the contract has not yet received the fixture result so payouts are not possible.
  The OPEN->AWAITING state transition occurs when the block timestamp becomes too close to the kick-off time, e.g. within 90 minutes of it. Note that this does not rely on automated functions but occurs if a stake action is taken on a fixture with such a time or if a public transition function is called.
- PAYABLE
  The PAYABLE state defines a fixture that has its result fulfilled, where the result is one of HOME, DRAW or AWAY. In this state, users can claim winnings or refunds where applicable.
  The AWAITING->PAYABLE state transition occurs if the contract receives a fixture result from the sports oracle for that fixture.
- CANCELLED
  The CANCELLED state defines a fixture that has its result fulfilled, where the result is CANCELLED. This result signifies that the fixture could not occur and ERC-20 tokens staked on any result for that fixture should be claimable by stakers.
  
TODO: 
Fixture results explanation
Fixture payout calculation explanation
Sports Oralce Consumer explanation
Foundry tests
How to run

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
