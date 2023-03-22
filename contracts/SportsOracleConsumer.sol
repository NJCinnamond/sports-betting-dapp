//SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * Request testnet LINK and ETH here: https://faucets.chain.link/
 * Find information on LINK Token Contracts and get the latest ETH and LINK faucets here: https://docs.chain.link/docs/link-token-contracts/
 */

abstract contract SportsOracleConsumer is ChainlinkClient {
    using Chainlink for Chainlink.Request;

    address public immutable chainlink;
    string public sportsOracleURI;

    bytes32 private jobId;
    uint256 private fee;

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

    event RequestFixtureResultError(
        bytes32 indexed requestId,
        string error
    );
    
    constructor(
        string memory _sportsOracleURI,
        address _oracle,
        address _link,
        string memory _jobId,
        uint256 _fee
    ) {
        sportsOracleURI = _sportsOracleURI;
        setChainlinkToken(_link);
        setChainlinkOracle(_oracle);
        chainlink = _oracle;
        jobId = stringToBytes32(_jobId);
        fee = _fee;
    }

    modifier hasLinkFee() {
        require(userToLink[msg.sender] >= fee, "You haven't sent enough LINK.");
        _;
    }

    function stringToBytes32(string memory source)
        private
        pure
        returns (bytes32 result)
    {
        bytes memory tempEmptyStringTest = bytes(source);
        if (tempEmptyStringTest.length == 0) {
            return 0x0;
        }

        assembly {
            // solhint-disable-line no-inline-assembly
            result := mload(add(source, 32))
        }
    }

    /**
     * @notice Request fixture kickoff time from the oracle in a single transaction
     */
    function requestFixtureKickoffTimeParameter(string memory fixtureID)
        internal
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

    function rawFulfillFixtureKickoffTime(bytes32 requestId, uint256 ko)
        external
        recordChainlinkFulfillment(requestId)
    {
        require(msg.sender == chainlink, "Only ChainlinkClient can fulfill");
        fulfillFixtureKickoffTime(requestId, ko);
    }

    function fulfillFixtureKickoffTime(bytes32 requestId, uint256 ko)
        internal
        virtual;

    /**
     * @notice Request fixture result from the oracle in a single transaction
     */
    function requestFixtureResultParameter(string memory fixtureID)
        internal
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

    function rawFulfillFixtureResult(bytes32 requestId, uint256 result)
        external
        recordChainlinkFulfillment(requestId)
    {
        require(msg.sender == chainlink, "Only ChainlinkClient can fulfill");
        fulfillFixtureResult(requestId, result);
    }

    function fulfillFixtureResult(bytes32 requestId, uint256 result)
        internal
        virtual;

    // Anybody can transfer LINK to ctx
    function transferLink(uint256 amount) external {
        IERC20 link = IERC20(chainlinkTokenAddress());
        require(
            link.transferFrom(msg.sender, address(this), amount),
            "Unable to transfer"
        );

        userToLink[msg.sender] += amount;
    }

    /**
     * Allow withdraw of Link tokens from the contract
     */
    function withdrawLink(uint256 amount) external {
        require(amount <= userToLink[msg.sender], "You don't have enough link");
        userToLink[msg.sender] -= amount;

        IERC20 link = IERC20(chainlinkTokenAddress());
        require(link.transfer(msg.sender, amount), "Unable to transfer");
    }
}
