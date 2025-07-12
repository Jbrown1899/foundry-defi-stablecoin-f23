// SPDX-License-Identifier: MIT

// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volitility coin

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity 0.8.18;

import { DecentralizedStableCoin } from "./DecentralizedStableCoin.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title DSCEngine
 * @author Jason Brown
 *
 * The system is designed to be as minimal as possible, and have the tokens maintain a 1 token == $1 peg at all times.
 * This is a stablecoin with the properties:
 * - Exogenously Collateralized
 * - Dollar Pegged
 * - Algorithmically Stable
 *
 * It is similar to DAI if DAI had no governance, no fees, and was backed by only WETH and WBTC.
 *
 * Our DSC system should always be "overcollateralized". At no point, should the value of
 * all collateral < the $ backed value of all the DSC.
 *
 * @notice This contract is the core of the Decentralized Stablecoin system. It handles all the logic
 * for minting and redeeming DSC, as well as depositing and withdrawing collateral.
 * @notice This contract is based on the MakerDAO DSS system
 */
contract DSCEngine is ReentrancyGuard {
    ///////////////////
    // Errors
    ///////////////////
    error DSCEngine__AmountMustBeGreaterThanZero();
    error DscEngine__TokenMustHavePriceFeed();
    error DscEngine__TokenNoteAllowedNoPriceFeed();
    error DscEngine__TransferFailed();
    error DscEngine__TokenMustHavePositivePrice();
    error DSCEngine__BelowMinHealthFactor(uint256 healthFactor);
    error DSCEngine__MintFailed();

    ///////////////////
    // State Variables
    ///////////////////

    mapping(address token => address priceFeed) 
        public s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) 
        private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) 
        private s_DSCMinted;
    address[] 
        private s_collateralTokens;
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10; //For ETH and BTC in data.chain.link since 1e8
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THREASHOLD = 50; //The collateral is worth 50/100 of the stable coin (so half the value)
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1;

    DecentralizedStableCoin private immutable i_dsc; //dscAddress

    ///////////////////
    // Events
    ///////////////////
    event CollateralDeposited(
        address indexed user, 
        address indexed token, 
        uint256 amount);
    event CollateralWithdrawn(
        address indexed user, 
        address indexed token, 
        uint256 amount
    );


    ///////////////////
    // Modifiers
    ///////////////////
    modifier moreThanZero(uint256 _amount) {
        if (_amount <= 0) {
            revert DSCEngine__AmountMustBeGreaterThanZero();
        }
        _;
    }

    modifier isAllowedToken(address _token) {
        if (s_priceFeeds[_token] == address(0)) {
            revert DscEngine__TokenNoteAllowedNoPriceFeed();
        }
        _;
    }

    ///////////////////
    // Functions
    ///////////////////
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddress, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddress.length) {
            revert DscEngine__TokenMustHavePriceFeed();
        }

        // Initialize the USD price feeds for each token
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddress[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    ///////////////////
    // External Functions
    ///////////////////
    function depositCollateralAndMintDsc() external { }

    /**
     * @notice follows CEI
     * @param tokenCollateralAddress The address of the collateral token to deposit
     * @param amountCollateral The amount of collateral to deposit
     */
    function depositCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    )
        external
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
        {
            s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
            emit CollateralDeposited(
                msg.sender, 
                tokenCollateralAddress, 
                amountCollateral
            );
            bool success = IERC20(tokenCollateralAddress).transferFrom(
                msg.sender,
                address(this),
                amountCollateral
            );
            if(!success) {
                revert DscEngine__TransferFailed();
            }
    }

    function redeemCollateralForDsc() external { }

    function redeemCollateral() 
        external 
 
    { 

    }

    /**
     * @notice follows CEI
     * @param amountDscToMint The amount of DSC to mint
     * @notice This function allows users to redeem their collateral for DSC.
     */
    function mintDsc(uint256 amountDscToMint) 
        external 
        moreThanZero(amountDscToMint)
        nonReentrant 
        { 
            s_DSCMinted[msg.sender] += amountDscToMint;
            _revertIfHealthFactorIsBroken(msg.sender);
            bool minted = i_dsc.mint(msg.sender, amountDscToMint);
            if(!minted){
                revert DSCEngine__MintFailed();
            }
    }

    function burnDsc() external { }

    function liquidate() external { }

    function getHealthFactor() external view { }

    
    ///////////////////
    // Private & Internal view Functions
    ///////////////////
    
    function _getAccountInformation(address user) 
        private view returns(uint256 totalDscMinted,uint256 totalCollateralValue)
        {
            totalDscMinted = s_DSCMinted[user];
            totalCollateralValue = getAccountCollateralValue(user);
    }

    /**
     * uses a health factor to determine a ratio of when a user can be liquidated
     * 
     */
    function _healthFactor(address user) private view returns (uint256) {
        uint256 totalDscMinted;
        uint256 totalCollateralValueInUsd;

        (totalDscMinted, totalCollateralValueInUsd) = _getAccountInformation(user);
        uint256 collateralAdjustedForThreshold = //how much do we value the collateral
            (totalCollateralValueInUsd * LIQUIDATION_THREASHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted; // if < 1 then it should liquidated
    }
    
    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 healthFactor = _healthFactor(user);
        if(healthFactor < MIN_HEALTH_FACTOR){
            revert DSCEngine__BelowMinHealthFactor(healthFactor);
        }
    }

    ///////////////////
    // Public & External view Functions
    ///////////////////

    function getAccountCollateralValue(address user)
        public view returns (uint256 totalCollateralValueInUsd) 
        {
            for(uint256 i=0; i < s_collateralTokens.length; i++){
                address token = s_collateralTokens[i];
                uint256 amount = s_collateralDeposited[user][token];
                totalCollateralValueInUsd += getUsdValue(token,amount);
            }
        return totalCollateralValueInUsd;
    }

    function getUsdValue(address token, uint256 amount) public view returns(uint256){
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);

        (, int256 price, , , ) = priceFeed.latestRoundData();
        
        
        if (price <= 0) {
            revert DscEngine__TokenMustHavePositivePrice();
        }

        return (uint256(price) * ADDITIONAL_FEED_PRECISION * amount) / PRECISION;
    }
}
