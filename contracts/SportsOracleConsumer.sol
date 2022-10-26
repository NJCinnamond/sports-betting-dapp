//SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";
import "hardhat/console.sol";

/**
 * Request testnet LINK and ETH here: https://faucets.chain.link/
 * Find information on LINK Token Contracts and get the latest ETH and LINK faucets here: https://docs.chain.link/docs/link-token-contracts/
 */

abstract contract SportsOracleConsumer is ChainlinkClient {
    using Chainlink for Chainlink.Request;

    address public chainlink;
    string public sportsOracleURI;

    bytes32 private jobId;
    uint256 private fee;

    // multiple params returned in a single oracle response
    string public fixtureResult;

    mapping(address => uint256) public userToLink;

    event RequestedFixtureKickoff(bytes32 indexed requestId, string fixtureID);

    event RequestedFixtureResult(bytes32 indexed requestId, string fixtureID);

    event RequestFixtureKickoffFulfilled(
        bytes32 indexed requestId,
        string fixtureID,
        uint256 kickoff
    );

    event RequestFixtureResultFulfilled(
        bytes32 indexed requestId,
        string fixtureID,
        uint256 result
    );

    /**
     * @notice Initialize the link token and target oracle
     * @dev The oracle address must be an Operator contract for multiword response
     *
     *
     * Kovan Testnet details:
     * Link Token: 0xa36085F69e2889c224210F603D836748e7dC0088
     * Oracle: 0x74EcC8Bdeb76F2C6760eD2dc8A46ca5e581fA656 (Chainlink DevRel)
     * jobId: 53f9755920cd451a8fe46f5087468395
     *
     */
    constructor(
        string memory _sportsOracleURI,
        address _oracle,
        address _link,
        bytes32 _jobId,
        uint256 _fee
    ) {
        sportsOracleURI = _sportsOracleURI;
        setChainlinkToken(_link);
        setChainlinkOracle(_oracle);
        chainlink = _oracle;
        //jobId = _jobId;
        jobId = "ca98366cc7314957b8c012c72f05aeeb";
        fee = _fee;
    }

    modifier hasLinkFee() {
        require(userToLink[msg.sender] > fee, "You haven't sent enough LINK.");
        _;
    }

    /**
     * @notice Request fixture kickoff time from the oracle in a single transaction
     */
    function requestFixtureKickoffTimeParameter(string memory fixtureID)
        public
        hasLinkFee
        returns (bytes32)
    {
        // User spends LINK value = fee on this request
        userToLink[msg.sender] -= fee;

        Chainlink.Request memory req = buildChainlinkRequest(
            jobId,
            address(this),
            this.rawFulfillFixtureKickoffTime.selector
        );
        req.add("get", string.concat(sportsOracleURI, fixtureID));
        req.add("path", "0,ko");
        req.addInt("times", 1);
        return sendChainlinkRequest(req, fee); // MWR API.
    }

    function rawFulfillFixtureKickoffTime(bytes32 _requestId, uint256 _ko)
        public
        recordChainlinkFulfillment(_requestId)
    {
        require(msg.sender == chainlink, "Only ChainlinkClient can fulfill");
        fulfillFixtureKickoffTime(_requestId, _ko);
    }

    function fulfillFixtureKickoffTime(bytes32 _requestId, uint256 _ko)
        internal
        virtual;

    /**
     * @notice Request fixture result from the oracle in a single transaction
     */
    function requestFixtureResultParameter(string memory fixtureID)
        public
        hasLinkFee
        returns (bytes32)
    {
        // User spends LINK value = fee on this request
        userToLink[msg.sender] -= fee;

        Chainlink.Request memory req = buildChainlinkRequest(
            jobId,
            address(this),
            this.rawFulfillFixtureResult.selector
        );
        req.add("get", string.concat(sportsOracleURI, fixtureID));
        req.add("path", "0,result");
        req.addInt("times", 1);
        return sendChainlinkRequest(req, fee); // MWR API.
    }

    function rawFulfillFixtureResult(bytes32 _requestId, uint256 _result)
        public
        recordChainlinkFulfillment(_requestId)
    {
        require(msg.sender == chainlink, "Only ChainlinkClient can fulfill");
        fulfillFixtureResult(_requestId, _result);
    }

    function fulfillFixtureResult(bytes32 _requestId, uint256 _result)
        internal
        virtual;

    // Anybody can transfer LINK to ctx
    function transferLink(uint256 amount) public {
        LinkTokenInterface link = LinkTokenInterface(chainlinkTokenAddress());
        require(
            link.transferFrom(msg.sender, address(this), amount),
            "Unable to transfer"
        );

        userToLink[msg.sender] += amount;
    }

    /**
     * Allow withdraw of Link tokens from the contract
     */
    function withdrawLink(uint256 amount) public {
        require(amount <= userToLink[msg.sender], "You don't have enough link");
        userToLink[msg.sender] -= amount;

        LinkTokenInterface link = LinkTokenInterface(chainlinkTokenAddress());
        require(link.transfer(msg.sender, amount), "Unable to transfer");
    }
}
