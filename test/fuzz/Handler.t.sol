// SPDX-License-Identifier: MIT
//Thi shandler will help with ensuring the random function calls are called in order

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract Handler is Test {
    DSCEngine dsce;
    DecentralizedStableCoin dsc;

    ERC20Mock weth;
    ERC20Mock wbtc;

    uint256 public timesMintIsCalled;
    address[] public usersWithCollateralDeposited;
    MockV3Aggregator public wethPriceFeed;
    MockV3Aggregator public wbtcPriceFeed;

    uint256 MAX_DEPOSIT_SIZE = type(uint96).max;

    constructor(DSCEngine _dsce, DecentralizedStableCoin _dsc) {
        dsce = _dsce;
        dsc = _dsc;

        address[] memory collateralTokens = dsce.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);

        wethPriceFeed = MockV3Aggregator(dsce.getCollateralTokenPriceFeed(address(weth)));
        wbtcPriceFeed = MockV3Aggregator(dsce.getCollateralTokenPriceFeed(address(wbtc)));
    }

    function mintDsc(uint256 amountDsc, uint256 addressSeed) public {
        if(usersWithCollateralDeposited.length == 0) {
            return; // No users with collateral deposited
        }
        
        address sender = usersWithCollateralDeposited[addressSeed % usersWithCollateralDeposited.length];
        
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(sender); // Ensure the account is initialized
        int256 maxDscToMint = ((int256(collateralValueInUsd) / 2) - int256(totalDscMinted));
        
        if(maxDscToMint < 0) {
            return; // No need to mint if maxDscToMint is negative
        }
        amountDsc = bound(amountDsc, 1, uint256(maxDscToMint));
        if(amountDsc == 0) {
            return; // No need to mint if amount is zero
        }

        vm.startPrank(sender);
        dsce.mintDsc(amountDsc);
        vm.stopPrank();
        timesMintIsCalled++;
    }

    //redeem collateral
    function depositeCollateral(
        uint256 collateralSeed,
        uint256 amountCollateral
    ) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(dsce), amountCollateral);

        dsce.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
        //should check to see if already in array
        // if(usersWithCollateralDeposited.length == 0 || usersWithCollateralDeposited[usersWithCollateralDeposited.length - 1] != msg.sender) {
        //     return; // No need to add if the user is already in the list
        // }
        usersWithCollateralDeposited.push(msg.sender);
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 maxCollateralToRedeem = dsce.getCollateralBalanceOfUser(address(collateral), msg.sender);


        amountCollateral = bound(amountCollateral, 0, maxCollateralToRedeem);

        if(amountCollateral == 0) {
            return; // No need to redeem if amount is zero
        }
        dsce.redeemCollateral(address(collateral), amountCollateral);

        // (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(msg.sender); // Ensure the account is initialized
        // if(collateralValueInUsd == 0) {
        //     // Manually remove msg.sender from usersWithCollateralDeposited
        //     return; //NOT IMPLEMENTED
        // }
    }

    //Update price of ETH
    //This breaks the test suite because if the price of eth drops to fast then the protocol goes KABOOOM
    function updateCollateralPrice(uint96 newPrice) public {
        int256 newPriceInt = int256(uint256(newPrice));
        wethPriceFeed.updateAnswer(newPriceInt);
    }

    //helper
    function _getCollateralFromSeed(
        uint256 collateralSeed
    ) private view returns(ERC20Mock) {
        if(collateralSeed % 2 == 0) {
            return weth;
        } else {
            return wbtc;
        }
    }
}   

