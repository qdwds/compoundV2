pragma solidity ^0.5.16;

import "./InterestRateModel.sol";
import "./SafeMath.sol";

/**
   * @title Compound 的 WhitePaperInterestRateModel 合约
   * @author 复合
   * @notice 原始复合协议白皮书第 2.4 节中描述的参数化模型
   */
//   直线形利率模型
//   y = k*x + b
contract WhitePaperInterestRateModel is InterestRateModel {
    using SafeMath for uint;

    event NewInterestParams(uint baseRatePerBlock, uint multiplierPerBlock);

    /**
     * @notice The approximate number of blocks per year that is assumed by the interest rate model
     */
    uint public constant blocksPerYear = 2102400;

    /**
     * @notice The multiplier of utilization rate that gives the slope of the interest rate
     */
    uint public multiplierPerBlock;

    /**
     * @notice The base interest rate which is the y-intercept when utilization rate is 0
     */
    uint public baseRatePerBlock;

    /**
      * @notice 构建利率模型
      * @param baseRatePerYear 近似目标基础 APR，尾数（按 1e18 缩放）
      * @param multiplierPerYear 利率利用率的增长率（按 1e18 缩放）
      */
    constructor(uint baseRatePerYear, uint multiplierPerYear) public {
        baseRatePerBlock = baseRatePerYear.div(blocksPerYear);
        multiplierPerBlock = multiplierPerYear.div(blocksPerYear);

        emit NewInterestParams(baseRatePerBlock, multiplierPerBlock);
    }

    /**
      * @notice 计算市场使用率：`borrows / (cash + borrows - reserves)`
      * @param cash 市场上的现金数量
      * @param borrows 市场上的借款数量
      * @param reserves 市场上的储备量（目前未使用）
      */
    //   * @return 使用率作为尾数在 [0, 1e18] 之间
    function utilizationRate(uint cash, uint borrows, uint reserves) public pure returns (uint) {
        // Utilization rate is 0 when there are no borrows
        if (borrows == 0) {
            return 0;
        }

        return borrows.mul(1e18).div(cash.add(borrows).sub(reserves));
    }

    /**
      * @notice 计算当前每个区块的借贷利率，错误码是市场预期的
      * @param cash 市场上的现金数量
      * @param borrows 市场上的借款数量
      * @param reserves 市场上的准备金数量
      */
    //   * @return 以尾数表示的每个区块的借款利率百分比（按 1e18 缩放）
    function getBorrowRate(uint cash, uint borrows, uint reserves) public view returns (uint) {
        uint ur = utilizationRate(cash, borrows, reserves);
        return ur.mul(multiplierPerBlock).div(1e18).add(baseRatePerBlock);
    }

    /**
      * @notice 计算每个区块的当前供应率
      * @param cash 市场上的现金数量
      * @param borrows 市场上的借款数量
      * @param reserves 市场上的准备金数量
      * @param reserveFactorMantissa 市场的当前储备因子
      */
    //   * @return 每个块的供应率百分比作为尾数（按 1e18 缩放）
    function getSupplyRate(uint cash, uint borrows, uint reserves, uint reserveFactorMantissa) public view returns (uint) {
        uint oneMinusReserveFactor = uint(1e18).sub(reserveFactorMantissa);
        uint borrowRate = getBorrowRate(cash, borrows, reserves);
        uint rateToPool = borrowRate.mul(oneMinusReserveFactor).div(1e18);
        return utilizationRate(cash, borrows, reserves).mul(rateToPool).div(1e18);
    }
}
