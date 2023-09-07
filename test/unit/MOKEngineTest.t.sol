// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {DeployMOK} from "../../script/DeployMOK.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {MOKEngine} from "../../src/MOKEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import "forge-std/console.sol";
contract MOKEngineTest is Test{
    DeployMOK _deployer;
    DecentralizedStableCoin _mok;
    MOKEngine _moke;
    HelperConfig _config;

    address _ethUsdPriceFeed;
    address _weth;

    function setUp() public {
        _deployer = new DeployMOK();
        (_mok, _moke, _config) = _deployer.run();
        (_ethUsdPriceFeed, ,_weth, ,) = _config.activeNetworkConfig();
    }
    
    //////////////
    //price test//
    //////////////
    function testGetUsdValue() public {
        uint256 ethAmount = 15e18;

        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = _moke.getUsdValue(_weth, ethAmount);


        assertEq(expectedUsd, actualUsd);
    }
}