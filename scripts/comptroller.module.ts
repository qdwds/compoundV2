import { parseEther } from "ethers/lib/utils";
import { ethers } from "hardhat";
import { contractAbi } from "../utils/contractInfo";
import { liquidationIncentive, settlementRate } from "./config";

const unitrollerName = "Unitroller";
const comptrollerName = "Comptroller";



export const unitollerDeploy = async () => {
    const Unitroller = await ethers.getContractFactory(unitrollerName);
    const unitroller = await Unitroller.deploy();
    await unitroller.deployed().catch(err => console.log(err));
    await contractAbi(unitroller.address, unitrollerName);
    return unitroller;
}

// 设置管理员   代理绑定 转移所有权
export const unitoller__setPendingImplementation =async (unitrollerAddress:string, comptrollerAddress:string) => {
    const unitroller = await ethers.getContractAt("Unitroller", unitrollerAddress);
    await unitroller._setPendingImplementation(comptrollerAddress);
    console.log("unitoller__setPendingImplementation call  success !!");
}


export const comptrollerDeploy = async () => {
    const Comptroller = await ethers.getContractFactory(comptrollerName);
    const comptroller = await Comptroller.deploy();
    await comptroller.deployed();
    await contractAbi(comptroller.address, comptrollerName);
    return comptroller;
}

//  给设置代理合约地址    新的 Comptroller 接受所有权
export const comptroller__become = async(comptrollerAddress:string, unitrollerAddress:string)=>{
    const comptroller = await ethers.getContractAt(comptrollerName, comptrollerAddress);
    await comptroller._become(unitrollerAddress);
    console.log("comptroller__become call  success !!");
}

// 应该是设置清算比例
export const comptroller__setCloseFactor =async (comptrollerAddress:string) => {
    const comptroller = await ethers.getContractAt(comptrollerName, comptrollerAddress);
    await comptroller._setCloseFactor(settlementRate);   //  0.5
    console.log("comptroller__setCloseFactor call  success !!");
}


// 设置流动性激励为 8%，参数值就是1.08 * 1 ^ 18;
export const ccomptroller__setLiquidationIncentive = async(comptrollerAddress:string) => {
    const comptroller = await ethers.getContractAt(comptrollerName, comptrollerAddress);
    await comptroller._setLiquidationIncentive(liquidationIncentive);    //  1.08
    console.log("ccomptroller__setLiquidationIncentive call  success !!");
}

// 设置预言机地址
export const comptroller__setPriceOracle = async(comptrollerAddress:string, simplePriceOracleAddress:string) => {
    const comptroller = await ethers.getContractAt(comptrollerName, comptrollerAddress);
    await comptroller._setPriceOracle(simplePriceOracleAddress);
    console.log("comptroller__setPriceOracle call  success !!");
}


// 设置抵押率
export const comptroller__setCollateralFactor = async(comptrollerAddress:string,cErc20DelegatorAddress:string) => {
    const comptroller = await ethers.getContractAt(comptrollerName,comptrollerAddress);
    // //  CToken cToken,CErc20Delegator.sol 地址
    // 0.6 * 10 ^ 18
    await comptroller._setCollateralFactor(cErc20DelegatorAddress,parseEther("0.6"));    
    console.log("comptroller__setCollateralFactor call success !!")
}

// COMP奖励
export const comptroller_setCompSpeed = async (comptrollerAddress:string,cTokenAddress:string) => {
    const comptroller = await ethers.getContractAt(comptrollerName,comptrollerAddress);
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
    await comptroller._setCompSpeed(cTokenAddress, "1");
}