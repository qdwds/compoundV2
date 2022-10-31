pragma solidity ^0.5.16;

import "./CToken.sol";

//    价格预言机
contract PriceOracle {
    bool public constant isPriceOracle = true;  //  用于检测是否是一个预言机
     /**
      *@notice 获取cToken资产的基础价格
      *@param cToken获取的基础价格
      *零表示价格不可用。
      */
      // *@return 基础资产价格尾数（按1e18缩放）。
    function getUnderlyingPrice(CToken cToken) external view returns (uint);
}
