// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

interface IMorphoAaveV2Factory {
    function newMorphoLender(
        address _asset,
        string memory _name,
        address _aToken
    ) external returns (address);

    function management() external view returns (address);

    function performanceFeeRecipient() external view returns (address);

    function keeper() external view returns (address);

    function setAddresses(
        address _management,
        address _performanceFeeRecipient,
        address _keeper
    ) external;
}
