import { ethers } from "hardhat";
import { contractAbi } from "../utils/contractInfo";

const usdtToken = "USDTToken"
const daiToken = "DAIToken"
export const USDTTokenDeploy = async () => {
    const USDT = await ethers.getContractFactory(usdtToken);
    const usdt = await USDT.deploy();
    await usdt.deployed();
    await contractAbi(usdt.address, usdtToken);
    return usdt;
}

export const DAITokenDeploy = async () => {
    const USDT = await ethers.getContractFactory(daiToken);
    const usdt = await USDT.deploy();
    await usdt.deployed();
    await contractAbi(usdt.address, daiToken);
    return usdt;
}