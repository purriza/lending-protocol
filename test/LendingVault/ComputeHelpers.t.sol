// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {TestSetup} from "../TestSetup.t.sol";
import {LendingVault} from "../../contracts/LendingVault.sol";
import {ILendingVault} from "../../contracts/interfaces/ILendingVault.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract LendingVaultHarness is LendingVault {
    function computeDebtToRepay_(uint256 currentDebt) external view returns (uint256) {
        return _computeDebtToRepay(currentDebt);
    }

    // Test helpers
    function setUserPosition_(address user, uint256 collateral, uint256 principal, uint256 userIndex, bool exists) external {
        positions[user].collateralAmount = collateral;
        positions[user].debtAmount = principal;
        positions[user].lastInterestUpdate = userIndex;
        positions[user].exists = exists;
    }

    function callTransferToTreasury_(
        address user,
        address treasuryWallet,
        uint256 debtToTransfer,
        uint256 collateralToTransfer,
        uint256 currentIndex
    ) external {
        _transferPositionToTreasury(user, treasuryWallet, debtToTransfer, collateralToTransfer, currentIndex);
    }
}

contract ComputeHelpersTest is TestSetup {
    LendingVaultHarness public harness;
    ERC1967Proxy private harnessProxy;

    function setUp() public override {
        super.setUp();

        // Deploy harness implementation and proxy-initialize to avoid InvalidInitialization
        LendingVaultHarness impl = new LendingVaultHarness();
        bytes memory data = abi.encodeWithSelector(
            LendingVault.initialize.selector,
            address(pusd),
            address(protocolConfig),
            address(wstETH)
        );
        harnessProxy = new ERC1967Proxy(address(impl), data);
        harness = LendingVaultHarness(address(harnessProxy));
    }

    function test_ComputeDebtToRepay_WhenPartialIsZero_UsesFullCurrentDebt() public view {
        // Given: a very small current debt (1 wei)
        uint256 currentDebt = 1;
        // closeFactorBps default is 5000 (50%), so partial = 1 * 5000 / 10000 = 0 => branch should return currentDebt
        uint256 toRepay = harness.computeDebtToRepay_(currentDebt);
        assertEq(toRepay, currentDebt, "Should repay full debt when partial rounds to zero");
    }

    function test_TransferPositionToTreasury_WhenInsufficientDebt_Reverts() public {
        // Arrange: user with principal = 100 ether, user index = PRECISION
        uint256 PRECISION = 1e12;
        address user = makeAddr("userDebtLow");
        harness.setUserPosition_(user, 10 ether, 100 ether, PRECISION, true);

        // Act/Assert: try to transfer more debt than currentDebt
        uint256 currentIndex = PRECISION; // so currentDebt == principal
        uint256 debtToTransfer = 200 ether;
        uint256 collatToTransfer = 1 ether;
        vm.expectRevert(abi.encodeWithSelector(
            ILendingVault.LendingVault__InsufficientRemainingDebtToTransfer.selector,
            100 ether,
            200 ether
        ));
        harness.callTransferToTreasury_(user, address(0xBEEF), debtToTransfer, collatToTransfer, currentIndex);
    }

    function test_TransferPositionToTreasury_WhenInsufficientCollateral_Reverts() public {
        // Arrange: user with collateral = 5 ether, principal = 100 ether
        uint256 PRECISION = 1e12;
        address user = makeAddr("userCollatLow");
        harness.setUserPosition_(user, 5 ether, 100 ether, PRECISION, true);

        // Act/Assert: try to transfer more collateral than available
        uint256 currentIndex = PRECISION;
        uint256 debtToTransfer = 50 ether; // within debt
        uint256 collatToTransfer = 10 ether; // exceeds available
        vm.expectRevert(abi.encodeWithSelector(
            ILendingVault.LendingVault__InsufficientRemainingCollateralToTransfer.selector,
            5 ether,
            10 ether
        ));
        harness.callTransferToTreasury_(user, address(0xBEEF), debtToTransfer, collatToTransfer, currentIndex);
    }
}


