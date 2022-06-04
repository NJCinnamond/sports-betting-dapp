//SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";
import "@chainlink/contracts/src/v0.8/ConfirmedOwner.sol";

/**
 * Request testnet LINK and ETH here: https://faucets.chain.link/
 * Find information on LINK Token Contracts and get the latest ETH and LINK faucets here: https://docs.chain.link/docs/link-token-contracts/
 */

/**
 * THIS IS AN EXAMPLE CONTRACT WHICH USES HARDCODED VALUES FOR CLARITY.
 * PLEASE DO NOT USE THIS CODE IN PRODUCTION.
 */
abstract contract SportsOracleConsumer is ChainlinkClient, ConfirmedOwner {
    using Chainlink for Chainlink.Request;

    address public chainlink;
    string public sportsOracleURI;

    bytes32 private jobId;
    uint256 private fee;

    // multiple params returned in a single oracle response
    string public fixtureResult;

    event RequestedFixtureResult(bytes32 indexed requestId, string fixtureID);

    event RequestFixtureResultFulfilled(
        bytes32 indexed requestId,
        string fixtureID,
        string fixtureResult
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
        address _chainlink,
        address _link,
        uint256 _fee,
    ) ConfirmedOwner(msg.sender) {
        chainlink = _chainlink;
        sportsOracleURI = _sportsOracleURI;
        setChainlinkToken(_chainlink);
        setChainlinkOracle(_link);
        jobId = "53f9755920cd451a8fe46f5087468395";
        fee = _fee;
    }

    /**
     * @notice Request mutiple parameters from the oracle in a single transaction
     */
    function requestMultipleParameters(string memory fixtureID)
        public
        returns (bytes32)
    {
        Chainlink.Request memory req = buildChainlinkRequest(
            jobId,
            address(this),
            this.rawFulfillMultipleParameters.selector
        );
        req.add("urlResult", string.concat(sportsOracleURI, fixtureID));
        req.add("pathResult", "Result");
        return sendChainlinkRequest(req, fee); // MWR API.
    }

    function rawFulfillMultipleParameters(
        bytes32 _requestId,
        string memory _resultResponse
    ) external {
        require(msg.sender == chainlink, "Only ChainlinkClient can fulfill");
        fulfillMultipleParameters(_requestId, _resultResponse);
    }

    function fulfillMultipleParameters(
        bytes32 _requestId,
        string memory _resultResponse
    ) internal virtual;

    /**
     * Allow withdraw of Link tokens from the contract
     */
    function withdrawLink() public onlyOwner {
        LinkTokenInterface link = LinkTokenInterface(chainlinkTokenAddress());
        require(
            link.transfer(msg.sender, link.balanceOf(address(this))),
            "Unable to transfer"
        );
    }
}
