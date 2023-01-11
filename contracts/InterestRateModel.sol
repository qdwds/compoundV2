pragma solidity ^0.5.16;

/**
 * @title Compound's InterestRateModel Interface
 * @author Compound
 */
contract InterestRateModel {
    //  外部判断，确认是利率模型合约
    bool public constant isInterestRateModel = true;

    /**
     * @notice 计算当前每个区块的借款利率
     * @param cash 市场拥有的现金总量
     * @param borrows 市场未偿还的借款总额
     * @param 储备 市场拥有的储备总量
     */
    //  * @return 每个区块的借款利率（百分比，按 1e18 缩放）
    function getBorrowRate(
        uint cash,
        uint borrows,
        uint reserves
    ) external view returns (uint);

    /**
     * @notice 计算每个区块的当前供应利率
     * @param cash 市场拥有的现金总量
     * @param borrows 市场未偿还的借款总额
     * @param 储备 市场拥有的储备总量
     * @param reserveFactorMantissa 市场当前的储备因子  储备金率
     */
    //  * @return 每个区块的供应率（百分比，按 1e18 缩放）
    function getSupplyRate(
        uint cash,
        uint borrows,
        uint reserves,
        uint reserveFactorMantissa 
    ) external view returns (uint);
}
