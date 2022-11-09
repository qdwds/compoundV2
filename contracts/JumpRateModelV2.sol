pragma solidity ^0.5.16;

import "./BaseJumpRateModelV2.sol";
import "./InterestRateModel.sol";


/**
  * @title Compound's JumpRateModel Contract V2 for V2 cTokens
  * @author Arr00
  * @notice Supports only for V2 cTokens
  */
//  拐点型 利率模型
// y = k2*(x - p) + (k*p + b)
// y = k2 * (x - p) + (k * p + b)
/***
 * @title 利率模型 - 利率随着借款总额和存款总额的变动而变动
 * 借款总额为零（没有人进行借款），此时没有营收产生，存款利率为零
 * 借款总额增大，产生营收增多，存款利率也会提高
 * 借款总额不变（营收不变），存款总额增大，存款利率降低
 */
contract JumpRateModelV2 is InterestRateModel, BaseJumpRateModelV2  {

	  /**
      * @notice 计算当前每个区块的借贷利率
      * @param cash 市场上的现金数量
      * @param borrows 市场上的借款数量
      * @param reserves 市场上的准备金数量
      */
      // * @return 以尾数表示的每个区块的借款利率百分比（按 1e18 缩放）
    // 计算当前借款利率
    function getBorrowRate(uint cash, uint borrows, uint reserves) external view returns (uint) {
        return getBorrowRateInternal(cash, borrows, reserves);
    }

    constructor(
      uint baseRatePerYear,
      uint multiplierPerYear,
      uint jumpMultiplierPerYear,
      uint kink_,
      address owner_
    ) 
    	BaseJumpRateModelV2(baseRatePerYear,multiplierPerYear,jumpMultiplierPerYear,kink_,owner_) public {}
}
