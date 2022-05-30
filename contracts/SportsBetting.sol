//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./SportsOracleConsumer.sol";
import "hardhat/console.sol";

contract SportsBetting is SportsOracleConsumer, Ownable {
    enum BetType {
        HOME,
        DRAW,
        AWAY
    }

    event BetStaked(
        address indexed better,
        uint256 fixtureID,
        uint256 amount,
        BetType betType
    );

    event BetUnstaked(
        address indexed better,
        uint256 fixtureID,
        BetType betType
    );

    // Entrance fee of 0.0001 Eth (10^14 Wei)
    uint256 public entranceFee = 10**14;

    string public sportsOracleURI;

    // Map each fixture ID to a map of BetType to array of addresses making that bet
    mapping(uint256 => mapping(BetType => address[])) public betters;

    // Map each fixture ID to a map of BetType to a map of address to uint representing the amount of ether bet on that result
    mapping(uint256 => mapping(BetType => mapping(address => uint256)))
        public amounts;

    // Map oracle request ID to corresponding fixture ID
    mapping(bytes32 => uint256) public requestToFixture;

    constructor(string memory _sportsOracleURI) {
        console.log(
            "Deploying a SportsBetting with sports oracle URI:",
            _sportsOracleURI
        );
        sportsOracleURI = _sportsOracleURI;
    }

    function stake(uint256 fixtureID, BetType betType) public payable {
        require(msg.value >= entranceFee, "Amount is below minimum.");
        betters[fixtureID][betType].push(msg.sender);
        amounts[fixtureID][betType][msg.sender] += msg.value;
        emit BetStaked(better, fixtureID, amount, betType);
    }

    // Removes all stake in fixtureID-BetType combo
    function unstake(uint256 fixtureID, BetType betType) public {
        require(
            betters[fixtureID][betType].contains(msg.sender),
            "No stake on this address-result."
        );
        betters[fixtureID][betType].remove(msg.sender);
        amountToUnstake = amounts[fixtureID][betType][msg.sender];
        amounts[fixtureID][betType][msg.sender] = 0;
        msg.sender.transfer(amountToUnstake);
        emit BetUnstaked(better, fixtureID, betType);
    }

    function getResult(uint256 fixtureID) public onlyOwner {
        bytes requestID = requestMultipleParameters(fixtureID);
        requestToFixture[requestID] = fixtureID;
        emit RequestedFixtureResult(fixtureID);
    }

    function fulfillMultipleParameters(
        bytes32 _requestId,
        string _resultResponse
    ) internal override recordChainlinkFulfillment(requestId) {
        uint256 fixtureID = requestToFixture[_requestId];
        emit RequestMultipleFulfilled(_requestId, fixtureID, _resultResponse);
        // TODO: Biz logic to update state and payout betters
    }
}
