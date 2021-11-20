//SPDX-License-Identifier: Unlicense
pragma solidity 0.7.0;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v3.1.0-solc-0.7/contracts/access/Ownable.sol";
import "../interfaces/IPriceOracle.sol";

contract PriceOracleTest is IPriceOracle, Ownable {
    mapping(address => uint256) virtualPrice;
    function getVirtualPrice(address token)
        view
        external
        override
        returns (uint256) {
        if (virtualPrice[token] == 0) {
            return 1 ether;
        } else {
            return virtualPrice[token];
        }
    }

    function setVirtualPrice(address token, uint256 newPrice) external onlyOwner returns(bool) {
        require(newPrice != virtualPrice[token], "new and old prices are the same");
        virtualPrice[token] = newPrice;
        return true;
    }
}