// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {BaseTokenizedStrategy} from "@tokenized-strategy/BaseTokenizedStrategy.sol";
import {HealthCheck} from "@periphery/HealthCheck/HealthCheck.sol";
import {TradeFactorySwapper} from "@periphery/swappers/TradeFactorySwapper.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IMorpho} from "./interfaces/morpho/IMorpho.sol";
import {ILens} from "./interfaces/morpho/ILens.sol";
import {IRewardsDistributor} from "./interfaces/morpho/IRewardsDistributor.sol";

/**
 * The `TokenizedStrategy` variable can be used to retrieve the strategies
 * specifc storage data your contract.
 *
 *       i.e. uint256 totalAssets = TokenizedStrategy.totalAssets()
 *
 * This can not be used for write functions. Any TokenizedStrategy
 * variables that need to be udpated post deployement will need to
 * come from an external call from the strategies specific `management`.
 */

// NOTE: To implement permissioned functions you can use the onlyManagement and onlyKeepers modifiers

contract Strategy is BaseTokenizedStrategy, HealthCheck, TradeFactorySwapper {
    // using SafeERC20 for ERC20;

    // reward token, not currently listed
    address internal constant MORPHO_TOKEN =
        0x9994E35Db50125E0DF82e4c2dde62496CE330999;
    // used for claiming reward Morpho token
    address public rewardsDistributor =
        0x3B14E5C73e0A56D607A8688098326fD4b4292135;
    // Max gas used for matching with p2p deals
    uint256 public maxGasForMatching = 100000;

    // Morpho is a contract to handle interaction with the protocol
    IMorpho public morpho;
    // Lens is a contract to fetch data about Morpho protocol
    ILens public lens;
    // aToken = Morpho Aave Market for want token
    address public aToken;

    /// @notice Emitted when maxGasForMatching is updated.
    /// @param maxGasForMatching The new maxGasForMatching value.
    event SetMaxGasForMatching(uint256 maxGasForMatching);

    /// @notice Emitted when rewardsDistributor is updated.
    /// @param rewardsDistributor The new rewardsDistributor address.
    event SetRewardsDistributor(address rewardsDistributor);

    constructor(
        address _asset,
        string memory _name,
        address _morpho,
        address _lens,
        address _aToken
    ) BaseTokenizedStrategy(_asset, _name) {
        morpho = IMorpho(_morpho);
        lens = ILens(_lens);
        aToken = _aToken;

        IMorpho.Market memory market = morpho.market(aToken);
        require(market.underlyingToken == asset, "!asset");

        ERC20(asset).approve(_morpho, type(uint256).max);
        // add reward token for swapping
        _addToken(MORPHO_TOKEN, asset);
    }

    /*//////////////////////////////////////////////////////////////
                NEEDED TO BE OVERRIDEN BY STRATEGIST
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Should deploy up to '_amount' of 'asset' in the yield source.
     *
     * This function is called at the end of a {deposit} or {mint}
     * call. Meaning that unless a whitelist is implemented it will
     * be entirely permsionless and thus can be sandwhiched or otherwise
     * manipulated.
     *
     * @param _amount The amount of 'asset' that the strategy should attemppt
     * to deposit in the yield source.
     */
    function _deployFunds(uint256 _amount) internal override {
        morpho.supply(aToken, address(this), _amount, maxGasForMatching);
    }

    /**
     * @dev Will attempt to free the '_amount' of 'asset'.
     *
     * The amount of 'asset' that is already loose has already
     * been accounted for.
     *
     * This function is called during {withdraw} and {redeem} calls.
     * Meaning that unless a whitelist is implemented it will be
     * entirely permsionless and thus can be sandwhiched or otherwise
     * manipulated.
     *
     * Should not rely on asset.balanceOf(address(this)) calls other than
     * for diff accounting puroposes.
     *
     * Any difference between `_amount` and what is actually freed will be
     * counted as a loss and passed on to the withdrawer. This means
     * care should be taken in times of illiquidity. It may be better to revert
     * if withdraws are simply illiquid so not to realize incorrect losses.
     *
     * @param _amount, The amount of 'asset' to be freed.
     */
    function _freeFunds(uint256 _amount) internal override {
        // morpho scales down amount to max available
        // https://github.com/morpho-org/morpho-v1/blob/2b4993ccb5ace70005d340298abe631a03a065bc/src/aave-v2/ExitPositionsManager.sol#L160
        morpho.withdraw(aToken, _amount);
    }

    /**
     * @dev Internal function to harvest all rewards, redeploy any idle
     * funds and return an accurate accounting of all funds currently
     * held by the Strategy.
     *
     * This should do any needed harvesting, rewards selling, accrual,
     * redepositing etc. to get the most accurate view of current assets.
     *
     * NOTE: All applicable assets including loose assets should be
     * accounted for in this function.
     *
     * Care should be taken when relying on oracles or swap values rather
     * than actual amounts as all Strategy profit/loss accounting will
     * be done based on this returned value.
     *
     * This can still be called post a shutdown, a strategist can check
     * `TokenizedStrategy.isShutdown()` to decide if funds should be
     * redeployed or simply realize any profits/losses.
     *
     * @return _totalAssets A trusted and accurate account for the total
     * amount of 'asset' the strategy currently holds including idle funds.
     */
    function _harvestAndReport()
        internal
        override
        returns (uint256 _totalAssets)
    {
        // deposit any loose funds in the strategy
        uint256 looseAsset = _balanceAsset();
        if (looseAsset > 0 && !TokenizedStrategy.isShutdown()) {
            morpho.supply(aToken, address(this), looseAsset, maxGasForMatching);
        }
        //total assets of the strategy:
        (, , uint256 totalUnderlying) = underlyingBalance();
        _totalAssets = _balanceAsset() + totalUnderlying;
        require(_executHealthCheck(_totalAssets), "!healthcheck)");
    }

    function _balanceAsset() internal view returns (uint256) {
        return ERC20(asset).balanceOf(address(this));
    }

    /**
     * @notice Returns the value deposited in Morpho protocol
     * @return balanceInP2P Amount supplied through Morpho that is matched peer-to-peer
     * @return balanceOnPool Amount supplied through Morpho on the underlying protocol's pool
     * @return totalBalance Equals `balanceOnPool` + `balanceInP2P`
     */
    function underlyingBalance()
        public
        view
        returns (
            uint256 balanceInP2P,
            uint256 balanceOnPool,
            uint256 totalBalance
        )
    {
        (balanceInP2P, balanceOnPool, totalBalance) = lens
            .getCurrentSupplyBalanceInOf(aToken, address(this));
    }

    /*//////////////////////////////////////////////////////////////
                    OPTIONAL TO OVERRIDE BY STRATEGIST
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Optional function for strategist to override that can
     *  be called in between reports.
     *
     * If '_tend' is used tendTrigger() will also need to be overridden.
     *
     * This call can only be called by a persionned role so may be
     * through protected relays.
     *
     * This can be used to harvest and compound rewards, deposit idle funds,
     * perform needed poisition maintence or anything else that doesn't need
     * a full report for.
     *
     *   EX: A strategy that can not deposit funds without getting
     *       sandwhiched can use the tend when a certain threshold
     *       of idle to totalAssets has been reached.
     *
     * The TokenizedStrategy contract will do all needed debt and idle updates
     * after this has finished and will have no effect on PPS of the strategy
     * till report() is called.
     *
     * @param _totalIdle The current amount of idle funds that are available to deploy.
     *
    function _tend(uint256 _totalIdle) internal override {}
    */

    /**
     * @notice Returns wether or not tend() should be called by a keeper.
     * @dev Optional trigger to override if tend() will be used by the strategy.
     * This must be implemented if the strategy hopes to invoke _tend().
     *
     * @return . Should return true if tend() should be called by keeper or false if not.
     *
    function tendTrigger() public view override returns (bool) {}
    */

    /**
     * @notice Gets the max amount of `asset` that can be deposited.
     * @dev Returns 0 if the market is paused.
     * @param . The address that is depositing to the strategy.
     * @return . The avialable amount that can be deposited in terms of `asset`
     */
    function availableDepositLimit(
        address //_owner
    ) public view override returns (uint256) {
        IMorpho.MarketPauseStatus memory market = morpho.marketPauseStatus(
            aToken
        );
        if (market.isSupplyPaused || market.isWithdrawPaused) {
            // don't allow deposit if the market is paused
            return 0;
        }
        return type(uint256).max;
    }

    /**
     * @notice Gets the max amount of `asset` that can be withdrawn.
     * @dev Defaults to an unlimited amount for any address. But can
     * be overriden by strategists.
     *
     * This function will be called before any withdraw or redeem to enforce
     * any limits desired by the strategist. This can be used for illiquid
     * or sandwhichable strategies. It should never be lower than `totalIdle`.
     *
     *   EX:
     *       return TokenIzedStrategy.totalIdle();
     *
     * This does not need to take into account the `_owner`'s share balance
     * or conversion rates from shares to assets.
     *
     * @param . The address that is withdrawing from the strategy.
     * @return . The avialable amount that can be withdrawn in terms of `asset`
     */
    function availableWithdrawLimit(
        address //_owner
    ) public view override returns (uint256) {
        IMorpho.MarketPauseStatus memory market = morpho.marketPauseStatus(
            aToken
        );
        if (market.isWithdrawPaused) {
            return 0;
        }
        return type(uint256).max;
    }

    /**
     * @dev Optional function for a strategist to override that will
     * allow management to manually withdraw deployed funds from the
     * yield source if a strategy is shutdown.
     * @param _amount The amount of asset to attempt to free. Scaled to max available.
     */
    function _emergencyWithdraw(uint256 _amount) internal override {
        morpho.withdraw(aToken, _amount);
    }

    // override TradeFactory virtual function
    function _claimRewards() internal override {
        // cannot automate claiming rewards
        // see function claimMorphoRewards()
    }

    /*//////////////////////////////////////////////////////////////
                    CUSTOM MANAGEMENT FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Set the maximum amount of gas to consume to get matched in peer-to-peer.
     * @dev
     *  This value is needed in Morpho supply liquidity calls.
     *  Supplyed liquidity goes to loop with current loans on Morpho
     *  and creates a match for p2p deals. The loop starts from bigger liquidity deals.
     *  The default value set by Morpho is 100000.
     * @param _maxGasForMatching new maximum gas value for P2P matching
     */
    function setMaxGasForMatching(
        uint256 _maxGasForMatching
    ) external onlyManagement {
        maxGasForMatching = _maxGasForMatching;
        emit SetMaxGasForMatching(_maxGasForMatching);
    }

    /**
     * @notice Set new rewards distributor contract
     * @param _rewardsDistributor address of new contract
     */
    function setRewardsDistributor(
        address _rewardsDistributor
    ) external onlyManagement {
        rewardsDistributor = _rewardsDistributor;
        emit SetRewardsDistributor(_rewardsDistributor);
    }

    /**
     * @notice Claims MORPHO rewards. Use Morpho API to get the data: https://api.morpho.xyz/rewards/{address}
     * @dev See stages of Morpho rewards distibution: https://docs.morpho.xyz/usdmorpho/ages-and-epochs
     * @param _account The address of the claimer.
     * @param _claimable The overall claimable amount of token rewards.
     * @param _proof The merkle proof that validates this claim.
     */
    function claimMorphoRewards(
        address _account,
        uint256 _claimable,
        bytes32[] calldata _proof
    ) external onlyManagement {
        require(rewardsDistributor != address(0), "!rewardsDistributor");
        IRewardsDistributor(rewardsDistributor).claim(
            _account,
            _claimable,
            _proof
        );
        // event emitted in claim function
    }

    /**
     * @notice Set the trade factory contract address.
     * @dev For disabling set address(0).
     * @param _tradeFactory The address of the trade factory contract.
     */
    function setTradeFactory(address _tradeFactory) external {
        require(msg.sender == 0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52, "!yChad");
        if (_tradeFactory == address(0)) {
            _removeTradeFactoryPermissions();
        } else {
            _setTradeFactory(_tradeFactory, asset);
        }
    }
}
