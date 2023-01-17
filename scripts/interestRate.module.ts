import { ethers } from "hardhat";
import { contractAbi } from "../utils/contractInfo";
import { baseRatePerYear, jumpMultiplierPerYear, kink, multiplierPerYear } from "./config";
import { parseEther, parseUnits } from "ethers/lib/utils"

const JumpRateModelV2Name = "JumpRateModelV2";
const whitePaperInterestRateModelName = "WhitePaperInterestRateModel";
export const jumpRateModelV2Deploy = async (owner: string) => {
    const JumpRateModelV2 = await ethers.getContractFactory(JumpRateModelV2Name);
    // 部署后的参数可以在 updateJumpRateModel 中修改
    const jumpRateModelV2 = await JumpRateModelV2.deploy(
        parseUnits("0.1"), //  年化利率, 
        parseEther("0.07"), 
        parseEther("3"), 
        parseEther("0.8"), 
        owner
    );
    await jumpRateModelV2.deployed();
    await contractAbi(jumpRateModelV2.address, JumpRateModelV2Name);
    return jumpRateModelV2;
}


export const WhitePaperInterestRateModelDeploy = async (owner: string) => {
    const WhitePaperInterestRateModel = await ethers.getContractFactory(whitePaperInterestRateModelName);
    // 部署后的参数可以在 updateJumpRateModel 中修改
    const whitePaperInterestRateModel = await WhitePaperInterestRateModel.deploy(
        parseUnits("0.1"), //  年化利率
        parseEther("0.07"), //  年华利率乘基
    );
    await whitePaperInterestRateModel.deployed();
    await contractAbi(whitePaperInterestRateModel.address, whitePaperInterestRateModelName);
    return whitePaperInterestRateModel;
}