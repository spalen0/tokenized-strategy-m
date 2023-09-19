// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {MorphoAaveV2Lender} from "./MorphoAaveV2Lender.sol";
import {IMorphoAaveV2Lender} from "./interfaces/IMorphoAaveV2Lender.sol";
import {IMorphoAaveV2Factory} from "./interfaces/IMorphoAaveV2Factory.sol";

contract MorphoAaveV2Factory is IMorphoAaveV2Factory {
    event NewMorphoAaveV2Lender(
        address indexed strategy,
        address indexed asset
    );

    address public management;
    address public performanceFeeRecipient;
    address public keeper;

    constructor(
        address _management,
        address _performanceFeeRecipient,
        address _keeper
    ) {
        management = _management;
        performanceFeeRecipient = _performanceFeeRecipient;
        keeper = _keeper;
    }

    /**
     * @notice Deploye a new Aave V3 Lender.
     * @dev This will set the msg.sender to all of the permisioned roles.
     * @param _asset The underlying asset for the lender to use.
     * @param _name The name for the lender to use.
     * @return . The address of the new lender.
     */
    function newMorphoLender(
        address _asset,
        string memory _name,
        address _aToken
    ) external returns (address) {
        // We need to use the custom interface with the
        // tokenized strategies available setters.
        IMorphoAaveV2Lender newStrategy = IMorphoAaveV2Lender(
            address(new MorphoAaveV2Lender(_asset, _name, _aToken))
        );

        newStrategy.setPerformanceFeeRecipient(performanceFeeRecipient);

        newStrategy.setKeeper(keeper);

        newStrategy.setPendingManagement(management);

        emit NewMorphoAaveV2Lender(address(newStrategy), _asset);
        return address(newStrategy);
    }

    function setAddresses(
        address _management,
        address _performanceFeeRecipient,
        address _keeper
    ) external {
        require(msg.sender == management, "!management");
        management = _management;
        performanceFeeRecipient = _performanceFeeRecipient;
        keeper = _keeper;
    }
}
