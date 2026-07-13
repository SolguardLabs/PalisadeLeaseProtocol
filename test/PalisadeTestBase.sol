// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";

import { LeaseLedger } from "../src/accounting/LeaseLedger.sol";
import { PalisadeLeaseMarket } from "../src/market/PalisadeLeaseMarket.sol";
import { LeasePricingOracle } from "../src/pricing/LeasePricingOracle.sol";
import { RewardEscrow } from "../src/rewards/RewardEscrow.sol";
import { PalisadePositionToken } from "../src/token/PalisadePositionToken.sol";
import { ProductiveVault } from "../src/vault/ProductiveVault.sol";
import {
    FeeSide,
    LeaseTerms,
    MarketConfig,
    RenewalMode,
    VaultConfig
} from "../src/types/PalisadeTypes.sol";

import { MockERC20 } from "./mocks/MockERC20.sol";

abstract contract PalisadeTestBase is Test {
    uint256 internal constant UNIT = 1e18;
    address internal constant OWNER = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant CAROL = address(0xCA120);
    address internal constant KEEPER = address(0xBEEF);
    address internal constant GUARDIAN = address(0x600D);
    address internal constant TREASURY = address(0x7EA5);

    MockERC20 internal asset;
    PalisadePositionToken internal positionToken;
    RewardEscrow internal escrow;
    ProductiveVault internal vault;
    LeasePricingOracle internal pricing;
    LeaseLedger internal ledger;
    PalisadeLeaseMarket internal market;

    uint256 internal positionId;

    function setUp() public virtual {
        vm.warp(1_000_000);

        asset = new MockERC20("Palisade Dollar", "pUSD", 18);
        positionToken = new PalisadePositionToken(
            "Palisade Productive Position", "pPOS", address(this), GUARDIAN
        );
        escrow = new RewardEscrow(address(this), GUARDIAN, address(asset));
        pricing = new LeasePricingOracle(address(this), GUARDIAN);
        ledger = new LeaseLedger(address(this), GUARDIAN);

        vault = new ProductiveVault(
            address(asset),
            address(positionToken),
            address(escrow),
            address(this),
            GUARDIAN,
            VaultConfig({
                minDeposit: 1 * UNIT,
                maxPositionPrincipal: 10_000_000 * UNIT,
                harvestFeeBps: 0,
                reserveBps: 0,
                feeRecipient: TREASURY,
                depositsPaused: false,
                withdrawalsPaused: false,
                harvestPaused: false
            })
        );

        market = new PalisadeLeaseMarket(
            address(vault),
            address(positionToken),
            address(escrow),
            address(pricing),
            address(ledger),
            address(this),
            GUARDIAN,
            MarketConfig({
                minLeaseDuration: 1 days,
                maxLeaseDuration: 30 days,
                defaultRenewalWindow: 2 days,
                protocolFeeBps: 200,
                maxProtocolFeeBps: 2000,
                feeRecipient: TREASURY,
                listingsPaused: false,
                leasesPaused: false,
                claimsPaused: false
            })
        );

        positionToken.setVault(address(vault));
        positionToken.setMarket(address(market));
        escrow.setVault(address(vault));
        escrow.setMarket(address(market));
        vault.setMarket(address(market));
        ledger.setMarket(address(market));

        asset.mint(OWNER, 2000 * UNIT);
        asset.mint(BOB, 2000 * UNIT);
        asset.mint(CAROL, 2000 * UNIT);
        asset.mint(KEEPER, 2000 * UNIT);

        vm.startPrank(OWNER);
        asset.approve(address(vault), type(uint256).max);
        (positionId,) = vault.deposit(1000 * UNIT, OWNER, keccak256("owner productive vault"));
        vm.stopPrank();
    }

    function _defaultTerms() internal pure returns (LeaseTerms memory) {
        return LeaseTerms({
            minDuration: 1 days,
            maxDuration: 30 days,
            renewalWindow: 2 days,
            protocolFeeBps: 200,
            ownerFeeBps: 0,
            lateFeeBps: 0,
            maxDiscountBps: 1000,
            renewalMode: RenewalMode.PublicFixed,
            feeSide: FeeSide.Owner
        });
    }

    function _listPosition() internal {
        vm.prank(OWNER);
        market.list(
            positionId,
            address(asset),
            10 * UNIT,
            5 * UNIT,
            uint40(block.timestamp + 60 days),
            _defaultTerms()
        );
    }

    function _approveMarket(address account) internal {
        vm.prank(account);
        asset.approve(address(market), type(uint256).max);
    }

    function _harvest(uint256 amount) internal {
        vm.startPrank(KEEPER);
        asset.approve(address(vault), amount);
        vault.harvestRewards(amount);
        vm.stopPrank();
    }
}
