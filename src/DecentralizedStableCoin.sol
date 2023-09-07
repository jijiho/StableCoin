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

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/*
 * @title DecentralizedStableCoin
 * @author Jang Jiho
 * Collateral: Exogenous (BTC, ETH, XRP)
 * Minting (Stability Mechanism): Decentralized (Algorithmic)
 * Value (Relative Stability): Anchored (Pegged to USD)
 * Collateral Type: Crypto
 *
 * This is the contract meant to be owned by DSCEngine. It is a ERC20 token that can be minted and burned by the DSCEngine smart contract.
 */
contract DecentralizedStableCoin is ERC20Burnable, Ownable {
    error DecentralizedStableCoin__MustBeMoreThanZero(); //_amount가 0보다 크지 않으면 에러 발생 
    error DecentralizedStableCoin__BurnAmountExceedsBalance(); //태우려는 _amount가 balance(계좌 총액)보다 크면 에러 발생
    error DecentralizedStableCoin__NotZeroAddress();
    constructor() ERC20("MokToken", "MOK") {}//ERC20표쥰에 따라서 토큰 생성 토큰 이름 MokToken, 심볼명 MOK

    //MOk을 주고 담보물을 받아갈 때 MOK을 소각하는 함수
    function burn(uint256 _amount) public override onlyOwner { // onlyOwner 소유자만 burn 함수를 호출할 수 있음
        uint256 balance = balanceOf(msg.sender); //balance는 현재 컨트랙트를 호출한 주소가 가진 잔고
        if(_amount<=0){//소각하려는 양이 0보다 작거나 같으면 오류발생
            revert DecentralizedStableCoin__MustBeMoreThanZero();
        }
        if(balance < _amount){//소각하려는 양이 잔고보다 
            revert DecentralizedStableCoin__BurnAmountExceedsBalance();
        }
        super.burn(_amount);
    }
    function mint(address _to, uint256 _amount) external onlyOwner returns(bool) { //담보물 맡길 때 MOK 발행
        if(_to == address(0)){
            revert DecentralizedStableCoin__NotZeroAddress();
        }
        if(_amount <= 0){
            revert DecentralizedStableCoin__MustBeMoreThanZero();
        }
        _mint(_to, _amount);
        return true;
    }
}