pragma solidity ^0.5.16;

import "./PriceOracle.sol";
import "./CErc20.sol";
import "hardhat/console.sol";


contract SimplePriceOracle is PriceOracle {
    mapping(address => uint) prices;
    event PricePosted(address asset, uint previousPriceMantissa, uint requestedPriceMantissa, uint newPriceMantissa);

    // 获取代币价格
    // function getUnderlyingPrice(CToken cToken) public view returns (uint) {
    //     if (compareStrings(cToken.symbol(), "cETH")) {
    //         return 1e18;
    //     } else {
    //         return prices[address(CErc20(address(cToken)).underlying())];
    //     }
    // }
    function _getUnderlyingAddress(CToken cToken) private view returns (address) {
        address asset;
        if (compareStrings(cToken.symbol(), "cETH")) {
            asset = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
        } else {
            asset = address(CErc20(address(cToken)).underlying());
        }
        return asset;
    }
    // 获取对应cToken价格
    function getUnderlyingPrice(CToken cToken) public view returns (uint) {
        return prices[_getUnderlyingAddress(cToken)];
    }

    // 设置市场价格
    function setUnderlyingPrice(CToken cToken, uint underlyingPriceMantissa) public {
        // cToken = > cToken 地址
        // address(CErc20(address(cToken)).underlying()) cToken的原始资产地址
        address asset = _getUnderlyingAddress(cToken);
        emit PricePosted(asset, prices[asset], underlyingPriceMantissa, underlyingPriceMantissa);
        console.log(underlyingPriceMantissa);
        prices[asset] = underlyingPriceMantissa;
    }

    function setDirectPrice(address asset, uint price) public {
        emit PricePosted(asset, prices[asset], price, price);
        prices[asset] = price;
    }

    // v1 price oracle interface for use as backing of proxy
    function assetPrices(address asset) external view returns (uint) {
        return prices[asset];
    }

    function compareStrings(string memory a, string memory b) internal pure returns (bool) {
        return (keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b))));
    }
    
}
