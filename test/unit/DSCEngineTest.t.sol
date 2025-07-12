// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Mock } from "../mocks/ERC20Mock.sol";
import { Test } from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {console} from "forge-std/console.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dscEngine;
    HelperConfig config;
    address ethUsdPriceFeed;
    address weth;
    address public USER = makeAddr("USER");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether; // 1000 tokens
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether; // 1000 tokens

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dscEngine, config) = deployer.run();
        (ethUsdPriceFeed,,weth,,) = config.activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

    ///////////////////////
    // Price Feed Tests
    ///////////////////////

    function testGetUsdValues() public view {
        uint256 ethAmount = 15e18; // 15 ETH
        //15e18 *2000/ETH = 30,000e18
        uint256 expectedUsdValue = 30000e18; // 30,000 USD
        uint256 actualUsd = dscEngine.getUsdValue(weth, ethAmount);
        console.log("actualUsd: %s", actualUsd);
        assertEq(actualUsd, expectedUsdValue, "USD value should be 30,000");
    }

    ///////////////////////
    // DepositCollateral Tests
    ///////////////////////

    function testRevertsIfCollateralIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__AmountMustBeGreaterThanZero.selector);
        dscEngine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

}