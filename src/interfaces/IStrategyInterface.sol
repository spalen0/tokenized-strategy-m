// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";

interface IStrategyInterface is IStrategy {
    function morpho() external view returns (address);

    function lens() external view returns (address);

    function aToken() external view returns (address);

    function underlyingBalance()
        external
        view
        returns (
            uint256 balanceInP2P,
            uint256 balanceOnPool,
            uint256 totalBalance
        );

    // management
    function emergencyWithdraw(uint256 _amount) external;

    function emergencyWithdrawAll() external;

    function maxGasForMatching() external view returns (uint256);

    function setMaxGasForMatching(uint256 _maxGasForMatching) external;

    function rewardsDistributor() external view returns (address);

    function setRewardsDistributor(address _rewardsDistributor) external;

    function claimMorphoRewards(
        address _account,
        uint256 _claimable,
        bytes32[] calldata _proof
    ) external;

    function transferMorpho(address _receiver, uint256 _amount) external;
}
