//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.12;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";

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
        if (result <= type(uint8).max && result < 5) {
            return FixtureResult(result);
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
        for (uint256 i = uint256(FixtureResult.HOME); i <= uint256(FixtureResult.AWAY); ++i) {
            if (FixtureResult(i) != winningOutcome) {
                losingOutcomes[losingOutcomesIndex] = FixtureResult(i);
                ++losingOutcomesIndex;
            }
        }
        return losingOutcomes;
    }

    function calculateStakerObligation(
        uint256 stakerAmount,
        uint256 winningAmount,
        uint256 totalAmount
    ) public pure returns(uint256) {
        bool flag;
        uint256 stakerShare;
        uint256 obligation;
        (flag, stakerShare) = SafeMath.tryMul(totalAmount, stakerAmount);
        if (!flag) {
            revert("Overflow calculating obligation");
        }
        (flag, obligation) = SafeMath.tryDiv(stakerShare, winningAmount);
        if (!flag) {
            revert("Division by zero");
        }
        return obligation;
    }

    function calculateCommission(
        uint256 stakerObligation,
        uint256 stakerAmount,
        uint256 commissionRate
    ) public pure returns(uint256) {
        bool flag;
        uint256 profit;
        (flag, profit) = SafeMath.trySub(stakerObligation, stakerAmount);
        if (!flag) {
            revert("Underflow calculating profit");
        }
        // Divide by 10_000 as commissionRate is expressed in basis points
        return (profit * commissionRate) / 10_000;
    }
}