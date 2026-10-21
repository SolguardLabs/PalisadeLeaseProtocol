// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { LeaseCashflowLens } from "../src/views/LeaseCashflowLens.sol";
import { LeaseQuote } from "../src/types/PalisadeTypes.sol";
import { PalisadeTestBase } from "./PalisadeTestBase.sol";

contract LeaseCashflowLensTest is PalisadeTestBase {
    LeaseCashflowLens internal lens;

    function setUp() public override {
        super.setUp();
        lens = new LeaseCashflowLens();
    }

    function testStressForecastShowsCoverageAndBreakEven() public {
        _listPosition();
        LeaseQuote memory leaseQuote = market.quote(positionId, 7 days);
        LeaseCashflowLens.Forecast memory result = lens.forecast(leaseQuote, 100 * UNIT, 5000);

        assertEq(result.quotedRent, 70 * UNIT);
        assertEq(result.ownerProceeds, 68.6 ether);
        assertEq(result.stressedRewards, 50 * UNIT);
        assertEq(result.lesseeSurplus, 0);
        assertEq(result.lesseeShortfall, 20 * UNIT);
        assertEq(result.coverageBps, 7142);
        assertEq(result.breakEvenRewardForecast, 140 * UNIT);
    }

    function testFullForecastShowsPositiveSurplus() public {
        _listPosition();
        LeaseQuote memory leaseQuote = market.quote(positionId, 7 days);
        LeaseCashflowLens.Forecast memory result = lens.forecast(leaseQuote, 100 * UNIT, 10_000);

        assertEq(result.stressedRewards, 100 * UNIT);
        assertEq(result.lesseeSurplus, 30 * UNIT);
        assertEq(result.lesseeShortfall, 0);
        assertEq(result.coverageBps, 14_285);
    }

    function testOwnerAnnualizedYieldIsReportedInBps() public view {
        assertEq(lens.annualizedOwnerYieldBps(10 * UNIT, 1000 * UNIT, 365 days), 100);
        assertEq(lens.annualizedOwnerYieldBps(10 * UNIT, 1000 * UNIT, 182 days), 200);
    }

    function testInvalidAssumptionsAreRejected() public {
        _listPosition();
        LeaseQuote memory leaseQuote = market.quote(positionId, 7 days);
        vm.expectRevert(LeaseCashflowLens.InvalidRetention.selector);
        lens.forecast(leaseQuote, 100 * UNIT, 0);
        vm.expectRevert(LeaseCashflowLens.InvalidPrincipal.selector);
        lens.annualizedOwnerYieldBps(1 * UNIT, 0, 7 days);
    }
}
