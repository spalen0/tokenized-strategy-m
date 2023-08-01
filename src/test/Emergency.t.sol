// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import "forge-std/console.sol";
import {Setup} from "./utils/Setup.sol";
import {IMorpho} from "../interfaces/morpho/IMorpho.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract EmergencyTest is Setup {
    function setUp() public override {
        super.setUp();
    }

    function test_emergencyWithdraw(
        uint256 _deposit,
        uint256 _withdraw
    ) public {
        // don't withdraw all, test for that is below
        _deposit = bound(_deposit, minFuzzAmount * 2, maxFuzzAmount);
        _withdraw = bound(_withdraw, minFuzzAmount, _deposit - minFuzzAmount);

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
        assertEq(
            asset.balanceOf(address(strategy)),
            _withdraw,
            "!emergencyWithdraw"
        );

        // User can pull his funds or max strategy funds
        uint256 limit = strategy.availableWithdrawLimit(user);
        uint256 maxRedeem = Math.min(limit, strategy.balanceOf(user));
        vm.prank(user);
        strategy.redeem(maxRedeem, user, user);

        // problem with freeFunds(1) that strategy doesn't own but user has 1 token left
        // loss is not greater than 1 token
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
        assertGe(
            asset.balanceOf(address(strategy)),
            _amount - 1,
            "!emergencyWithdrawAll"
        );

        // TODO: problem with freeFunds(1) that strategy doesn't own
        // User can pull his funds with loss
        // console.log("user balance", asset.balanceOf(user));
        // console.log("user strategy balance", strategy.balanceOf(user));
        // redeemAll(strategy, user);
        // checkStrategyTotals(strategy, 0, 0, 0);
        // assertGe(asset.balanceOf(user), _amount - 1, "!redeem");
    }
}
