import { parseEther } from "ethers/lib/utils";
import { ethers } from "hardhat";
import { contractAbi } from "../utils/contractInfo";
import { liquidationIncentive, settlementRate } from "./config";

const unitrollerName = "Unitroller";
const comptrollerG7Name = "ComptrollerG7";



export const unitollerDeploy = async () => {
    const Unitroller = await ethers.getContractFactory(unitrollerName);
    const unitroller = await Unitroller.deploy();
    await unitroller.deployed();
    await contractAbi(unitroller.address, unitrollerName);
    return unitroller;
}

// 设置管理员   代理绑定 转移所有权
export const unitoller__setPendingImplementation =async (unitrollerAddress:string, comptrollerG7Address:string) => {
    const unitroller = await ethers.getContractAt("Unitroller", unitrollerAddress);
    await unitroller._setPendingImplementation(comptrollerG7Address);
    console.log("unitoller__setPendingImplementation call  success !!");
}


export const comptrollerG7Deploy = async () => {
    const ComptrollerG7 = await ethers.getContractFactory(comptrollerG7Name);
    const comptrollerG7 = await ComptrollerG7.deploy();
    await comptrollerG7.deployed();
    await contractAbi(comptrollerG7.address, comptrollerG7Name);
    return comptrollerG7;
}

//  给G7设置代理合约地址    新的 Comptroller 接受所有权
export const comptrollerG7__become = async(comptrollerG7Address:string, unitrollerAddress:string)=>{
    const g7 = await ethers.getContractAt(comptrollerG7Name, comptrollerG7Address);
    await g7._become(unitrollerAddress);
    console.log("comptrollerG7__become call  success !!");
}

// 应该是设置清算比例
export const comptrollerG7__setCloseFactor =async (comptrollerG7Address:string) => {
    const g7 = await ethers.getContractAt(comptrollerG7Name, comptrollerG7Address);
    await g7._setCloseFactor(settlementRate);   //  0.5
    console.log("comptrollerG7__setCloseFactor call  success !!");
}


// 设置流动性激励为 8%，参数值就是1.08 * 1 ^ 18;
export const ccomptrollerG7__setLiquidationIncentive = async(comptrollerG7Address:string) => {
    const g7 = await ethers.getContractAt(comptrollerG7Name, comptrollerG7Address);
    await g7._setLiquidationIncentive(liquidationIncentive);    //  1.08
    console.log("ccomptrollerG7__setLiquidationIncentive call  success !!");
}

// 设置预言机地址
export const comptrollerG7__setPriceOracle = async(comptrollerG7Address:string, simplePriceOracleAddress:string) => {
    const g7 = await ethers.getContractAt(comptrollerG7Name, comptrollerG7Address);
    console.log(simplePriceOracleAddress);
    await g7._setPriceOracle(simplePriceOracleAddress);
    console.log("comptrollerG7__setPriceOracle call  success !!");
}


// 设置抵押率
export const comptrollerG7__setCollateralFactor = async(comptrollerG7Address:string,cErc20DelegatorAddress:string) => {
    const g7 = await ethers.getContractAt(comptrollerG7Name,comptrollerG7Address);
    // //  CToken cToken,CErc20Delegator.sol 地址
    // 0.6 * 10 ^ 18
    await g7._setCollateralFactor(cErc20DelegatorAddress,parseEther("0.6"));    
    console.log("comptrollerG7__setCollateralFactor call success !!")
}

// COMP奖励
export const comptrollerG7_setCompSpeed = async (comptrollerG7Address:string,cTokenAddress:string) => {
    const g7 = await ethers.getContractAt(comptrollerG7Name,comptrollerG7Address);
    /**
     * 
     * 计算compspeed：需要翻倍计算 ？？？ 
        const cTokenAddress = '0xabc...';
        const comptroller = new web3.eth.Contract(comptrollerAbi, comptrollerAddress);
        let compSpeed = await comptroller.methods.compSpeeds(cTokenAddress).call();
        compSpeed = compSpeed / 1e18;
        // COMP issued to suppliers OR borrowers
        const compSpeedPerDay = compSpeed * 4 * 60 * 24;
        // COMP issued to suppliers AND borrowers
        const compSpeedPerDayTotal = compSpeedPerDay * 2;
     */
    await g7._setCompSpeed(cTokenAddress, "1");
}