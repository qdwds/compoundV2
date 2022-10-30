pragma solidity ^0.5.16;

import "./InterestRateModel.sol";
import "./SafeMath.sol";

/**
  * @title Compound's JumpRateModel Contract
  * @author Compound
  */
contract JumpRateModel is InterestRateModel {
    using SafeMath for uint;

    event NewInterestParams(uint baseRatePerBlock, uint multiplierPerBlock, uint jumpMultiplierPerBlock, uint kink);

    /**
     * @notice 按每个区块15秒计算，获取一年的区块   60 * 60 * 24 * 365 / 15 = 2102400
     */
    uint public constant blocksPerYear = 2102400;

    /**
     * @notice 利率斜率的利用率乘数
     */
    uint public multiplierPerBlock;

    /**
     * @notice 使用率为 0 时的 y 截距的基准利率
     */
    uint public baseRatePerBlock;

    /**
     * @notice 达到指定的利用率点后的 multiplierPerBlock(利率斜率)
     */
    uint public jumpMultiplierPerBlock;

    /**
     * @notice 应用跳转乘数的利用率点
     */
    uint public kink;

    /**
      * @notice 构建利率模型
      * @param baseRatePerYear 近似目标基础 APR，尾数（按 1e18 缩放）
      * @param multiplierPerYear 利率利用率的增长率（按 1e18 缩放）
      * @param jumpMultiplierPerYear 达到指定使用点后的 multiplierPerBlock
      * @param kink_ 应用跳转乘数的利用点
      */
    constructor(
        uint baseRatePerYear, 
        uint multiplierPerYear, 
        uint jumpMultiplierPerYear, 
        uint kink_
    ) public {
        baseRatePerBlock = baseRatePerYear.div(blocksPerYear);
        multiplierPerBlock = multiplierPerYear.div(blocksPerYear);
        jumpMultiplierPerBlock = jumpMultiplierPerYear.div(blocksPerYear);
        kink = kink_;

        emit NewInterestParams(baseRatePerBlock, multiplierPerBlock, jumpMultiplierPerBlock, kink);
    }

    /**
     * @notice Calculates the utilization rate of the market: `borrows / (cash + borrows - reserves)`
     * @param cash The amount of cash in the market
     * @param borrows The amount of borrows in the market
     * @param reserves The amount of reserves in the market (currently unused)
     * @return The utilization rate as a mantissa between [0, 1e18]
     */
    function utilizationRate(uint cash, uint borrows, uint reserves) public pure returns (uint) {
        // Utilization rate is 0 when there are no borrows
        if (borrows == 0) {
            return 0;
        }

        return borrows.mul(1e18).div(cash.add(borrows).sub(reserves));
    }

    /**
     * @notice Calculates the current borrow rate per block, with the error code expected by the market
     * @param cash The amount of cash in the market
     * @param borrows The amount of borrows in the market
     * @param reserves The amount of reserves in the market
     * @return The borrow rate percentage per block as a mantissa (scaled by 1e18)
     */
    function getBorrowRate(uint cash, uint borrows, uint reserves) public view returns (uint) {
        uint util = utilizationRate(cash, borrows, reserves);

        if (util <= kink) {
            return util.mul(multiplierPerBlock).div(1e18).add(baseRatePerBlock);
        } else {
            uint normalRate = kink.mul(multiplierPerBlock).div(1e18).add(baseRatePerBlock);
            uint excessUtil = util.sub(kink);
            return excessUtil.mul(jumpMultiplierPerBlock).div(1e18).add(normalRate);
        }
    }

    /**
     * @notice Calculates the current supply rate per block
     * @param cash The amount of cash in the market
     * @param borrows The amount of borrows in the market
     * @param reserves The amount of reserves in the market
     * @param reserveFactorMantissa The current reserve factor for the market
     * @return The supply rate percentage per block as a mantissa (scaled by 1e18)
     */
    function getSupplyRate(uint cash, uint borrows, uint reserves, uint reserveFactorMantissa) public view returns (uint) {
        uint oneMinusReserveFactor = uint(1e18).sub(reserveFactorMantissa);
        uint borrowRate = getBorrowRate(cash, borrows, reserves);
        uint rateToPool = borrowRate.mul(oneMinusReserveFactor).div(1e18);
        return utilizationRate(cash, borrows, reserves).mul(rateToPool).div(1e18);
    }
}
