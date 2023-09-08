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

contract MOKEngine is ReentrancyGuard
{
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

    uint256 private constant _ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant _PRECISION = 1e10;
    uint256 private constant _LIQUIDATION_THRESHOLD = 50; //200% overcollateralized
    uint256 private constant _LIQUIDATION_PRECISION = 100;
    uint256 private constant _MIN_HEALTH_FACTOR = 1;

    mapping(address token => address priceFeed) private _priceFeeds; // tokenToPriceFeed
    mapping(address user => mapping(address token => uint256 amount))
        private _collateralDeposited;
    mapping(address user => uint256 amountMokMinted) private _mokMinted;

    address[] private _collateralToken;

    DecentralizedStableCoin private immutable _iMok;

    ////////////////
    //   Events   //
    ///////////////
    event CollateralDeposited(
        address indexed user,
        address indexed token,
        uint256 amount
    );

    ////////////////
    // Modifiers //
    //////////////
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert MOKEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (_priceFeeds[token] == address(0)) {
            revert MOKEngine__NotAllowedToken();
        }
        _;
    }

    ////////////////
    // Functions //
    //////////////
    constructor(
        address[] memory tokenAddress,
        address[] memory priceFeedAddress,
        address mokAddress
    ) {
        //USD Price Feed
        if (tokenAddress.length != priceFeedAddress.length) {
            revert MOKEngine__TokenAddressAndPriceFeedAddressMustBeSameLength();
        }

        for (uint256 i = 0; i < tokenAddress.length; i++) {
            _priceFeeds[tokenAddress[i]] = priceFeedAddress[i];
            _collateralToken.push(tokenAddress[i]);
        }
        _iMok = DecentralizedStableCoin(mokAddress);
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
    function depositCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    )
        external
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        _collateralDeposited[msg.sender][
            tokenCollateralAddress
        ] += amountCollateral;
        emit CollateralDeposited(
            msg.sender,
            tokenCollateralAddress,
            amountCollateral
        );
        bool succes = IERC20(tokenCollateralAddress).transferFrom(
            msg.sender,
            address(this),
            amountCollateral
        );
        if (!succes) {
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
    function mintMok(
        uint256 amountMokToMint
    ) external moreThanZero(amountMokToMint) nonReentrant {
        _mokMinted[msg.sender] += amountMokToMint;
        _revertItHealthFactorisBroken(msg.sender);
        bool minted = _iMok.mint(msg.sender, amountMokToMint);
        if (!minted) {
            revert MOKEngine__MintFailed();
        }
    }

    function burnMok() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}

    //////////////////////////////////
    // Private & Internal Functions //
    //////////////////////////////////

    function _getAccountInformation(
        address user
    )
        private
        view
        returns (uint256 totalMokMinted, uint256 collateralValueInUsd)
    {
        totalMokMinted = _mokMinted[user];
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
        (
            uint256 totalMokMinted,
            uint256 collateralValueInUsd
        ) = _getAccountInformation(user);
        uint256 collateralAdjustThreshold = (collateralValueInUsd *
            _LIQUIDATION_THRESHOLD) / _LIQUIDATION_PRECISION;
        return (collateralAdjustThreshold * _PRECISION) / totalMokMinted;
    }

    function _revertItHealthFactorisBroken(address user) internal view {
        // 1.Check health factor
        // 2.Revert if they don't

        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < _MIN_HEALTH_FACTOR) {
            revert MOKEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    //////////////////////////////////////
    // Public & External View Functions //
    //////////////////////////////////////
    function getAccountCollateralValue(
        address user
    ) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 i = 0; i < _collateralToken.length; i++) {
            address token = _collateralToken[i];
            uint256 amount = _collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getUsdValue(
        address token,
        uint256 amount
    ) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            _priceFeeds[token]
        );
        (, int256 price, , , ) = priceFeed.latestRoundData();
        return
            (uint256(price) * _ADDITIONAL_FEED_PRECISION * amount) / _PRECISION;
    }
}
