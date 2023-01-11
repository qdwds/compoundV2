import { parseEther } from "ethers/lib/utils";
import { ethers } from "hardhat"
import { contractAbi } from "../utils/contractInfo";

const erc20TokenName = "ERC20Token"
const CErc20DelegateName = "CErc20Delegate";
const CErc20DelegatorName = "CErc20Delegator";

// 用于测试的token
export const erc20TokenDeploy = async () => {
    const ERC20Token = await ethers.getContractFactory(erc20TokenName);
    const erc20Token = await ERC20Token.deploy();
    await erc20Token.deployed();
    await contractAbi(erc20Token.address, erc20TokenName);
    return erc20Token;
}

// 用于支持代理CToken使用，不支持代理的CToken不需要此合约
// 所有 ERC20 基础资产的 CToken 采用委托代理模式
export const CErc20DelegateDeploy = async () => {
    const CErc20Delegate = await ethers.getContractFactory(CErc20DelegateName);
    const cErc20Delegate = await CErc20Delegate.deploy();
    await cErc20Delegate.deployed();
    await contractAbi(cErc20Delegate.address, CErc20DelegateName);
    return cErc20Delegate;
}

export const cErc20DelegatorDeploy =async (
    erc20Address:string,
    comptrollerAddress:string,
    jumpRateModelV2Address:string,
    owner:string,
    cErc20DelegateAddress:string
) => {
    const CErc20Delegator = await ethers.getContractFactory(CErc20DelegatorName);
    const cErc20Delegator = await CErc20Delegator.deploy(
        erc20Address,  //  erc20 token address
        comptrollerAddress, //  comptroller address
        jumpRateModelV2Address, //  jumpRateModelV2 address
        parseEther("0.1"),  // 1个token 可以还  1 / 0.1(10)个cToken
        "COPM USD", //  name
        "cUSD",     //  symbol
        "18",       //  decimals
        owner,      // msg.sender
        cErc20DelegateAddress,  //  cErc20Delegate address  
        "0x"    //  额外初始数据，此处填入0x，即无数据
    );
    // initialExchangeRateMantissa_ = 1 * 10 ^ (18 + underlyingDecimals - cTokenDecimals)
    await cErc20Delegator.deployed();
    await contractAbi(cErc20Delegator.address, CErc20DelegateName);
    return cErc20Delegator;
}


// 设置保证金系数   0.1 * 10 ^ 18
export const cToken__setReserveFactor = async(CErc20DelegatorAddress:string)=>{
    const cToken = await ethers.getContractAt("CErc20Delegator",CErc20DelegatorAddress);
    await cToken._setReserveFactor(parseEther("0.1"));
    console.log("cToken__setReserveFactor call success !!");
}


// 加入市场
// export const cToken__supportMarket = async (comptrollerAddress:string, tokenAddress:string) => {
//     const cToken = await ethers.getContractAt("Comptroller",comptrollerAddress);
//     await cToken._supportMarket(tokenAddress);  //  把该token加入到市场中
// }

/**
 * 代币加入到市场中
 * @param comptrollerAddress 
 * @param cErc20DelegatorAddress 
 */
export const cErc20Delegator_supportMarket = async (comptrollerAddress:string, cErc20DelegatorAddress:string) => {
    const cToken = await ethers.getContractAt("Comptroller",comptrollerAddress);
    await cToken._supportMarket(cErc20DelegatorAddress);  //  把该token加入到市场中
    console.log("cErc20Delegator_supportMarket call success !!")
}

