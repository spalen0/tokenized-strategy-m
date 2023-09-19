// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import "forge-std/console.sol";
import {Setup} from "./utils/Setup.sol";

contract OperationTest is Setup {
    function setUp() public override {
        super.setUp();
    }

    function testSetupStrategyOK() public {
        console.log("address of strategy", address(strategy));
        assertTrue(address(0) != address(strategy));
        assertEq(strategy.asset(), address(asset));
        assertEq(strategy.management(), management);
        assertEq(strategy.performanceFeeRecipient(), performanceFeeRecipient);
        assertEq(strategy.keeper(), keeper);
        // DONE: add additional check on strat params
        // assertEq(strategy.morpho(), 0x777777c9898D384F785Ee44Acfe945efDFf5f3E0);
        // assertEq(strategy.lens(), 0x507fA343d0A90786d86C7cd885f5C49263A91FF4);
        assertEq(strategy.aToken(), aaveTokenAddrs[asset.symbol()]);
    }

    function test_operation(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        // DONE: Implement logic so totalDebt is _amount and totalIdle = 0.
        checkStrategyTotals(strategy, _amount, _amount, 0);

        // Earn Interest
        skip(1 days);

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Check return Values
        assertGe(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");

        skip(strategy.profitMaxUnlockTime());

        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        // collect all earned fees
        uint256 expectedFees = (profit * strategy.performanceFee()) / MAX_BPS;
        redeemAll(strategy, performanceFeeRecipient);
        assertGe(
            asset.balanceOf(performanceFeeRecipient),
            expectedFees,
            "!fee balance"
        );

        // DONE: Adjust if there are fees
        checkStrategyTotals(strategy, 0, 0, 0);

        assertGe(
            asset.balanceOf(user),
            balanceBefore + _amount,
            "!final balance"
        );
    }

    function test_profitableReport(
        uint256 _amount,
        uint16 _profitFactor
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
        _profitFactor = uint16(bound(uint256(_profitFactor), 10, MAX_BPS));

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        // DONE: Implement logic so totalDebt is _amount and totalIdle = 0.
        checkStrategyTotals(strategy, _amount, _amount, 0);

        // Earn Interest
        skip(1 days);

        // DONE: implement logic to simulate earning interest.
        skip(30 days);

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Check return Values
        assertGe(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");

        skip(strategy.profitMaxUnlockTime());

        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        // collect all earned fees
        uint256 expectedFees = (profit * strategy.performanceFee()) / MAX_BPS;
        redeemAll(strategy, performanceFeeRecipient);
        assertGe(
            asset.balanceOf(performanceFeeRecipient),
            expectedFees,
            "!fee balance"
        );

        // DONE: Adjust if there are fees
        checkStrategyTotals(strategy, 0, 0, 0);

        assertGe(
            asset.balanceOf(user),
            balanceBefore + _amount,
            "!final balance"
        );
    }

    function test_profitableReport_withFees(
        uint256 _amount,
        uint16 _profitFactor
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
        _profitFactor = uint16(bound(uint256(_profitFactor), 10, MAX_BPS));

        // Set protofol fee to 0 and perf fee to 10%
        setFees(0, 1_000);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        // DONE: Implement logic so totalDebt is _amount and totalIdle = 0.
        checkStrategyTotals(strategy, _amount, _amount, 0);

        // Earn Interest
        skip(1 days);

        // DONE: implement logic to simulate earning interest.
        skip(30 days);

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Check return Values
        assertGe(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");

        skip(strategy.profitMaxUnlockTime());

        // Get the expected fee
        uint256 expectedShares = (profit * 1_000) / MAX_BPS;

        assertEq(strategy.balanceOf(performanceFeeRecipient), expectedShares);

        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        // DONE: Adjust if there are fees
        assertGe(
            asset.balanceOf(user),
            balanceBefore + _amount,
            "!final balance"
        );

        vm.prank(performanceFeeRecipient);
        strategy.redeem(
            expectedShares,
            performanceFeeRecipient,
            performanceFeeRecipient
        );

        checkStrategyTotals(strategy, 0, 0, 0);

        assertGe(
            asset.balanceOf(performanceFeeRecipient),
            expectedShares,
            "!perf fee out"
        );
    }

    function test_profitableReport_withMutipleUsers(
        uint256 _amount,
        uint16 _divider,
        uint16 _secondDivider
    ) public {
        uint256 maxDivider = 100000;
        vm.assume(
            _amount > minFuzzAmount * maxDivider && _amount < maxFuzzAmount
        );
        // vm.assume(_profit > minFuzzAmount * maxDivider && _profit < maxFuzzAmount);
        vm.assume(_divider > 0 && _divider < maxDivider);
        vm.assume(_secondDivider > 0 && _secondDivider < maxDivider);

        // profit must be below 100%
        uint256 _profit = _amount / 10;
        address secondUser = address(22);
        address thirdUser = address(33);
        uint256 secondUserAmount = _amount / _divider;
        uint256 thirdUserAmount = _amount / _secondDivider;

        mintAndDepositIntoStrategy(strategy, user, _amount);
        mintAndDepositIntoStrategy(strategy, secondUser, secondUserAmount);
        mintAndDepositIntoStrategy(strategy, thirdUser, thirdUserAmount);

        // DONE: Implement logic so totalDebt is _amount and totalIdle = 0.
        uint256 strategyTotal = _amount + secondUserAmount + thirdUserAmount;
        checkStrategyTotals(strategy, strategyTotal, strategyTotal, 0);

        // Earn Interest
        skip(1 days);
        // drop some addtional profit
        airdrop(asset, address(strategy), _profit);

        // DONE: implement logic to simulate earning interest.
        skip(30 days);

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();
        uint256 totalProfit = profit;

        // Check return Values
        assertGe(profit, _profit, "!profit"); // profit should be at least airdrop amount
        assertEq(loss, 0, "!loss");

        skip(strategy.profitMaxUnlockTime());

        //withdraw part of the funds
        vm.prank(user);
        strategy.redeem(_amount / 8, user, user);
        vm.prank(secondUser);
        strategy.redeem(secondUserAmount / 6, secondUser, secondUser);
        vm.prank(thirdUser);
        strategy.redeem(thirdUserAmount / 4, thirdUser, thirdUser);

        // Skip some time, this will earn some profit in aave
        skip(3 days);

        // Report profit
        vm.prank(keeper);
        (profit, loss) = strategy.report();
        totalProfit += profit;

        // Check return Values
        assertGe(profit, 0, "!profit"); // no airdrop so profit can be mininmal
        assertEq(loss, 0, "!loss");

        skip(strategy.profitMaxUnlockTime());

        // withdraw all funds
        redeemAll(strategy, user);
        redeemAll(strategy, secondUser);
        redeemAll(strategy, thirdUser);

        // verify users earned profit
        assertGt(asset.balanceOf(user), _amount, "!final balance");
        assertGt(
            asset.balanceOf(secondUser),
            secondUserAmount,
            "!final balance"
        );
        assertGt(asset.balanceOf(thirdUser), thirdUserAmount, "!final balance");

        // collect all earned fees
        uint256 expectedFees = (totalProfit * strategy.performanceFee()) /
            MAX_BPS;
        redeemAll(strategy, performanceFeeRecipient);
        assertGe(
            asset.balanceOf(performanceFeeRecipient),
            expectedFees,
            "!fee balance"
        );

        // verify vault is empty
        checkStrategyTotals(strategy, 0, 0, 0);
    }

    function test_tendTrigger(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        assertTrue(!strategy.tendTrigger());

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertTrue(!strategy.tendTrigger());

        // Skip some time
        skip(1 days);

        assertTrue(!strategy.tendTrigger());

        vm.prank(keeper);
        strategy.report();

        assertTrue(!strategy.tendTrigger());

        // Unlock Profits
        skip(strategy.profitMaxUnlockTime());

        assertTrue(!strategy.tendTrigger());

        vm.prank(user);
        strategy.redeem(_amount, user, user);

        assertTrue(!strategy.tendTrigger());
    }

    function test_investLooseBalance(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        // DONE: Implement logic so totalDebt is _amount and totalIdle = 0.
        checkStrategyTotals(strategy, _amount, _amount, 0);

        // Airdrop some loose assets
        uint256 airdropAmount = _amount / 10;
        airdrop(asset, address(strategy), airdropAmount);
        assertEq(asset.balanceOf(address(strategy)), airdropAmount);

        // Report profit
        vm.prank(keeper);
        strategy.report();

        // Verify strategy has invested loose asset on report
        assertEq(asset.balanceOf(address(strategy)), 0);
    }
}
