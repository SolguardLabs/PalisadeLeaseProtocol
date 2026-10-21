// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { PalisadeInvariantLens } from "../src/views/PalisadeInvariantLens.sol";
import { PalisadeTestBase } from "./PalisadeTestBase.sol";

contract PalisadeOperationsTest is PalisadeTestBase {
    function testPaymentLedgerSplitsLeasePrice() public {
        _listPosition();
        _approveMarket(BOB);

        uint256 price = market.quote(positionId, 7 days).price;
        vm.prank(BOB);
        market.openLease(positionId, 7 days, price);

        uint256 ownerCredit = ledger.creditOf(address(asset), OWNER);
        uint256 protocolCredit = ledger.creditOf(address(asset), TREASURY);
        assertEq(ownerCredit + protocolCredit, price);
        assertEq(ledger.totalCredits(address(asset)), price);
        assertEq(asset.balanceOf(address(ledger)), price);

        uint256 beforeWithdrawal = asset.balanceOf(OWNER);
        vm.prank(OWNER);
        assertEq(ledger.withdrawAll(address(asset), OWNER), ownerCredit);
        assertEq(asset.balanceOf(OWNER) - beforeWithdrawal, ownerCredit);
        assertEq(ledger.totalCredits(address(asset)), protocolCredit);
    }

    function testRewardEscrowTracksFundingAndPayment() public {
        _listPosition();
        _approveMarket(BOB);
        vm.prank(BOB);
        uint256 leaseId = market.openLease(positionId, 7 days, type(uint256).max);

        _harvest(80 * UNIT);
        assertEq(escrow.availableRewards(), 80 * UNIT);
        assertEq(escrow.fundedRewardsOutstanding(), 80 * UNIT);

        vm.prank(BOB);
        assertEq(market.claimRewards(leaseId, BOB), 80 * UNIT);
        assertEq(escrow.availableRewards(), 0);
        assertEq(escrow.fundedRewardsOutstanding(), 0);
    }

    function testGuardianPauseBlocksMarketEntry() public {
        _listPosition();
        _approveMarket(BOB);
        vm.prank(GUARDIAN);
        market.setPaused(true);

        vm.prank(BOB);
        vm.expectRevert();
        market.openLease(positionId, 7 days, type(uint256).max);
        assertEq(market.activeLeaseFor(positionId), 0);
    }

    function testPrincipalAndPaymentLensesReflectCustody() public {
        PalisadeInvariantLens lens = new PalisadeInvariantLens(
            address(vault), address(market), address(escrow), address(ledger)
        );

        uint256[] memory positionIds = new uint256[](1);
        positionIds[0] = positionId;
        PalisadeInvariantLens.PrincipalConservation memory principal =
            lens.principalConservation(positionIds);
        assertEq(principal.vaultPrincipal, principal.sampledPositionPrincipal);
        assertEq(principal.vaultShares, principal.sampledPositionShares);
        assertEq(principal.vaultRewardWeight, principal.sampledPositionWeight);

        _listPosition();
        _approveMarket(BOB);
        vm.prank(BOB);
        market.openLease(positionId, 7 days, type(uint256).max);
        (bool solvent, uint256 balance, uint256 tracked) = lens.paymentLedgerSolvent(address(asset));
        assertTrue(solvent);
        assertEq(balance, tracked);
    }

    function testPositionCannotRedeemWhileLeased() public {
        _listPosition();
        _approveMarket(BOB);
        vm.prank(BOB);
        market.openLease(positionId, 7 days, type(uint256).max);

        vm.prank(OWNER);
        vm.expectRevert();
        vault.withdrawPosition(positionId, 100 * UNIT, OWNER);
        assertEq(vault.totalPrincipal(), 1000 * UNIT);
    }
}
