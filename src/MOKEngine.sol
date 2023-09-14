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
/*
* ReentrancyGuard -> 재진입공격방지 
* 재진입공격
* 왜 막아야 하는지
* 어떻게 막는지
*/
{
    ///////////////
    //  erros   //
    //////////////
    error MOKEngine__NeedsMoreThanZero();
    error MOKEngine__TokenAddressAndPriceFeedAddressMustBeSameLength();
    error MOKEngine__NotAllowedToken();
    error MOKEngine__TransferFailed();
    error MOKEngine__BreaksHealthFactor(uint256 healthFactor);
    error MOKEngine__MintFailed();
    error MOKEngine__HealthFactorOk();
    error MOKEngine__HealthFactorImporved();


    //////////////////////
    //  State Variable  //
    //////////////////////
    uint256 private constant _ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant _PRECISION = 1e10;
    uint256 private constant _LIQUIDATION_THRESHOLD = 50; //200% overcollateralized
    uint256 private constant _LIQUIDATION_PRECISION = 100;
    uint256 private constant _MIN_HEALTH_FACTOR = 1e18; 
    uint256 private constant _LIQUIDATION_BONUS = 10; //10% bonus

    mapping(address token => address priceFeed) private _priceFeeds; // tokenToPriceFeed
    mapping(address user => mapping(address token => uint256 amount))
        private _collateralDeposited;
    mapping(address user => uint256 amountMokMinted) private _mokMinted;

    address[] private _collateralToken;

    DecentralizedStableCoin private immutable _iMok;

    ////////////////
    //   Events   //
    ////////////////
    event CollateralDeposited(
        address indexed user,
        address indexed token,
        uint256 indexed amount
    );
    event CollateralRedeemed (
        address indexed redeemFrom,
        address indexed redeemTo,
        address token,
        uint256 amount
    );

    ///////////////
    // Modifiers //
    ///////////////
    modifier moreThanZero(uint256 amount) { //amount가 0보단 커야 함
        if (amount == 0) { // amount가 0이면 (uint 타입이기 때문에 0보다 작을 수 없음)
            revert MOKEngine__NeedsMoreThanZero(); //예외 처리 : amount가 0보단 커야 함
        }
        _;
    }

    modifier isAllowedToken(address token) { // token의 주소가 0주소가 아니어야 함
        if (_priceFeeds[token] == address(0)) { // _priceFeeds[token] -> token의 가격 정보를 받아올 주소가 0주소이면
            revert MOKEngine__NotAllowedToken(); //예외 처리 : 주소가 접근 가능한 주소여야 함
        }
        _;
    }

    ///////////////
    // Functions //
    ///////////////
    constructor(
        address[] memory tokenAddress, //token의 주소를 저장할 배열
        address[] memory priceFeedAddress, //token의 가격 정보를 받아올 주소를 저장하는 배열
        address mokAddress //MOK 토큰의 주소
    ) {
        //USD Price Feed
        if (tokenAddress.length != priceFeedAddress.length) { //token 주소와 token 가격 정보의 개수가 다르면
            revert MOKEngine__TokenAddressAndPriceFeedAddressMustBeSameLength(); //예외 처리
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



    /*
     * @notice this function will deposit your collateral and minr MOK in one trasaction
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of collateral to deposit
     * @param amountMokToMint The amount of decentralized stable coin to min
     */
    function depositCollateralMintMok(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountMokToMint) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintMok(amountMokToMint);
    }

    /*
     * @notice follows CEI
     * @param tokenCollateralAddress The address of the token to deposit as Collateral
     * @parma amountCollateral The amount of Collateral to deposit
     */
    function depositCollateral(
        address tokenCollateralAddress, //담보물 token 주소
        uint256 amountCollateral //담보물 token 양
    )
        public
        moreThanZero(amountCollateral) //담보물 양 (amountCollateral)이 0보다 커야함
        isAllowedToken(tokenCollateralAddress)
        nonReentrant //재진입 공격 방지
    {
        _collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
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



    /*
     * @param tokenCollateralAddress The Collateral address to redeem
     * @param amountCollateral The amount of collateral to redeem
     * @parma amountMokToBurn The amount of MOK to burn
     * This function burns MOK and redeems underlying collateral in one transaction
     */
    function redeemCollaternalForMok(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountMokToBurn) external 
    {
        burnMok(amountMokToBurn);
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
        //redeemCollateral aleady checks health factor
    }

    /*
     * @param tokenCollateralAddress: The ERC20 token address of the collateral you're redeeming
     * @param amountCollateral: The amount of collateral you're redeeming
     * @notice This function will redeem your collateral.
     * @notice If you have DSC minted, you will not be able to redeem until you burn your DSC
     */
    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        external
        moreThanZero(amountCollateral)
        nonReentrant
    {
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }
    /*
     * @notice follows CEI
     * @param amountMokToMint The amount of decentralized stable coin to mint
     * @notice they must have more collateral value than the minimum threshould
     */
    function mintMok( // mok token mint하는 함수
        uint256 amountMokToMint // 발행할 mok의 양
    ) public moreThanZero(amountMokToMint) nonReentrant { // 발행할 MOk의 양은 0보다 커야함, 재진입방지
        _mokMinted[msg.sender] += amountMokToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = _iMok.mint(msg.sender, amountMokToMint);
        if (!minted) {
            revert MOKEngine__MintFailed();
        }
    }

    function burnMok(uint256 amount) public moreThanZero(amount){
        _burnMok(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /*
     * @param collateral The erc20 collateral address to liquidate from the user
     * @param user The who has broken the health factor, Thier _healthFactor should be below MIN_HEALTH_FACTOR
     * @param debtToCover The amount of MOK you want to burn to improve the users health factor
     * @notice You can partially liquidate a user
     * @notice You will get a liquidation bonus taking the user funds 
     * @notice: This function working assumes that the protocol will be roughly 150% overcollateralized in order for this to work.
     * @notice: A known bug would be if the protocol was only 100% collateralized, we wouldn't be able to liquidate anyone.
     * For example, if the price of the collateral plummeted before anyone could be liquidated.
     * Follows CEI : Check, Effects, Interactions
    */
    function liquidate(address collateral, address user, uint256 debtToCover) external moreThanZero(debtToCover) nonReentrant
    {
        //need to check health factor of the user
        uint256 startingUserHealthFactor = _healthFactor(user);
        if(startingUserHealthFactor >= _MIN_HEALTH_FACTOR){
            revert MOKEngine__HealthFactorOk();
        }

        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);

        uint256 bonusCollateral = (tokenAmountFromDebtCovered * _LIQUIDATION_BONUS) / _LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;
        _redeemCollateral(collateral, totalCollateralToRedeem, user, msg.sender);
        _burnMok(debtToCover, user, msg.sender);


        uint256 endingUserHealthFactor = _healthFactor(user);
        if(endingUserHealthFactor <= startingUserHealthFactor){
            revert MOKEngine__HealthFactorImporved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }
    function getHealthFactor() external view {}

    //////////////////////////////////
    // Private & Internal Functions //
    //////////////////////////////////


    /*
     * @dev Low-level internal function, do not call unless the function calling it is checking for health factors being broken
     */
    function _burnMok(uint256 amountMokToBurn, address onBehalfOf, address mokFrom) private{
        _mokMinted[onBehalfOf] -= amountMokToBurn;
        bool success = _iMok.transferFrom(mokFrom, address(this), amountMokToBurn);
        if (!success){
            revert MOKEngine__TransferFailed();
        }
        _iMok.burn(amountMokToBurn);
    }
    function _redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to) private 
    {
        _collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if(!success){
            revert MOKEngine__TransferFailed();
        }
    }
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

    function _revertIfHealthFactorIsBroken(address user) internal view {
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

    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns(uint256)
    {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(_priceFeeds[token]);
        (,int256 price,,,) = priceFeed.latestRoundData();
        return (usdAmountInWei * _PRECISION) / (uint256(price) * _ADDITIONAL_FEED_PRECISION);
    }
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
