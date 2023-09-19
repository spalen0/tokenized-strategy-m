// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import "forge-std/console.sol";
import {ExtendedTest} from "./ExtendedTest.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {MorphoAaveV2Lender} from "../../MorphoAaveV2Lender.sol";
import {MorphoAaveV2Factory} from "../../MorphoAaveV2Factory.sol";
import {IMorphoAaveV2Lender} from "../../interfaces/IMorphoAaveV2Lender.sol";
import {IMorphoAaveV2Factory} from "../../interfaces/IMorphoAaveV2Factory.sol";

// Inherit the events so they can be checked if desired.
import {IEvents} from "@tokenized-strategy/interfaces/IEvents.sol";

interface IFactory {
    function governance() external view returns (address);

    function set_protocol_fee_bps(uint16) external;

    function set_protocol_fee_recipient(address) external;
}

contract Setup is ExtendedTest, IEvents {
    // Contract instancees that we will use repeatedly.
    ERC20 public asset;
    IMorphoAaveV2Lender public strategy;
    IMorphoAaveV2Factory public strategyFactory;

    mapping(string => address) public tokenAddrs;
    mapping(string => address) public aaveTokenAddrs;

    // Addresses for different roles we will use repeatedly.
    address public user = address(10);
    address public keeper = address(4);
    address public management = address(1);
    address public performanceFeeRecipient = address(3);

    // Address of the real deployed Factory
    address public factory;

    // Integer variables that will be used repeatedly.
    uint256 public decimals;
    uint256 public MAX_BPS = 10_000;

    // Fuzz from $0.01 of 1e6 stable coins up to 1 trillion of a 1e18 coin
    uint256 public maxFuzzAmount = 1e15; // TODO: see if we can increase this
    uint256 public minFuzzAmount = 1e6;

    // Default prfot max unlock time is set for 10 days
    uint256 public profitMaxUnlockTime = 10 days;

    function setUp() public virtual {
        _setTokenAddrs();
        _setAaveTokenAddrs();

        // Set asset
        asset = ERC20(tokenAddrs["USDC"]);

        // Set decimals
        decimals = asset.decimals();

        // Deploy strategy and set variables
        strategy = IMorphoAaveV2Lender(setUpStrategy());

        factory = strategy.FACTORY();

        strategyFactory = setUpStrategyFactory();

        // label all the used addresses for traces
        vm.label(keeper, "keeper");
        vm.label(factory, "factory");
        vm.label(address(asset), "asset");
        vm.label(management, "management");
        vm.label(address(strategy), "strategy");
        vm.label(performanceFeeRecipient, "performanceFeeRecipient");
    }

    function setUpStrategy() public returns (address) {
        address aaveToken = aaveTokenAddrs[asset.symbol()];

        // we save the strategy as a IStrategyInterface to give it the needed interface
        IMorphoAaveV2Lender _strategy = IMorphoAaveV2Lender(
            address(
                new MorphoAaveV2Lender(
                    address(asset),
                    "MorphoAaveV2Lender",
                    aaveToken
                )
            )
        );

        // set keeper
        _strategy.setKeeper(keeper);
        // set treasury
        _strategy.setPerformanceFeeRecipient(performanceFeeRecipient);
        // set management of the strategy
        _strategy.setPendingManagement(management);

        vm.prank(management);
        _strategy.acceptManagement();

        return address(_strategy);
    }

    function setUpStrategyFactory() public returns (IMorphoAaveV2Factory) {
        IMorphoAaveV2Factory _factory = IMorphoAaveV2Factory(
            address(
                new MorphoAaveV2Factory(
                    management,
                    performanceFeeRecipient,
                    keeper
                )
            )
        );
        return _factory;
    }

    function depositIntoStrategy(
        IMorphoAaveV2Lender _strategy,
        address _user,
        uint256 _amount
    ) public {
        vm.prank(_user);
        asset.approve(address(_strategy), _amount);

        vm.prank(_user);
        _strategy.deposit(_amount, _user);
    }

    function mintAndDepositIntoStrategy(
        IMorphoAaveV2Lender _strategy,
        address _user,
        uint256 _amount
    ) public {
        airdrop(asset, _user, _amount);
        depositIntoStrategy(_strategy, _user, _amount);
    }

    function mintAndDepositIntoStrategy(
        IMorphoAaveV2Lender _strategy,
        address _user,
        uint256 _amount,
        ERC20 _asset
    ) public {
        airdrop(_asset, _user, _amount);
        vm.prank(_user);
        ERC20(_asset).approve(address(_strategy), _amount);

        vm.prank(_user);
        _strategy.deposit(_amount, _user);
    }

    // For checking the amounts in the strategy
    function checkStrategyTotals(
        IMorphoAaveV2Lender _strategy,
        uint256 _totalAssets,
        uint256 _totalDebt,
        uint256 _totalIdle
    ) public {
        assertEq(_strategy.totalAssets(), _totalAssets, "!totalAssets");
        assertEq(_strategy.totalDebt(), _totalDebt, "!totalDebt");
        assertEq(_strategy.totalIdle(), _totalIdle, "!totalIdle");
        assertEq(_totalAssets, _totalDebt + _totalIdle, "!Added");
    }

    function airdrop(ERC20 _asset, address _to, uint256 _amount) public {
        uint256 balanceBefore = _asset.balanceOf(_to);
        deal(address(_asset), _to, balanceBefore + _amount);
    }

    function redeemAll(IMorphoAaveV2Lender _strategy, address _user) public {
        uint256 amount = _strategy.balanceOf(_user);
        vm.prank(_user);
        _strategy.redeem(amount, _user, _user);
    }

    function getExpectedProtocolFee(
        uint256 _amount,
        uint16 _fee
    ) public view returns (uint256) {
        uint256 timePassed = block.timestamp - strategy.lastReport();

        return (_amount * _fee * timePassed) / MAX_BPS / 31_556_952;
    }

    function setFees(uint16 _protocolFee, uint16 _performanceFee) public {
        address gov = IFactory(factory).governance();

        // Need to make sure there is a protocol fee recipient to set the fee.
        vm.prank(gov);
        IFactory(factory).set_protocol_fee_recipient(gov);

        vm.prank(gov);
        IFactory(factory).set_protocol_fee_bps(_protocolFee);

        vm.prank(management);
        strategy.setPerformanceFee(_performanceFee);
    }

    function _setTokenAddrs() internal {
        tokenAddrs["WBTC"] = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
        tokenAddrs["WETH"] = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        tokenAddrs["USDT"] = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
        tokenAddrs["DAI"] = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        tokenAddrs["USDC"] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    }

    function _setAaveTokenAddrs() internal {
        aaveTokenAddrs["WBTC"] = 0x9ff58f4fFB29fA2266Ab25e75e2A8b3503311656;
        aaveTokenAddrs["WETH"] = 0x030bA81f1c18d280636F32af80b9AAd02Cf0854e;
        aaveTokenAddrs["USDT"] = 0x3Ed3B47Dd13EC9a98b44e6204A523E766B225811;
        aaveTokenAddrs["DAI"] = 0x028171bCA77440897B824Ca71D1c56caC55b68A3;
        aaveTokenAddrs["USDC"] = 0xBcca60bB61934080951369a648Fb03DF4F96263C;
    }
}
