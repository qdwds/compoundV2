pragma solidity ^0.5.16;

import "./CErc20.sol";

/**
  * @title Compound 的 CErc20Immutable 合约
  * @notice CTokens 封装了 EIP-20 底层并且是不可变的
  * @author 复合
  */
contract CErc20Immutable is CErc20 {
    /**
      * @notice 构建一个新的货币市场
      * @param underlying_ 标的资产地址
      * @param comptroller_ 主计长地址
      * @param interestRateModel_ 利率模型的地址
      * @param initialExchangeRateMantissa_ 初始汇率，按 1e18 缩放
      * @param name_ 此令牌的 ERC-20 名称
      * @param symbol_ 此代币的 ERC-20 符号
      * @param decimals_ 此令牌的 ERC-20 十进制精度
      * @param admin_ 此令牌的管理员地址
      */
    constructor(
        address underlying_,
        ComptrollerInterface comptroller_,
        InterestRateModel interestRateModel_,
        uint initialExchangeRateMantissa_,
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        address payable admin_
    ) public {
        // Creator of the contract is admin during initialization
        admin = msg.sender;

        // Initialize the market
        initialize(underlying_, comptroller_, interestRateModel_, initialExchangeRateMantissa_, name_, symbol_, decimals_);

        // Set the proper admin now that initialization is done
        admin = admin_;
    }
}
