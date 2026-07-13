// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Script } from "forge-std/Script.sol";

import { LeaseLedger } from "../src/accounting/LeaseLedger.sol";
import { PalisadeLeaseMarket } from "../src/market/PalisadeLeaseMarket.sol";
import { LeasePricingOracle } from "../src/pricing/LeasePricingOracle.sol";
import { RewardEscrow } from "../src/rewards/RewardEscrow.sol";
import { PalisadePositionToken } from "../src/token/PalisadePositionToken.sol";
import { ProductiveVault } from "../src/vault/ProductiveVault.sol";
import { MarketConfig, VaultConfig } from "../src/types/PalisadeTypes.sol";

contract DeployPalisade is Script {
    function run()
        external
        returns (
            PalisadePositionToken positionToken,
            RewardEscrow escrow,
            ProductiveVault vault,
            LeasePricingOracle pricing,
            LeaseLedger ledger,
            PalisadeLeaseMarket market
        )
    {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        address guardian = vm.envOr("PALISADE_GUARDIAN", deployer);
        address treasury = vm.envOr("PALISADE_TREASURY", deployer);
        address asset = vm.envAddress("PALISADE_ASSET");

        vm.startBroadcast(deployerKey);

        positionToken =
            new PalisadePositionToken("Palisade Productive Position", "pPOS", deployer, guardian);
        escrow = new RewardEscrow(deployer, guardian, asset);
        pricing = new LeasePricingOracle(deployer, guardian);
        ledger = new LeaseLedger(deployer, guardian);

        vault = new ProductiveVault(
            asset,
            address(positionToken),
            address(escrow),
            deployer,
            guardian,
            VaultConfig({
                minDeposit: vm.envOr("PALISADE_MIN_DEPOSIT", uint256(1e18)),
                maxPositionPrincipal: vm.envOr("PALISADE_MAX_POSITION", uint256(10_000_000e18)),
                harvestFeeBps: uint16(vm.envOr("PALISADE_HARVEST_FEE_BPS", uint256(0))),
                reserveBps: 0,
                feeRecipient: treasury,
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
            deployer,
            guardian,
            MarketConfig({
                minLeaseDuration: uint40(vm.envOr("PALISADE_MIN_LEASE", uint256(1 days))),
                maxLeaseDuration: uint40(vm.envOr("PALISADE_MAX_LEASE", uint256(30 days))),
                defaultRenewalWindow: uint40(vm.envOr("PALISADE_RENEWAL_WINDOW", uint256(2 days))),
                protocolFeeBps: uint16(vm.envOr("PALISADE_PROTOCOL_FEE_BPS", uint256(200))),
                maxProtocolFeeBps: 2000,
                feeRecipient: treasury,
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

        vm.stopBroadcast();
    }
}
