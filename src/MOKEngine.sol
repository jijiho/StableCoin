// SPDX-License-Identifier: MIT

// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volitility coin

// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
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

pragma solidity 0.8.19;
import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/*
* @title MOKEngine
* @auther Jang Jiho
* The system is designed to be as minial as posible, and have the tokens maintain a 1 MokToken == 1$ peg.
* This stablecoin has the properties:
 * - Exogenously Collateralized
 * - Dollar Pegged
 * - Algorithmically Stable
* It is similar to DAI if DAI had no governance, no fees, and was backed by only WETH and WBTC and WXRP.
*
* Our MOK system should always be "overcollateralized". At no point, Should the value of all collateral <= the value of all the MOK
*
* @notice This contract is the core of the Decentralized Stablecoin system. It handles all the logic
* for minting and redeeming DSC, as well as depositing and withdrawing collateral.
* @notice This contract is based on the MakerDAO DSS system
*/

contract MOKEngine is ReentrancyGuard {
    ////////////////
    //  erros    //
    //////////////
    error MOKEngine__NeedsMoreThanZero();
    error MOKEngine__TokenAddressAndPriceFeedAddressMustBeSameLength();
    error MOKEngine__NotAllowedToken();
    error MOKEngine__TransferFailed();
    error MOKEngine__BreaksHealthFactor(uint256 healthFactor);
    error MOKEngine__MintFailed();
    /////////////////////////
    //  State Variable    //
    ///////////////////////

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e10;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; //200% overcollateralized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1;


    mapping(address token => address priceFeed) private s_priceFeeds; // tokenToPriceFeed
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountMokMinted) private s_MOKMinted;

    address[] private s_collateralToken;

    DecentralizedStableCoin private immutable i_mok;

     ////////////////
    //   Events   //
    ///////////////
    event CollateralDeposited(address indexed user, address indexed token, uint256 amount);

    ////////////////
    // Modifiers //
    //////////////
    modifier moreThanZero(uint256 amount){

        if(amount == 0){
            revert MOKEngine__NeedsMoreThanZero();
        }
        _;
    }
    
    modifier isAllowedToken(address token){
        if(s_priceFeeds[token] == address(0)){
            revert MOKEngine__NotAllowedToken();
        }
        _;
    }
    
    ////////////////
    // Functions //
    //////////////
    constructor(address[] memory tokenAddress, address[] memory priceFeedAddress, address mokAddress) {
        //USD Price Feed
        if(tokenAddress.length != priceFeedAddress.length){
            revert MOKEngine__TokenAddressAndPriceFeedAddressMustBeSameLength();
        }

        for(uint256 i = 0; i<tokenAddress.length; i++){
            s_priceFeeds[tokenAddress[i]] = priceFeedAddress[i];
            s_collateralToken.push(tokenAddress[i]);
        }
        i_mok = DecentralizedStableCoin(mokAddress);
    }

    /////////////////////////
    // External Functions //
    ///////////////////////
    function depositCollateralMintMok() external {}
    /*
    * @notice follows CEI
    * @param tokenCollateralAddress The address of the token to deposit as Collateral
    * @parma amountCollateral The amount of Collaterla to deposit
    *
     */
 function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        external moreThanZero(amountCollateral) isAllowedToken(tokenCollateralAddress) nonReentrant

    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool succes = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if(!succes){
            revert MOKEngine__TransferFailed();
        }
    }
    function redeemCollaternalForMok() external {}

    function redeemCollaternal() external {}

    /*
    * @notice follows CEI
    * @param amountMokToMint The amount of decentralized stable coin to mint
    * @notice they must have more collateral value than the minimum threshould
    */
    function mintMok(uint256 amountMokToMint) external moreThanZero(amountMokToMint) nonReentrant()
    {
        s_MOKMinted[msg.sender] += amountMokToMint;
        _revertItHealthFactorisBroken(msg.sender);
        bool minted = i_mok.mint(msg.sender, amountMokToMint);
        if(!minted){
            revert MOKEngine__MintFailed();
        }
    }

    function burnMok() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}

    //////////////////////////////////
    // Private & Internal Functions //
    //////////////////////////////////

    function _getAccountInformation(address user) private view returns(uint256 totalMokMinted, uint256 collateralValueInUsd) {
        totalMokMinted = s_MOKMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }
    /*
    * Health factor =  Collateral * LiquidationThreshold / TotalBorrows
    *
    * Returns how close to liquidation a user is
    *
    * If a user goes below 1, then they can get liquidated
    *
    */
    function _healthFactor(address user) private view returns (uint256) {
        //total MOK minted 
        //total collateral VALUE
        (uint256 totalMokMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        uint256 collateralAdjustThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustThreshold * PRECISION) / totalMokMinted;
    }
    function _revertItHealthFactorisBroken(address user) internal view {
        // 1.Check health factor
        // 2.Revert if they don't

        uint256 userHealthFactor = _healthFactor(user);
        if(userHealthFactor < MIN_HEALTH_FACTOR) {
            revert MOKEngine__BreaksHealthFactor(userHealthFactor);
        }
    }
    //////////////////////////////////////
    // Public & External View Functions //
    //////////////////////////////////////
    function getAccountCollateralValue(address user) public view returns(uint256 totalCollateralValueInUsd) {
        for(uint256 i=0; i<s_collateralToken.length;i++){
            address token = s_collateralToken[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }
    function getUsdValue(address token, uint256 amount) public view returns(uint256){
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (,int256 price,,,) = priceFeed.latestRoundData();
        return (uint256(price) *ADDITIONAL_FEED_PRECISION * amount) / PRECISION; 
    }
}
