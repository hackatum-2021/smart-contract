//SPDX-License-Identifier: Unlicense
pragma solidity 0.7.0;

import "./interfaces/IBank.sol";
import "./interfaces/IPriceOracle.sol";
import "./libraries/Math.sol";
import "@openzeppelin/contracts@3.4.2-solc-0.7/token/ERC20/ERC20.sol";

contract Bank is IBank {
    address internal constant ethToken = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    
    address private hakToken;
    address private priceOracle;

    mapping(address => Account) public ETHBankAccount;
    mapping(address => Account) public HAKBankAccount;
    mapping(address => Account) public ETHBorrowed;

    constructor(address _priceOracle, address _hakToken) {
        hakToken = _hakToken;
        priceOracle = _priceOracle;
    }
    function deposit(address token, uint256 amount)
        payable
        external
        override
        returns (bool) {
            require(amount > 0, "Too small amount!");
            // TODO add requires for tokens
            if(token == ethToken){
                require(msg.value == amount);
                ETHBankAccount[msg.sender].interest = DSMath.add(ETHBankAccount[msg.sender].interest, calculateDepositInterest(token));
                ETHBankAccount[msg.sender].deposit = DSMath.add(ETHBankAccount[msg.sender].deposit, amount);
                ETHBankAccount[msg.sender].lastInterestBlock = block.number;
            } else if(token == hakToken) {
                require(ERC20(hakToken).transferFrom(msg.sender, address(this), amount), "Bank not allowed to transfer funds");
                HAKBankAccount[msg.sender].interest = DSMath.add(HAKBankAccount[msg.sender].interest, calculateDepositInterest(token));
                HAKBankAccount[msg.sender].deposit = DSMath.add(HAKBankAccount[msg.sender].deposit, amount);
                HAKBankAccount[msg.sender].lastInterestBlock = block.number;
            } else {
                require(false, "Token not recognized");
            }
            emit Deposit(msg.sender, token, amount);
            return true;
        }
    
    function withdraw(address token, uint256 amount)
        external
        override
        returns (uint256) {
            require(amount >= 0, "Too small amount!");
            if(token == ethToken){
                require(address(this).balance >= amount, "Bank doesn't have enough funds");
                ETHBankAccount[msg.sender].interest = DSMath.add(ETHBankAccount[msg.sender].interest, calculateDepositInterest(token));
                require(DSMath.add(ETHBankAccount[msg.sender].deposit, ETHBankAccount[msg.sender].interest) >= amount, "Not enough funds in account");
                if(ETHBankAccount[msg.sender].interest >= amount){
                    ETHBankAccount[msg.sender].interest = DSMath.sub(ETHBankAccount[msg.sender].interest, amount);
                } else {
                    uint256 tempAmount = amount;
                    tempAmount = DSMath.sub(tempAmount, ETHBankAccount[msg.sender].interest);
                    ETHBankAccount[msg.sender].interest = 0;
                    ETHBankAccount[msg.sender].deposit = DSMath.sub(ETHBankAccount[msg.sender].deposit, tempAmount);
                }
                (bool sent, bytes memory data) = msg.sender.call{value: amount}("");
                require(sent, "Failed to send Ether");
                ETHBankAccount[msg.sender].lastInterestBlock = block.number;
                
            } else if (token == hakToken) {
                require(ERC20(hakToken).balanceOf(address(this)) >= amount, "Bank doesn't have enough funds");
                HAKBankAccount[msg.sender].interest = DSMath.add(HAKBankAccount[msg.sender].interest, calculateDepositInterest(token));
                require(DSMath.add(HAKBankAccount[msg.sender].deposit, HAKBankAccount[msg.sender].interest) >= amount, "Not enough funds in account");
                if(HAKBankAccount[msg.sender].interest >= amount){
                    HAKBankAccount[msg.sender].interest = DSMath.sub(HAKBankAccount[msg.sender].interest, amount);
                } else {
                    uint256 tempAmount = amount;
                    tempAmount = DSMath.sub(tempAmount, HAKBankAccount[msg.sender].interest);
                    HAKBankAccount[msg.sender].interest = 0;
                    HAKBankAccount[msg.sender].deposit = DSMath.sub(HAKBankAccount[msg.sender].deposit, tempAmount);
                }
                ERC20(hakToken).transfer(msg.sender, amount);
                HAKBankAccount[msg.sender].lastInterestBlock = block.number;
            } else {
                require(false, "Token not recognized");
            }
            emit Withdraw(msg.sender, token, amount);
        }

    function borrow(address token, uint256 amount)
        external
        override
        returns (uint256) {
            require(token == ethToken, "You can only borrow ETH");
            if(amount==0){
                // calculate maximum amount
                uint256 max_amount = (HAKBankAccount[msg.sender].deposit + HAKBankAccount[msg.sender].interest)*10000 / 15000 - borrowed[msg.sender] - owedInterest[msg.sender];
                //uint256 max_amount = DSMath.sub(DSMath.sub(DSMath.wdiv(DSMath.mul(DSMath.add(HAKBankAccount[msg.sender].deposit, HAKBankAccount[msg.sender].interest) , 10000), 15000), borrowed[msg.sender]), owedInterest[msg.sender]);
                
                // update borrowed amount
                borrowed[msg.sender] = DSMath.add(borrowed[msg.sender], max_amount);
            } else {
                // calculate new collateral ratio
                uint256 tentative_coll_ratio = (HAKBankAccount[msg.sender].deposit + HAKBankAccount[msg.sender].interest)*10000 / (borrowed[msg.sender] + owedInterest[msg.sender] + amount);
                require(tentative_coll_ratio >= 15000, "you don't have enough deposit");
                
                // update borrowed amount
                borrowed[msg.sender] = DSMath.add(borrowed[msg.sender], amount);
            }
            
            uint256 new_coll_ratio = getCollateralRatio(token, msg.sender);
            emit Borrow(msg.sender, token, amount, new_coll_ratio);
                        
            return new_coll_ratio;
        }

    function repay(address token, uint256 amount)
        payable
        external
        override
        returns (uint256) {}

    function liquidate(address token, address account)
        payable
        external
        override
        returns (bool) {}

    function getCollateralRatio(address token, address account)
        view
        public
        override
        returns (uint256) {}

    function getBalance(address token)
        view
        public
        override
        returns (uint256) {
            if(token == ethToken){
                return DSMath.add(ETHBankAccount[msg.sender].deposit, ETHBankAccount[msg.sender].interest);
            } else if(token == hakToken) {
                return DSMath.add(HAKBankAccount[msg.sender].deposit, HAKBankAccount[msg.sender].interest);
            } else {
                require(false, "Token not recognized");
            }
        }
        
    function calculateDepositInterest(address token) view private returns (uint256) {
        if(token == ethToken){
            return calculateInterest(3, ETHBankAccount[msg.sender].lastInterestBlock, ETHBankAccount[msg.sender].deposit);
        } else if (token == hakToken) {
            return calculateInterest(3, HAKBankAccount[msg.sender].lastInterestBlock, HAKBankAccount[msg.sender].deposit);
        }
    }
    
    function calculateInterest(uint256 interestRate, uint256 lastInterestBlock, uint256 amount) view private returns (uint256) {
        return DSMath.wdiv(DSMath.wmul(DSMath.mul(interestRate, DSMath.sub(block.number, lastInterestBlock)), amount), 10000);
    }
}
