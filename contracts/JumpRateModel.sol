pragma solidity ^0.5.16;

import "./InterestRateModel.sol";
import "./SafeMath.sol";
import "hardhat/console.sol";

/**
 * @title Compound's JumpRateModel Contract
 * @author Compound
 */
/***
 * @title 利率模型 - 利率随着借款总额和存款总额的变动而变动
 * 借款总额为零（没有人进行借款），此时没有营收产生，存款利率为零
 * 借款总额增大，产生营收增多，存款利率也会提高
 * 借款总额不变（营收不变），存款总额增大，存款利率降低
 */
contract JumpRateModel is InterestRateModel {
    using SafeMath for uint;

    event NewInterestParams(
        uint baseRatePerBlock,
        uint multiplierPerBlock,
        uint jumpMultiplierPerBlock,
        uint kink
    );

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

        emit NewInterestParams(
            baseRatePerBlock,
            multiplierPerBlock,
            jumpMultiplierPerBlock,
            kink
        );
    }

    /**
     * @notice 计算市场使用率：`borrows / (cash + borrows - reserves)`
     * @param cash 市场上的现金数量
     * @param borrows 市场上的借款数量
     * @param reserves 市场上的储备量（目前未使用）
     */
    //  * @return 使用率作为尾数在 [0, 1e18] 之间
    // 计算市场使用率
    function utilizationRate(
        uint cash,
        uint borrows,
        uint reserves
    ) public view returns (uint) {
        // Utilization rate is 0 when there are no borrows
        // 市场借款额度为0
        if (borrows == 0) {
            return 0;
        }

        // 最小利率0  最大利率1  ？？？
        // borrows * 1 / (cash + borrows - reserves;)
        console.log(cash.add(borrows));
        console.log(cash.add(borrows).sub(reserves));
        console.log(borrows.mul(1e18).div(cash.add(borrows).sub(reserves)));
        return borrows.mul(1e18).div(cash.add(borrows).sub(reserves));
    }

    /**
     * @notice 计算当前每个区块的借贷利率，错误码是市场预期的
     * @param cash 市场上的现金数量
     * @param borrows 市场上的借款数量
     * @param reserves 市场上的储备金数量
     */
    //  * @return 以尾数表示的每个区块的借款利率百分比（按 1e18 缩放）
    // 获取借款利率
    function getBorrowRate(
        uint cash,
        uint borrows,
        uint reserves
    ) public view returns (uint) {
        // 计算出使用率
        uint util = utilizationRate(cash, borrows, reserves);
        console.log("util", util);
        // 使用率小于_传入设定阀值_时候
        if (util <= kink) {
            // util * multiplierPerBlock / 1e18 + baseRatePerBlock基准利率
            console.log(
                util.mul(multiplierPerBlock).div(1e18).add(baseRatePerBlock)
            );
            return util.mul(multiplierPerBlock).div(1e18).add(baseRatePerBlock);
        } else {
            // kink * multiplierPerBlock - 1e18 + baseRatePerBlock
            uint normalRate = kink.mul(multiplierPerBlock).div(1e18).add(
                baseRatePerBlock
            );
            console.log("normalRate", normalRate);
            // util - kink;
            uint excessUtil = util.sub(kink);
            console.log(excessUtil);
            // excessUtil * jumpMultiplierPerBlock(阀值) / 1e18 + normalRate
            console.log(
                "excessUtil.mul(jumpMultiplierPerBlock).div(1e18).add(normalRate)",
                excessUtil.mul(jumpMultiplierPerBlock).div(1e18).add(normalRate)
            );
            return
                excessUtil.mul(jumpMultiplierPerBlock).div(1e18).add(
                    normalRate
                );
        }
    }

    /**
     * @notice 计算每个区块的当前供应率
     * @param cash 市场上的现金数量
     * @param borrows 市场上的借款数量
     * @param reserves 市场上的储备金数量
     * @param reserveFactorMantissa 市场的当前储备因子  储备金率
     */
    //  * @return 每个块的供应率百分比作为尾数（按 1e18 缩放）
    //  每个区块的供应率
    // 获取存款利率
    function getSupplyRate(
        uint cash,
        uint borrows,
        uint reserves,
        uint reserveFactorMantissa
    ) public view returns (uint) {
        // 1e18 - reserveFactorMantissa
        uint oneMinusReserveFactor = uint(1e18).sub(reserveFactorMantissa);
        console.log("oneMinusReserveFactor", oneMinusReserveFactor);
        // 借款利率
        uint borrowRate = getBorrowRate(cash, borrows, reserves);
        console.log("borrowRate", borrowRate);
        uint rateToPool = borrowRate.mul(oneMinusReserveFactor).div(1e18);
        console.log("rateToPool", rateToPool);

        console.log(
            "utilizationRate(cash, borrows, reserves).mul(rateToPool).div(1e18)",
            utilizationRate(cash, borrows, reserves).mul(rateToPool).div(1e18)
        );
        return
            utilizationRate(cash, borrows, reserves).mul(rateToPool).div(1e18);
    }
}
