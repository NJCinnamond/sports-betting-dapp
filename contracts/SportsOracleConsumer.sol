//SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";

/**
 * Request testnet LINK and ETH here: https://faucets.chain.link/
 * Find information on LINK Token Contracts and get the latest ETH and LINK faucets here: https://docs.chain.link/docs/link-token-contracts/
 */

abstract contract SportsOracleConsumer is ChainlinkClient {
    using Chainlink for Chainlink.Request;

    address payable public owner;

    address public chainlink;
    string public sportsOracleURI;

    bytes32 private jobId;
    uint256 private fee;

    // multiple params returned in a single oracle response
    string public fixtureResult;

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

        // Set owner
        owner = payable(msg.sender);
    }

    /**
     * @notice Request fixture kickoff time from the oracle in a single transaction
     */
    function requestFixtureKickoffTimeParameter(string memory fixtureID)
        public
        returns (bytes32)
    {
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
        returns (bytes32)
    {
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

    /**
     * Allow withdraw of Link tokens from the contract
     */
    function withdrawLink() public {
        require(msg.sender == owner, "Only owner can withdraw LINK");
        LinkTokenInterface link = LinkTokenInterface(chainlinkTokenAddress());
        require(
            link.transfer(msg.sender, link.balanceOf(address(this))),
            "Unable to transfer"
        );
    }
}
