// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console.sol";
import {Setup} from "./utils/Setup.sol";
import {IMorphoAaveV2Lender} from "../interfaces/IMorphoAaveV2Lender.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract FactoryTest is Setup {
    function setUp() public override {
        super.setUp();
    }

    function testSetupStrategyFactoryOK() public {
        console.log("address of strategy factory", address(strategyFactory));
        assertTrue(address(0) != address(strategyFactory));
        assertEq(strategyFactory.management(), management);
        assertEq(
            strategyFactory.performanceFeeRecipient(),
            performanceFeeRecipient
        );
        assertEq(strategyFactory.keeper(), keeper);
    }

    function test_deploy(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        IMorphoAaveV2Lender strat1 = IMorphoAaveV2Lender(
            strategyFactory.newMorphoLender(
                tokenAddrs["USDC"],
                "USDC-morpho",
                aaveTokenAddrs["USDC"]
            )
        );
        // there is a problem with USDT approval
        // IMorphoAaveV2Lender strat2 = IMorphoAaveV2Lender(
        //     strategyFactory.newMorphoLender(
        //         tokenAddrs["USDT"],
        //         "USDT-morpho",
        //         aaveTokenAddrs["USDT"]
        //     )
        // );
        IMorphoAaveV2Lender strat3 = IMorphoAaveV2Lender(
            strategyFactory.newMorphoLender(
                tokenAddrs["DAI"],
                "DAI-morpho",
                aaveTokenAddrs["DAI"]
            )
        );
        IMorphoAaveV2Lender strat4 = IMorphoAaveV2Lender(
            strategyFactory.newMorphoLender(
                tokenAddrs["WBTC"],
                "WBTC-morpho",
                aaveTokenAddrs["WBTC"]
            )
        );
        IMorphoAaveV2Lender strat5 = IMorphoAaveV2Lender(
            strategyFactory.newMorphoLender(
                tokenAddrs["WETH"],
                "WETH-morpho",
                aaveTokenAddrs["WETH"]
            )
        );

        strategy_testing(strat1, _amount);
        // strategy_testing(strat2, _amount * 1e2);
        strategy_testing(strat3, _amount * 1e12);
        strategy_testing(strat4, _amount);
        strategy_testing(strat5, _amount * 1e10);
    }

    function strategy_testing(
        IMorphoAaveV2Lender _strategy,
        uint256 _amount
    ) internal {
        ERC20 _asset = ERC20(_strategy.asset());
        console.log(_amount);
        // Deposit into strategy
        mintAndDepositIntoStrategy(_strategy, user, _amount, _asset);

        // TODO: Implement logic so totalDebt is _amount and totalIdle = 0.
        checkStrategyTotals(_strategy, _amount, _amount, 0);

        // Earn Interest
        skip(20 days);
        vm.roll(block.number + 1);

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = _strategy.report();

        // Check return Values
        assertGe(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");

        skip(_strategy.profitMaxUnlockTime());

        uint256 balanceBefore = _asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        _strategy.redeem(_amount, user, user);

        assertGe(
            _asset.balanceOf(user),
            balanceBefore + _amount,
            "!final balance"
        );
    }
}
