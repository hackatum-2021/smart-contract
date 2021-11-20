//SPDX-License-Identifier: Unlicense
pragma solidity 0.7.0;

import "./interfaces/IBank.sol";
import "./interfaces/IPriceOracle.sol";
import "./libraries/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Bank is IBank {
    address internal constant ethToken = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    
    address private hakToken;
    address private priceOracle;

    mapping(address => Account) public ETHBankAccount;
    mapping(address => Account) public HAKBankAccount;

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
                //require(IERC20(ethToken).transferFrom(msg.sender, address(this), amount), "Bank not allowed to transfer funds");
                ETHBankAccount[msg.sender].deposit = DSMath.add(ETHBankAccount[msg.sender].deposit, amount);
            } else if(token == hakToken) {
                require(IERC20(hakToken).transferFrom(msg.sender, address(this), amount), "Bank not allowed to transfer funds");
                HAKBankAccount[msg.sender].deposit = DSMath.add(HAKBankAccount[msg.sender].deposit, amount);
            }
            emit Deposit(msg.sender, token, amount);
            return true;
        }
    
    function withdraw(address token, uint256 amount)
        external
        override
        returns (uint256) {}

    function borrow(address token, uint256 amount)
        external
        override
        returns (uint256) {}

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
        returns (uint256) {}
}
