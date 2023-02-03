//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.12;

import "../SportsBettingLib.sol";

contract SportsBettingLibTest {

    function getFixtureResultFromAPIResponseTest(
        uint256 result
    ) public pure returns (SportsBettingLib.BetType) {
        return SportsBettingLib.getFixtureResultFromAPIResponse(result);
    }

    function getLosingFixtureOutcomesTest(SportsBettingLib.BetType winningOutcome)
        public
        pure
        returns (SportsBettingLib.BetType[] memory)
    {
        return SportsBettingLib.getLosingFixtureOutcomes(winningOutcome);
    }
}