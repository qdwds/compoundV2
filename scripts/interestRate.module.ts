import { ethers } from "hardhat";
import { contractAbi } from "../utils/contractInfo";
import { baseRatePerYear, jumpMultiplierPerYear, kink, multiplierPerYear } from "./config";


const JumpRateModelV2Name = "JumpRateModelV2";
export const jumpRateModelV2Deploy = async (owner: string) => {
    const JumpRateModelV2 = await ethers.getContractFactory(JumpRateModelV2Name);
    // 部署后的参数可以在 updateJumpRateModel 中修改
    const jumpRateModelV2 = await JumpRateModelV2.deploy(
        baseRatePerYear, 
        multiplierPerYear, 
        jumpMultiplierPerYear, 
        kink, 
        owner
    );console.log(await jumpRateModelV2.kink())
    await jumpRateModelV2.deployed();
    await contractAbi(jumpRateModelV2.address, JumpRateModelV2Name);
    return jumpRateModelV2;
}