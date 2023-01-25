//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.12;

library SportsBettingLib {
    // Define DEFAULT BetType = 0. 
    // DEFAULT BetType is actually invalid and acts a placeholder to catch erroneous
    // betType entries, as Solidity interprets null values as 0.
    enum BetType {
        DEFAULT,
        HOME,
        DRAW,
        AWAY
    }

    function getFixtureResultFromAPIResponse(
        uint256 _result
    ) external pure returns (BetType) {
        if (_result == uint256(BetType.HOME)) {
            return BetType.HOME;
        } else if (_result == uint256(BetType.DRAW)) {
            return BetType.DRAW;
        } else if (_result == uint256(BetType.AWAY)) {
            return BetType.AWAY;
        }
        return BetType.DEFAULT;
    }

    function getLosingFixtureOutcomes(BetType winningOutcome)
        external
        pure
        returns (BetType[] memory)
    {
        BetType[] memory losingOutcomes = new BetType[](2);

        uint256 losingOutcomesIndex = 0;
        for (uint256 i = 0; i <= uint256(BetType.AWAY); i++) {
            if (BetType(i) != winningOutcome && BetType(i) != BetType.DEFAULT) {
                losingOutcomes[losingOutcomesIndex] = BetType(i);
                losingOutcomesIndex += 1;
            }
        }
        return losingOutcomes;
    }
}