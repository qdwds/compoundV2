import { ethers } from "hardhat";
import { contractAbi } from "../utils/contractInfo";

const usdtTokenName = "USDTToken"
export const USDTTokenDeploy = async () => {
    const USDT = await ethers.getContractFactory(usdtTokenName);
    const usdt = await USDT.deploy();
    await usdt.deployed();
    await contractAbi(usdt.address, usdtTokenName);
    return usdt;
}