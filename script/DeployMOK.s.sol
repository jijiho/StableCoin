// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {MOKEngine} from "../src/MOKEngine.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
contract DeployMOK is Script {
    address[] public tokenAddress;
    address[] public priceFeedAddresses;
    function run() external returns(DecentralizedStableCoin, MOKEngine, HelperConfig) {
        HelperConfig config = new HelperConfig();

        (address wethUsdPriceFeed, address wbtcPriceFeed, address weth, address wbtc, uint256 deployerKey) = config.activeNetworkConfig();

        tokenAddress = [weth, wbtc];
        priceFeedAddresses = [wethUsdPriceFeed, wbtcPriceFeed];


        vm.startBroadcast(deployerKey);
        DecentralizedStableCoin mok = new DecentralizedStableCoin();
        MOKEngine engine = new MOKEngine(tokenAddress, priceFeedAddresses, address(mok));

        mok.transferOwnership(address(engine));
        vm.stopBroadcast();

        return(mok, engine, config);
    }
    
}
