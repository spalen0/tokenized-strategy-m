// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import "forge-std/console.sol";
import {Setup} from "./utils/Setup.sol";
import {IMorpho} from "../interfaces/morpho/IMorpho.sol";

contract EmergencyTest is Setup {
    function setUp() public override {
        super.setUp();
    }

    function test_emergencyWithdraw(uint256 _deposit, uint256 _withdraw) public {
        vm.assume(_withdraw > minFuzzAmount);
        vm.assume(_deposit > _withdraw && _deposit < maxFuzzAmount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _deposit);

        // DONE: Implement logic so totalDebt is _amount and totalIdle = 0.
        checkStrategyTotals(strategy, _deposit, _deposit, 0);

        // shutdown strategy
        vm.prank(management);
        strategy.shutdownStrategy();

        // withdraw some funds
        vm.prank(management);
        strategy.emergencyWithdraw(_withdraw);
        assertEq(asset.balanceOf(address(strategy)), _withdraw, "!emergencyWithdraw");

        // User can pull his funds with loss
        redeemAll(strategy, user);

        checkStrategyTotals(strategy, 0, 0, 0);
        assertGe(asset.balanceOf(user), _deposit - 1, "!redeem");
    }

    function test_emergencyWithdrawAll(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);
        checkStrategyTotals(strategy, _amount, _amount, 0);

        // shutdown strategy
        vm.prank(management);
        strategy.shutdownStrategy();

        vm.prank(management);
        strategy.emergencyWithdraw(type(uint256).max);
        assertGe(asset.balanceOf(address(strategy)), _amount - 1, "!emergencyWithdrawAll");

        // User can pull his funds with loss
        // TODO: problem with freeFunds(1) that strategy doesn't own
        // redeemAll(strategy, user);
        // checkStrategyTotals(strategy, 0, 0, 0);
        // assertGe(asset.balanceOf(user), _amount - 1, "!redeem");
    }
}
