import { parseEther } from "ethers/lib/utils";
import { ethers } from "hardhat";
import { contractAbi } from "../utils/contractInfo";

const CEtherName = "CEther";

export const cEtherDeploy = async (
    unitrollerAddress: string,
    etherJumpRateModelV2Address: string,
    owner: string
) => {
    const CEther = await ethers.getContractFactory(CEtherName);
    const cEther = await CEther.deploy(
        unitrollerAddress,
        etherJumpRateModelV2Address,
        parseEther("1"),
        "COMPOUND ETH",
        "cETH",
        "18",
        owner
    );
    await cEther.deployed();
    await contractAbi(cEther.address, CEtherName);
    return cEther
}


// 设置保证金系数   0.1 * 10 ^ 18
export const cEther__setReserveFactor = async(CEtherAddress:string)=>{
    const cEther = await ethers.getContractAt("CErc20Delegator",CEtherAddress);
    await cEther._setReserveFactor(parseEther("0.2"));
    console.log("cEther__setReserveFactor call success !!");
}

// 添加到市场
export const cEther__supportMarket = async (comptrollerG7Address:string, cEtherAddress:string) => {
    const cToken = await ethers.getContractAt("ComptrollerG7",comptrollerG7Address);
    await cToken._supportMarket(cEtherAddress);  //  把该ETH加入到市场中
    console.log("cEther__supportMarket call success !!")
}