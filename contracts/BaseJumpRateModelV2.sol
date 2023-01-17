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
     * @notice 利率模型假设的每年的大致区块数 15s = block
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
     * @param baseRatePerYear 近似目标基础 APR，尾数（按 1e18 缩放）// 年基准利率
     * @param multiplierPerYear 利率利用率的增长率（按 1e18 缩放）// 年利率乘数
     * @param jumpMultiplierPerYear 达到指定使用点后的 multiplierPerBlock  // 拐点年利率乘数
     * @param kink_ 应用跳转乘数的利用点 利率模型的拐点 // 拐点资金借出率
     * @param owner_ owner的地址，即Timelock合约（具有直接更新参数的能力）
     */
    constructor(
        uint baseRatePerYear,   //年基准利率
        uint multiplierPerYear, //年利率乘数
        uint jumpMultiplierPerYear, //拐点年利率乘数
        uint kink_,//拐点资金借出率
        address owner_
    ) internal {
        owner = owner_;

        // 更新利率模型
        updateJumpRateModelInternal(
            baseRatePerYear,
            multiplierPerYear,
            jumpMultiplierPerYear,
            kink_
        );
    }

    /**
     * @notice 更新利率模型的参数（只有所有者可以调用，即Timelock）
     * @param baseRatePerYear 近似目标基础 APR，尾数（按 1e18 缩放） // 年基准利率
     * @param multiplierPerYear 利率利用率的增长率（按 1e18 缩放）// 年利率乘数
     * @param jumpMultiplierPerYear 达到指定使用点后的 multiplierPerBlock // 拐点年利率乘数
     * @param kink_ 应用跳转乘数的利用点  // 拐点资金借出率
     */
    function updateJumpRateModel(
        uint baseRatePerYear,
        uint multiplierPerYear,
        uint jumpMultiplierPerYear,
        uint kink_  //  拐点
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
    // 市场使用率
    function utilizationRate(
        uint cash,  //代币余额
        uint borrows,   //用户借出代币总数
        uint reserves   // 储备代币总量
    ) public view returns (uint) {
        // Utilization rate is 0 when there are no borrows
        if (borrows == 0) {
            return 0;
        }
        console.log("市场使用率",borrows.mul(1e18).div(cash.add(borrows).sub(reserves)));
        // 资金借出率 = borrows * 1e18 / (cash + borrows - reserves)
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
        uint cash, // 代币余额
        uint borrows, // 用户借出代币总数
        uint reserves // 储备代币总数
    ) internal view returns (
        uint    // 块借出利率
    ) {
        // 获取市场使用率
        uint util = utilizationRate(cash, borrows, reserves);
        // 判断市场使用率 是否到达指定拐点
        if (util <= kink) {
            console.log("util.mul(multiplierPerBlock).div(1e18).add(baseRatePerBlock)", util.mul(multiplierPerBlock).div(1e18).add(baseRatePerBlock));
             // util * multiplierPerBlock + baseRatePerBlock
            //  块借出利率 = 资金借出率 * 块利率乘数 + 块基准利率
            return util.mul(multiplierPerBlock).div(1e18).add(baseRatePerBlock);
        } else {
            // 块借出利率 = (资金借出率 - 拐点资金借出率) * 拐点块利率乘数 + 拐点资金借出率 * 块利率乘数 + 块基准利率

            // 拐点前块借出利率 = kink * multiplierPerBlock + baseRatePerBlock
            uint normalRate = kink.mul(multiplierPerBlock).div(1e18).add(baseRatePerBlock);
            // 超出拐点资金借出率 = util - kink
            uint excessUtil = util.sub(kink);
            // 根据超过拐点计算
            // 块借出利率 = (util - kink) * jumpMultiplierPerBlock + kink * multiplierPerBlock + baseRatePerBlock
            return excessUtil.mul(jumpMultiplierPerBlock).div(1e18).add(normalRate);
        }
    }

    /**
     * @notice 计算每个区块的当前供应率
     * @param cash 市场上的现金数量
     * @param borrows 市场上的借款数量
     * @param reserves 市场上的准备金数量
     * @param reserveFactorMantissa 市场的当前储备因子 储备金率
     */
    //  * @return 每个块的供应率百分比作为尾数（按 1e18 缩放）
    // 获取存款利率
    // 存款利率 =（借款总额 * 借款利率）/ 存款总额
    function getSupplyRate(
        uint cash, // 代币余额
        uint borrows, // 用户借出代币总数
        uint reserves, // 储备代币总数
        uint reserveFactorMantissa // 储备金率
    ) public view returns (uint) {
        //  1e18 - 储备金率
        uint oneMinusReserveFactor = uint(1e18).sub(reserveFactorMantissa);
        // 获取借款利率
        uint borrowRate = getBorrowRateInternal(cash, borrows, reserves);
        // 存款利率*资金自用率
        // rateToPool = borrowRate * (1 - reserveFactorMantissa)
        uint rateToPool = borrowRate.mul(oneMinusReserveFactor).div(1e18);
        // 块质押利率(存款) = 资金使用率 * 借款利率 *（1 - 储备金率）
        // 块质押利率 = utilizationRate * borrowRate * (1 - reserveFactorMantissa)
        return utilizationRate(cash, borrows, reserves).mul(rateToPool).div(1e18);
    }

    /**
     * @notice 内部函数更新利率模型的参数
     * @param baseRatePerYear 近似目标基础 APR，尾数（按 1e18 缩放）
     * @param multiplierPerYear 利率利用率的增长率（按 1e18 缩放）
     * @param jumpMultiplierPerYear 达到指定使用点后的 multiplierPerBlock
     * @param kink_ 应用跳转乘数的利用点
     */
    function updateJumpRateModelInternal(
        uint baseRatePerYear,   //  年基准利率
        uint multiplierPerYear, //  年利率乘数
        uint jumpMultiplierPerYear, //  拐点率
        uint kink_  //  拐点资金借出率(compound 0.8)
    ) internal {
        // 获取每个区块的 年化利率
        // 块基准利率 = 年基准利率 / 年块数
        baseRatePerBlock = baseRatePerYear.div(blocksPerYear);
        // 利用率的增长比例 * 1e18 / 每个区块 * kink_
        // 块利率乘数 = 年基准利率 / (年块数 * 拐点资金借出率)
        multiplierPerBlock = (multiplierPerYear.mul(1e18)).div(blocksPerYear.mul(kink_));
        // 年华 / 区块
        // 每个区块的 拐点利率乘数 = 拐点年利率乘数 / 年块数
        jumpMultiplierPerBlock = jumpMultiplierPerYear.div(blocksPerYear);
        // 拐点
        kink = kink_;
        emit NewInterestParams(
            baseRatePerBlock,
            multiplierPerBlock,
            jumpMultiplierPerBlock,
            kink
        );
    }
}
