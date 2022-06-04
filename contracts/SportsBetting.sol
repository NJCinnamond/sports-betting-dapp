//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./SportsOracleConsumer.sol";
import "hardhat/console.sol";

contract SportsBetting is SportsOracleConsumer {
    enum BetType {
        HOME,
        DRAW,
        AWAY
    }

    event BetStaked(
        address indexed better,
        string fixtureID,
        uint256 amount,
        BetType betType
    );

    event BetUnstaked(
        address indexed better,
        string fixtureID,
        BetType betType
    );

    // Entrance fee of 0.0001 Eth (10^14 Wei)
    uint256 public entranceFee = 10**14;

    // Map each fixture ID to a map of BetType to a map of address to uint representing the amount of ether bet on that result
    mapping(string => mapping(BetType => mapping(address => uint256)))
        public amounts;

    // Map oracle request ID to corresponding fixture ID
    mapping(bytes32 => string) public requestToFixture;

    constructor(
        string memory _sportsOracleURI,
        address _chainlink,
        address _link,
        uint256 _fee
    ) SportsOracleConsumer(_sportsOracleURI, _chainlink, _link, _fee)) {
        console.log(
            "Deploying a SportsBetting with sports oracle URI:",
            _sportsOracleURI
        );
    }

    function stake(string memory fixtureID, BetType betType) public payable {
        require(msg.value >= entranceFee, "Amount is below minimum.");
        amounts[fixtureID][betType][msg.sender] += msg.value;
        emit BetStaked(msg.sender, fixtureID, msg.value, betType);
    }

    // Removes all stake in fixtureID-BetType combo
    function unstake(string memory fixtureID, BetType betType) public {
        uint256 amountToUnstake = amounts[fixtureID][betType][msg.sender];
        require(amountToUnstake > 0, "No stake on this address-result.");

        amounts[fixtureID][betType][msg.sender] = 0;
        payable(msg.sender).transfer(amountToUnstake);
        emit BetUnstaked(msg.sender, fixtureID, betType);
    }

    function getResult(string memory fixtureID) public onlyOwner {
        bytes32 requestID = requestMultipleParameters(fixtureID);
        requestToFixture[requestID] = fixtureID;
        emit RequestedFixtureResult(requestID, fixtureID);
    }

    function fulfillMultipleParameters(
        bytes32 _requestId,
        string memory _resultResponse
    ) internal override recordChainlinkFulfillment(_requestId) {
        string memory fixtureID = requestToFixture[_requestId];
        emit RequestFixtureResultFulfilled(
            _requestId,
            fixtureID,
            _resultResponse
        );
        // TODO: Biz logic to update state and payout betters
    }
}
