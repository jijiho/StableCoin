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
    address public USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
    function setUp() public {
        _deployer = new DeployMOK();
        (_mok, _moke, _config) = _deployer.run();
        (_ethUsdPriceFeed, ,_weth, ,) = _config.activeNetworkConfig();

        ERC20Mock(_weth).mint(USER, STARTING_ERC20_BALANCE);
    }
    
    //////////////
    //price test//
    //////////////
    function testGetUsdValue() public {
        uint256 ethAmount = 15e18;

        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = _moke.getUsdValue(_weth, ethAmount);


        assertEq(actualUsd, expectedUsd);
    }

    //////////////////////////////
    // depositCollateral Tests  //
    //////////////////////////////

    function testRevertIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock (_weth).approve(address(_moke), AMOUNT_COLLATERAL);

        vm.expectRevert(MOKEngine.MOKEngine__NeedsMoreThanZero.selector);
        _moke.depositCollateral(_weth,0);
        vm.stopPrank();
    }
}