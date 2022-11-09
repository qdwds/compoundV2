pragma solidity ^0.5.16;

import "./SafeMath.sol";
import "hardhat/console.sol";

/**
 * @title Logic for Compound's JumpRateModel Contract V2.
 * @author Compound (modified by Dharma Labs, refactored by Arr00)
 * @notice Version 2 modifies Version 1 by enabling updateable parameters.
 */
// 拐点型利率模型
contract BaseJumpRateModelV2 {
    using SafeMath for uint;

    event NewInterestParams(
        uint baseRatePerBlock,
        uint multiplierPerBlock,
        uint jumpMultiplierPerBlock,
        uint kink
    );

    /**
     * @notice 拥有者地址，即Timelock合约，可直接更新参数
     */
    address public owner;

    /**
     * @notice 利率模型假设的每年的大致区块数
     */
    uint public constant blocksPerYear = 2102400;

    /**
     * @notice 给出利率斜率的利用率乘数
     */
    uint public multiplierPerBlock;

    /**
     * @notice 使用率为 0 时的 y 截距的基准利率
     */
    uint public baseRatePerBlock;

    /**
     * @notice 达到指定使用点后的 multiplierPerBlock
     */
    // 斜率
    uint public jumpMultiplierPerBlock;

    /**
     * @notice 应用跳转乘数的利用点
     */
    uint public kink;

    /**
     * @notice 构建利率模型
     * @param baseRatePerYear 近似目标基础 APR，尾数（按 1e18 缩放）
     * @param multiplierPerYear 利率利用率的增长率（按 1e18 缩放）
     * @param jumpMultiplierPerYear 达到指定使用点后的 multiplierPerBlock
     * @param kink_ 应用跳转乘数的利用点
     * @param owner_ owner的地址，即Timelock合约（具有直接更新参数的能力）
     */
    constructor(
        uint baseRatePerYear,
        uint multiplierPerYear,
        uint jumpMultiplierPerYear,
        uint kink_,
        address owner_
    ) internal {
        owner = owner_;

        // 更新利率模型参数
        updateJumpRateModelInternal(
            baseRatePerYear,
            multiplierPerYear,
            jumpMultiplierPerYear,
            kink_
        );
    }

    /**
     * @notice 更新利率模型的参数（只有所有者可以调用，即Timelock）
     * @param baseRatePerYear 近似目标基础 APR，尾数（按 1e18 缩放）
     * @param multiplierPerYear 利率利用率的增长率（按 1e18 缩放）
     * @param jumpMultiplierPerYear 达到指定使用点后的 multiplierPerBlock
     * @param kink_ 应用跳转乘数的利用点
     */
    function updateJumpRateModel(
        uint baseRatePerYear,
        uint multiplierPerYear,
        uint jumpMultiplierPerYear,
        uint kink_
    ) external {
        require(msg.sender == owner, "only the owner may call this function.");

        updateJumpRateModelInternal(
            baseRatePerYear,
            multiplierPerYear,
            jumpMultiplierPerYear,
            kink_
        );
    }

    /**
     *  @notice 计算市场使用率：`borrows /(cash + borrows -reserves)`
     *  @param cash 市场上的现金数量
     *  @param borrows 市场上的借款数量
     *  @param reserves 市场上的储备量（目前未使用）
     */
    //  *  @return 使用率作为尾数在 [0, 1e18] 之间
    function utilizationRate(
        uint cash,
        uint borrows,
        uint reserves
    ) public view returns (uint) {
        // Utilization rate is 0 when there are no borrows
        if (borrows == 0) {
            return 0;
        }
        console.log("borrows.mul(1e18).div(cash.add(borrows).sub(reserves)", borrows.mul(1e18).div(cash.add(borrows).sub(reserves)));
        return borrows.mul(1e18).div(cash.add(borrows).sub(reserves));
    }

    /**
     * @notice 计算当前每个区块的借贷利率，错误码是市场预期的
     * @param cash 市场上的现金数量
     * @param borrows 市场上的借款数量
     * @param reserves 市场上的准备金数量
     */
    //  * @return 以尾数表示的每个区块的借款利率百分比（按 1e18 缩放）
    // 获取借款利率
    function getBorrowRateInternal(
        uint cash,
        uint borrows,
        uint reserves
    ) internal view returns (uint) {
        uint util = utilizationRate(cash, borrows, reserves);
        // 判断是否到拐点位置
        if (util <= kink) {
            console.log("util.mul(multiplierPerBlock).div(1e18).add(baseRatePerBlock)", util.mul(multiplierPerBlock).div(1e18).add(baseRatePerBlock));
            return util.mul(multiplierPerBlock).div(1e18).add(baseRatePerBlock);
        } else {
            uint normalRate = kink.mul(multiplierPerBlock).div(1e18).add(
                baseRatePerBlock
            );
            // 超过多少
            uint excessUtil = util.sub(kink);
            // 根据超过拐点计算
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
     * @param reserves 市场上的准备金数量
     * @param reserveFactorMantissa 市场的当前储备因子
     */
    //  * @return 每个块的供应率百分比作为尾数（按 1e18 缩放）
    // 存款利率
    // 存款利率 =（借款总额 * 借款利率）/ 存款总额
    function getSupplyRate(
        uint cash,
        uint borrows,
        uint reserves,
        uint reserveFactorMantissa
    ) public view returns (uint) {
        // 资金自用率
        uint oneMinusReserveFactor = uint(1e18).sub(reserveFactorMantissa);
        // 获取借款利率
        uint borrowRate = getBorrowRateInternal(cash, borrows, reserves);
        // 存款利率*资金自用率
        uint rateToPool = borrowRate.mul(oneMinusReserveFactor).div(1e18);
        console.log("utilizationRate(cash, borrows, reserves).mul(rateToPool).div(1e18);", utilizationRate(cash, borrows, reserves).mul(rateToPool).div(1e18));
        return
            utilizationRate(cash, borrows, reserves).mul(rateToPool).div(1e18);
    }

    /**
     * @notice 内部函数更新利率模型的参数
     * @param baseRatePerYear 近似目标基础 APR，尾数（按 1e18 缩放）
     * @param multiplierPerYear 利率利用率的增长率（按 1e18 缩放）
     * @param jumpMultiplierPerYear 达到指定使用点后的 multiplierPerBlock
     * @param kink_ 应用跳转乘数的利用点
     */
    function updateJumpRateModelInternal(
        uint baseRatePerYear,
        uint multiplierPerYear,
        uint jumpMultiplierPerYear,
        uint kink_
    ) internal {
        // 获取每个区块的 年化利率
        baseRatePerBlock = baseRatePerYear.div(blocksPerYear);
        console.log("baseRatePerBlock", baseRatePerBlock);
        // 利用率的增长比例 * 1e18 / 每个区块 * kink_
        multiplierPerBlock = (multiplierPerYear.mul(1e18)).div(
            blocksPerYear.mul(kink_)
        );
        console.log("multiplierPerBlock", multiplierPerBlock);
        // 年华 / 区块
        jumpMultiplierPerBlock = jumpMultiplierPerYear.div(blocksPerYear);
        kink = kink_;
        console.log("jumpMultiplierPerBlock", jumpMultiplierPerBlock);
        console.log("kink", kink);
        emit NewInterestParams(
            baseRatePerBlock,
            multiplierPerBlock,
            jumpMultiplierPerBlock,
            kink
        );
    }
}
