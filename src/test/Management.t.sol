// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import "forge-std/console.sol";
import {Setup} from "./utils/Setup.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ManagementTest is Setup {
    function setUp() public override {
        super.setUp();
    }

    function testMaxGasForMatching() public {
        uint256 maxGasForMatching = 100;

        // user cannot change maxGasForMatching
        vm.prank(user);
        vm.expectRevert("!Authorized");
        strategy.setMaxGasForMatching(maxGasForMatching);

        // management can change maxGasForMatching
        vm.prank(management);
        strategy.setMaxGasForMatching(maxGasForMatching);
        assertEq(strategy.maxGasForMatching(), maxGasForMatching);
    }

    function testRewardsDistributor() public {
        address rewardsDistbutor = address(0);

        // user cannot change rewardsDistbutor
        vm.prank(user);
        vm.expectRevert("!Authorized");
        strategy.setRewardsDistributor(rewardsDistbutor);

        // management can change rewardsDistbutor
        vm.prank(management);
        strategy.setRewardsDistributor(rewardsDistbutor);
        assertEq(strategy.rewardsDistributor(), rewardsDistbutor);

        // claim rewards will revert on rewardsDistributor = address(0)
        vm.prank(management);
        bytes32[] memory empty = new bytes32[](0);
        vm.expectRevert("!rewardsDistributor");
        strategy.claimMorphoRewards(user, 100, empty);
    }

    function testTradeFactory() public {
        ERC20 morpho = ERC20(0x9994E35Db50125E0DF82e4c2dde62496CE330999);
        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = address(morpho);
        assertEq(strategy.tradeFactory(), address(0));
        assertEq(strategy.rewardTokens(), rewardTokens);

        address tradeFactory = address(
            0xd6a8ae62f4d593DAf72E2D7c9f7bDB89AB069F06
        );

        // user cannot change tradeFactory
        vm.prank(user);
        vm.expectRevert("!yChad");
        strategy.setTradeFactory(tradeFactory);

        // management can change tradeFactory
        address yChad = 0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52;
        vm.startPrank(yChad);
        strategy.setTradeFactory(tradeFactory);
        assertEq(strategy.tradeFactory(), tradeFactory);
        assertEq(
            morpho.allowance(address(strategy), strategy.tradeFactory()),
            type(uint256).max,
            "!allowance"
        );

        // management can disable tradeFactory
        vm.startPrank(yChad);
        strategy.setTradeFactory(address(0));
        assertEq(strategy.tradeFactory(), address(0));
        assertEq(
            morpho.allowance(address(strategy), tradeFactory),
            0,
            "!allowance"
        );
    }
}
