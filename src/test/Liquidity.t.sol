// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import "forge-std/console.sol";
import {Setup} from "./utils/Setup.sol";
import {IMorpho} from "../interfaces/morpho/IMorpho.sol";

contract LiquidityTest is Setup {
    function setUp() public override {
        super.setUp();
    }

    function test_marketSupplyPaused_expectRevert() public {
        uint256 amount = minFuzzAmount * 2;

        airdrop(asset, user, amount);

        vm.prank(user);
        asset.approve(address(strategy), amount);

        // deposit only half
        vm.prank(user);
        strategy.deposit(amount / 2, user);

        address morphoOwner = address(
            0x0b9915C13e8E184951Df0d9C0b104f8f1277648B
        );
        IMorphoGov morphoGov = IMorphoGov(
            0x777777c9898D384F785Ee44Acfe945efDFf5f3E0
        );
        IMorpho morpho = IMorpho(0x777777c9898D384F785Ee44Acfe945efDFf5f3E0);

        // Pause deposit
        address market = strategy.aToken();
        assertFalse(morpho.marketPauseStatus(market).isSupplyPaused);
        vm.prank(morphoOwner);
        morphoGov.setIsSupplyPaused(market, true);
        assertTrue(morpho.marketPauseStatus(market).isSupplyPaused);

        vm.startPrank(user);
        // user should not be able to deposit
        assertEq(
            strategy.availableDepositLimit(user),
            0,
            "Max deposit should be 0"
        );

        // revert on deposit
        vm.expectRevert("ERC4626: deposit more than max");
        strategy.deposit(amount / 2, user);

        // user didn't loose any funds
        assertFalse(
            morpho.marketPauseStatus(market).isWithdrawPaused,
            "Withdraw should not be paused"
        );
        strategy.redeem(amount / 2, user, user);
        assertEq(amount, asset.balanceOf(user));
    }

    function test_marketWithdrawPaused_expectRevert() public {
        uint256 amount = minFuzzAmount * 2;

        airdrop(asset, user, amount);

        vm.prank(user);
        asset.approve(address(strategy), amount);

        // deposit only half
        vm.prank(user);
        strategy.deposit(amount / 2, user);

        // pause market
        address morphoOwner = address(
            0x0b9915C13e8E184951Df0d9C0b104f8f1277648B
        );
        IMorphoGov morphoGov = IMorphoGov(strategy.morpho());
        IMorpho morpho = IMorpho(strategy.morpho());

        // Pause withdraw
        address market = strategy.aToken();
        assertFalse(morpho.marketPauseStatus(market).isWithdrawPaused);
        vm.prank(morphoOwner);
        morphoGov.setIsWithdrawPaused(market, true);
        assertTrue(morpho.marketPauseStatus(market).isWithdrawPaused);

        vm.startPrank(user);
        // user should not be able to deposit
        assertEq(
            strategy.availableDepositLimit(user),
            0,
            "Max deposit should be 0"
        );

        // revert on deposit
        vm.expectRevert("ERC4626: deposit more than max");
        strategy.deposit(amount / 2, user);

        // user should be able to withdraw
        assertEq(
            strategy.availableWithdrawLimit(user),
            0,
            "Max withdraw should be 0"
        );
        vm.expectRevert("ERC4626: withdraw more than max");
        strategy.redeem(amount / 2, user, user);

        // user has only half of the funds, the other half is still in the strategy
        assertEq(amount / 2, asset.balanceOf(user));
        assertEq(strategy.balanceOf(user), amount / 2);
    }

    function test_aaveWithoutLiquidity() public {
        uint256 amount = maxFuzzAmount;
        mintAndDepositIntoStrategy(strategy, user, amount);

        // some asset must be on the pool, on aave
        (, uint256 balanceOnPool, ) = strategy.underlyingBalance();
        assertGt(balanceOnPool, 0, "balanceOnPool should be > 0");

        // remove all liquidity from aave market
        address market = strategy.aToken();
        vm.startPrank(market);
        asset.transfer(address(0xdEaD), asset.balanceOf(address(market)));
        assertEq(
            asset.balanceOf(address(market)),
            0,
            "market should have 0 balance"
        );
        vm.stopPrank();

        // user should not be able to withdraw or record loss
        vm.prank(user);
        vm.expectRevert();
        strategy.redeem(amount / 2, user, user);

        // user won't loose funds if the aave is without liquidity
        assertEq(strategy.balanceOf(user), amount, "user lost funds");
    }
}

interface IMorphoGov {
    function setIsSupplyPaused(address _poolToken, bool _isPaused) external;

    function setIsBorrowPaused(address _poolToken, bool _isPaused) external;

    function setIsWithdrawPaused(address _poolToken, bool _isPaused) external;

    function setIsRepayPaused(address _poolToken, bool _isPaused) external;
}
