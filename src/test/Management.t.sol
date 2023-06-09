// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import "forge-std/console.sol";
import {Setup} from "./utils/Setup.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract OperationTest is Setup {
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

    function testTransferMorpho() public {
        uint256 amount = minFuzzAmount;
        ERC20 morpho = ERC20(0x9994E35Db50125E0DF82e4c2dde62496CE330999);
        airdrop(morpho, address(strategy), amount);

        // user cannot transfer morpho
        vm.prank(user);
        vm.expectRevert("!Authorized");
        strategy.transferMorpho(user, amount);
        assertEq(morpho.balanceOf(user), 0);

        // management can transfer morpho but it will revert on Morpho token side
        vm.prank(management);
        vm.expectRevert("UNAUTHORIZED");
        strategy.transferMorpho(management, amount);
        assertEq(morpho.balanceOf(management), 0);
    }
}
