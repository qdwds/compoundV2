import { parseEther } from "ethers/lib/utils";

/**
 * @name 流动性激励 || 清算激励
 * 设置流动性激励为 8%，参数值就是1.08 * 1 ^ 18;
 */
export const liquidationIncentive = parseEther("1.08");

/**
 * @name 清算比例
 */
export const settlementRate = parseEther("0.5");


// uint baseRatePerYear,         实际设置为 0
// uint multiplierPerYear,          实际设置 7%，即 0.07 * 10 ^ 18
// uint jumpMultiplierPerYear,  实际设置 3，即 3 * 10 ^ 18
// uint kink_,                             实际设置 75%，即 0.75 * 10 ^ 18
// address owner_,                   实际设置 msg.sender
export const baseRatePerYear = 0;
export const multiplierPerYear = parseEther("0.07");
export const jumpMultiplierPerYear = parseEther("3");
export const kink = parseEther("0.75");



// address underlying_,                                     erc20标的资产地址，见5.1节
// ComptrollerInterface comptroller_,                unitroller合约地址，见1.1节
// InterestRateModel interestRateModel_,        JumpRateModelV2合约地址，见4.1节
// uint initialExchangeRateMantissa_,               初始汇率，按 1：1 设置，本文 1 * 10 ^ 28
// string memory name_,                                   cToken 的 name
// string memory symbol_,                                 cToken 的 symbol
// uint8 decimals_,                                             cToken 的 decimals ，设为 8
// address payable admin_,                               应该是时间锁定合约地址，此处设为 msg.sender
// address implementation_,                              CErc20Delegate 合约地址，见5.2节
// bytes memory becomeImplementationData,  额外初始数据，此处填入0x，即无数据
// export const underlying;
// export const comptroller;
// export const interestRateModel;
// export const initialExchangeRateMantissa;
// export const name;
// export const symbol;
// export const decimals;
// export const admin;
// export const implementation;
// export const becomeImplementationData;