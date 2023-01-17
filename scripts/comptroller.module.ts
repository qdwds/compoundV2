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
    await comptroller._setCloseFactor(parseEther("0.5"));   //  0.5
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
export const comptroller__setCollateralFactor = async(comptrollerAddress:string,cErc20DelegatorAddress:string,rate?:string) => {
    const comptroller = await ethers.getContractAt(comptrollerName,comptrollerAddress);
    // //  CToken cToken,CErc20Delegator.sol 地址
    // 0.6 * 10 ^ 18
    // 100 * 0.75 = 75usdt
    await comptroller._setCollateralFactor(cErc20DelegatorAddress,parseEther(rate ? rate :"0.75"));    
    console.log("comptroller__setCollateralFactor call success !!")
}

// 设置comp token 地址

export const comptroller_setCompAddress = async (comptrollerAddress:string, comp:string) => {
    const comptroller = await ethers.getContractAt(comptrollerName,comptrollerAddress);
    await comptroller.setCompAddress(comp);
}