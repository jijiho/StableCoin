// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {DeployMOK} from "../../script/DeployMOK.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {MOKEngine} from "../../src/MOKEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import "forge-std/console.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";


contract MOKEngineTest is Test{
    DeployMOK _deployer;
    DecentralizedStableCoin _mok;
    MOKEngine _moke;
    HelperConfig _config;

    address _ethUsdPriceFeed;
    address _weth;
    address _btcUsdPriceFeed;
    address public testUser = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
    function setUp() public {
        _deployer = new DeployMOK();
        (_mok, _moke, _config) = _deployer.run();
        (_ethUsdPriceFeed, _btcUsdPriceFeed,_weth, ,) = _config.activeNetworkConfig();

        ERC20Mock(_weth).mint(testUser, STARTING_ERC20_BALANCE);
    }
    
    ////////////////////
    //constructor test//
    ////////////////////

    address[] public tokenAddress;
    address[] public priceFeedAddresses;
    function testRevertsIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddress.push(_weth);
        priceFeedAddresses.push(_ethUsdPriceFeed);
        priceFeedAddresses.push(_btcUsdPriceFeed);

        vm.expectRevert(MOKEngine.MOKEngine__TokenAddressAndPriceFeedAddressMustBeSameLength.selector);
        new MOKEngine(tokenAddress, priceFeedAddresses, address(_mok));
    }



    //////////////
    //price test//
    //////////////

    
    function testGetUsdValue() public {
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = 15000e18;
        uint256 actualUsd = _moke.getUsdValue(_weth, ethAmount);


        assertEq(actualUsd, expectedUsd);
    }
    
    function testGetTokenAmountFromUsd() public {
        uint256 expectedWeth = 0.1 ether;
        uint256 actualWeth = _moke.getTokenAmountFromUsd(_weth, 100 ether); 
        assertEq(expectedWeth, actualWeth);
    }
    //////////////////////////////
    // depositCollateral Tests  //
    //////////////////////////////

    function testRevertsIfCollateralZero() public {
        vm.startPrank(testUser);
        ERC20Mock (_weth).approve(address(_moke), AMOUNT_COLLATERAL);

        vm.expectRevert(MOKEngine.MOKEngine__NeedsMoreThanZero.selector);
        _moke.depositCollateral(_weth,0);
        vm.stopPrank();
    }

    function testRevertsWithUnapprovdCollateral() public {
        ERC20Mock ranToken = new ERC20Mock("RAN", "RAN", testUser, AMOUNT_COLLATERAL);
        vm.startPrank(testUser);
        vm.expectRevert(MOKEngine.MOKEngine__NotAllowedToken.selector);
        _moke.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        vm.startPrank(testUser);
        ERC20Mock(_weth).approve(address(_moke), AMOUNT_COLLATERAL);
        _moke.depositCollateral(_weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }
    function testCanDepositedCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _moke.getAccountInformation(testUser);
        uint256 expectedDepositedAmount = _moke.getTokenAmountFromUsd(_weth, collateralValueInUsd);
        assertEq(totalDscMinted, 0);
        assertEq(expectedDepositedAmount, AMOUNT_COLLATERAL);
    }

}