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
                require(false, "token not supported");
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
                require(DSMath.add(ETHBankAccount[msg.sender].deposit, ETHBankAccount[msg.sender].interest) > 0, "no balance");
                require(DSMath.add(ETHBankAccount[msg.sender].deposit, ETHBankAccount[msg.sender].interest) >= amount, "amount exceeds balance");
                
                if(amount == 0) {
                    amount = ETHBankAccount[msg.sender].deposit + ETHBankAccount[msg.sender].interest;
                }
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
                require(DSMath.add(HAKBankAccount[msg.sender].deposit, HAKBankAccount[msg.sender].interest) > 0, "no balance");
                require(DSMath.add(HAKBankAccount[msg.sender].deposit, HAKBankAccount[msg.sender].interest) >= amount, "amount exceeds balance");
                
                if(amount == 0) {
                    amount = HAKBankAccount[msg.sender].deposit + HAKBankAccount[msg.sender].interest;
                }
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
                require(false, "token not supported");
            }
            emit Withdraw(msg.sender, token, amount);
        }

    function borrow(address token, uint256 amount)
        external
        override
        returns (uint256) {
            require(token == ethToken, "token not supported");
            require(calcBorrowedInterest(msg.sender), "Could not calculate interest on debt");
            require(HAKBankAccount[msg.sender].deposit + HAKBankAccount[msg.sender].deposit > 0, "no collateral deposited");
            if(amount==0){
                // calculate maximum amount
                uint256 totalHakTokens = DSMath.add(HAKBankAccount[msg.sender].deposit, HAKBankAccount[msg.sender].interest);
                uint256 max_amount = DSMath.wmul(IPriceOracle(priceOracle).getVirtualPrice(hakToken), DSMath.mul(totalHakTokens, 10000) / 15000);
                amount = DSMath.sub(DSMath.sub(max_amount, ETHBorrowed[msg.sender].deposit), ETHBorrowed[msg.sender].interest);
                //uint256 max_amount = DSMath.sub(DSMath.sub(DSMath.wdiv(DSMath.mul(DSMath.add(HAKBankAccount[msg.sender].deposit, HAKBankAccount[msg.sender].interest) , 10000), 15000), borrowed[msg.sender]), owedInterest[msg.sender]);
                
                // update borrowed amount
                ETHBorrowed[msg.sender].deposit = DSMath.add(ETHBorrowed[msg.sender].deposit, amount);
            } else {
                // calculate new collateral ratio
                uint256 totalHakTokens = DSMath.add(HAKBankAccount[msg.sender].deposit, HAKBankAccount[msg.sender].interest);
                uint256 totalBorrowed = DSMath.add(ETHBorrowed[msg.sender].deposit, DSMath.add(ETHBorrowed[msg.sender].interest, amount));
                uint256 tentative_coll_ratio = DSMath.wdiv(DSMath.wmul(IPriceOracle(priceOracle).getVirtualPrice(hakToken), DSMath.mul(totalHakTokens, 10000)), totalBorrowed);
                require(tentative_coll_ratio >= 15000, "borrow would exceed collateral ratio");
                
                // update borrowed amount
                ETHBorrowed[msg.sender].deposit = DSMath.add(ETHBorrowed[msg.sender].deposit, amount);
            }
            require(address(this).balance >= amount, "Bank doesn't have enough funds");
            
            (bool sent, bytes memory data) = msg.sender.call{value: amount}("");
            require(sent, "Failed to send Ether");
            
            uint256 new_coll_ratio = getCollateralRatio(hakToken, msg.sender);
            emit Borrow(msg.sender, token, amount, new_coll_ratio);
                        
            return new_coll_ratio;
        }

    function repay(address token, uint256 amount)
        payable
        external
        override
        returns (uint256) {
            require(ETHBorrowed[msg.sender].deposit + ETHBorrowed[msg.sender].interest > 0, "nothing to repay");
            require(calcBorrowedInterest(msg.sender), "Could not calculate interest on debt");
            //TODO: maybe this is not required, case in which we need to send overpayments back
            require(ETHBorrowed[msg.sender].deposit + ETHBorrowed[msg.sender].interest >= msg.value);
            require(amount <= msg.value, "msg.value < amount to repay");
            
            repayHelper(token, msg.sender, msg.sender, amount);
        }

    function liquidate(address token, address account)
        payable
        external
        override
        returns (bool) {
            require(calcBorrowedInterest(msg.sender), "Could not calculate interest on debt");
            require(getCollateralRatio(hakToken, account) < 15000, "healty position");
            uint256 amountToPay = DSMath.add(ETHBorrowed[account].deposit, ETHBorrowed[account].interest);
            require(msg.value >= amountToPay, "insufficient ETH sent by liquidator");
            require(account != msg.sender, "cannot liquidate own position");
            // repay the loan
            repayHelper(token, account, msg.sender, amountToPay);
            
            if(amountToPay < msg.value) {
                (bool sent, bytes memory data) = msg.sender.call{value: msg.value - amountToPay}("");
                require(sent, "Failed to send Ether");
            }
            
            emit Liquidate(msg.sender, account, hakToken, HAKBankAccount[account].deposit, msg.value - amountToPay);
        }
        
    function repayHelper(address token, address borrower, address repayer, uint256 amount)
        private
        returns (bool) {
            require(token == ethToken, "token not supported");
            //require(ERC20(ethToken).approve(address(this), amount), "Bank not allowed to transfer funds");
            //require(ERC20(ethToken).transferFrom(repayer, address(this), amount), "Bank not allowed to transfer funds");
            
            if(amount <= ETHBorrowed[borrower].interest){
                ETHBorrowed[borrower].interest = DSMath.sub(ETHBorrowed[borrower].interest, amount);
            } else {
                uint256 remainingAmount = amount - ETHBorrowed[borrower].interest;
                ETHBorrowed[borrower].interest = 0;
                ETHBorrowed[borrower].deposit = DSMath.sub(ETHBorrowed[borrower].deposit, remainingAmount);
            }
            
            emit Repay(repayer, token, ETHBorrowed[borrower].deposit + ETHBorrowed[borrower].interest);
        }

    // TODO implement: wenn sich der Preis von HAK token ändert => jeden Block die Ratio checken und ggf. liquidieren
    function getCollateralRatio(address token, address account)
        view
        public
        override
        returns (uint256) {
            require(token == hakToken, "wrong input token");
            if (ETHBorrowed[account].deposit == 0) {
                return type(uint256).max;
            }
            uint256 deposited = DSMath.wmul(IPriceOracle(priceOracle).getVirtualPrice(hakToken), DSMath.add(HAKBankAccount[account].deposit, HAKBankAccount[account].interest));
            uint256 owedInterest = calculateInterest(5, ETHBorrowed[account].lastInterestBlock, ETHBorrowed[account].interest);
            uint256 borrowed = DSMath.add(ETHBorrowed[account].deposit, DSMath.add(ETHBorrowed[account].interest, owedInterest));
            return DSMath.wdiv(DSMath.mul(deposited, 10000), borrowed);
        }

    function calcBorrowedInterest(address account)
        private 
        returns (bool) {
            uint256 owedInterest = calculateInterest(5, ETHBorrowed[account].lastInterestBlock, ETHBorrowed[account].interest);
            ETHBorrowed[account].interest = DSMath.add(ETHBorrowed[account].interest, owedInterest);
            ETHBorrowed[account].lastInterestBlock = block.number;
            return true;
        }

    function getBalance(address token)
        view
        public
        override
        returns (uint256) {
            if(token == ethToken){
                return DSMath.add(ETHBankAccount[msg.sender].deposit, ETHBankAccount[msg.sender].interest + calculateDepositInterest(token));
            } else if(token == hakToken) {
                return DSMath.add(HAKBankAccount[msg.sender].deposit, HAKBankAccount[msg.sender].interest + calculateDepositInterest(token));
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
        uint256 nrOfBlocksElapsed = DSMath.sub(block.number, lastInterestBlock);
        
        return DSMath.mul(DSMath.mul(interestRate, nrOfBlocksElapsed), amount) / 10000;
    }
}
