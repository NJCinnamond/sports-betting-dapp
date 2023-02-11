//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.12;

library SportsBettingLib {
    // Define DEFAULT FixtureResult = 0. 
    // DEFAULT FixtureResult is actually invalid and acts a placeholder to catch erroneous
    // FixtureResult entries, as Solidity interprets null values as 0.
    // CANCELLED FixtureResult allows us to handle cases where sports fixtures are cancelled
    // and we should allow all stakers to withdraw their stakes
    enum FixtureResult {
        DEFAULT,
        CANCELLED,
        HOME,
        DRAW,
        AWAY
    }

    function getFixtureResultFromAPIResponse(
        uint256 result
    ) external pure returns (FixtureResult) {
        if (result == uint256(FixtureResult.HOME)) {
            return FixtureResult.HOME;
        } else if (result == uint256(FixtureResult.DRAW)) {
            return FixtureResult.DRAW;
        } else if (result == uint256(FixtureResult.AWAY)) {
            return FixtureResult.AWAY;
        } else if (result == uint256(FixtureResult.CANCELLED)) {
            return FixtureResult.CANCELLED;
        }
        return FixtureResult.DEFAULT;
    }

    function getLosingFixtureOutcomes(FixtureResult winningOutcome)
        external
        pure
        returns (FixtureResult[] memory)
    {
        FixtureResult[] memory losingOutcomes = new FixtureResult[](2);

        uint256 losingOutcomesIndex = 0;
        for (uint256 i = uint256(FixtureResult.HOME); i <= uint256(FixtureResult.AWAY); i++) {
            if (FixtureResult(i) != winningOutcome) {
                losingOutcomes[losingOutcomesIndex] = FixtureResult(i);
                losingOutcomesIndex += 1;
            }
        }
        return losingOutcomes;
    }
}